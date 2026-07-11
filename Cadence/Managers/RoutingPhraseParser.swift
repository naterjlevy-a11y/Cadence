import Foundation

/// Output of the routing parser.
struct RouteParseResult {
    /// The matched destination, if any.
    let destination: Destination?
    /// User-defined target inside the destination (e.g. a specific Google Doc).
    let subdestination: Subdestination?
    /// The exact prefix phrase that matched (for display + history).
    let matchedPhrase: String?
    /// The dictation content, with the routing and subdestination phrases removed.
    let strippedText: String
    /// Confidence in the match (0...1). Below 0.5 = fallback recommended.
    let confidence: Float
    /// Set when the user clearly *tried* to route ("Hey …", "Open …") but the
    /// destination word didn't confidently match. Drives the
    /// "Destination not found. Did you mean X?" toast. The text still goes to
    /// the current app verbatim.
    var didYouMean: String?

    init(
        destination: Destination?,
        subdestination: Subdestination?,
        matchedPhrase: String?,
        strippedText: String,
        confidence: Float,
        didYouMean: String? = nil
    ) {
        self.destination = destination
        self.subdestination = subdestination
        self.matchedPhrase = matchedPhrase
        self.strippedText = strippedText
        self.confidence = confidence
        self.didYouMean = didYouMean
    }
}

/// Detects routing phrases at the beginning of dictation and strips them.
final class RoutingPhraseParser {
    /// The ONLY way to route is to address a destination with a greeting at
    /// the very start — "Hey Claude", "OK Gemini", "Yo Cursor". Anything else
    /// is dictated verbatim into the current app. We deliberately do NOT route
    /// on action verbs ("open …", "go to …") or a bare product name, because
    /// those fire on ordinary speech and silently open random apps.
    private let greetingVerbs: [String] = ["hey", "hey there", "hi", "hello", "okay", "ok", "yo", "yoh"]

    /// Alias of `greetingVerbs` for the exact "verb + alias" prefix pass.
    private var routingVerbs: [String] { greetingVerbs }

    /// Connector words that often appear between the destination and a
    /// subdestination — "Hey Google Docs, **to** Nate Levy", "**in** my essay".
    private let subConnectors: [String] = ["to", "in", "into", "for", "on"]

    private let registry: DestinationRegistry

    init(registry: DestinationRegistry = .shared) {
        self.registry = registry
    }

    /// Parse a transcript. Returns the destination (if any), an optional
    /// subdestination, the matched phrase, and the dictation content with
    /// the routing portion removed.
    func parse(_ rawTranscript: String) -> RouteParseResult {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RouteParseResult(destination: nil, subdestination: nil, matchedPhrase: nil, strippedText: "", confidence: 0)
        }

        guard UserPreferences.shared.enableSpokenRouting else {
            return RouteParseResult(destination: nil, subdestination: nil, matchedPhrase: nil, strippedText: trimmed, confidence: 1)
        }

        // Normalize: Apple Speech inserts a comma right after "Hey" / "OK" /
        // "Yo" much of the time ("Hey, Claude"). That breaks naive
        // hasPrefix("hey claude") matching. Strip leading punctuation and
        // collapse the first comma if it appears right after a routing verb.
        let normalized = Self.normalizeForMatching(trimmed)
        let lower = normalized.lowercased()

        // Build alias list, longest-first so multi-word aliases (e.g. "google docs")
        // beat single-word ones.
        let candidates = registry.destinations
            .filter(\.enabled)
            .flatMap { dest in dest.allAliases.map { (alias: $0, destination: dest) } }
            .sorted { $0.alias.count > $1.alias.count }

        for (alias, destination) in candidates {
            // Special case: "current_app" aliases require strong markers because
            // "here" / "this" are very common words.
            if destination.id == "current_app" {
                if let result = matchCurrentAppPhrase(in: normalized, alias: alias, destination: destination) {
                    return result
                }
                continue
            }

            // Pattern A: verb + alias (e.g. "hey claude", "open cursor", "yo gemini")
            for verb in routingVerbs {
                let prefix = "\(verb) \(alias)"
                if hasRoutingPrefix(lower, prefix: prefix) {
                    if let result = buildResult(
                        prefix: prefix,
                        source: normalized,
                        destination: destination,
                        matched: prefix,
                        baseConfidence: 0.95
                    ) {
                        return result
                    }
                }
            }

        }

        // A greeting was spoken ("Hey …") but no exact alias — fuzzy-match the
        // next word; if still no confident match, suggest the closest.
        if let greetingResult = matchAfterGreeting(in: normalized, lower: lower) {
            return greetingResult
        }

        return RouteParseResult(destination: nil, subdestination: nil, matchedPhrase: nil, strippedText: trimmed, confidence: 1)
    }

    /// Handles "Hey <word>" where <word> didn't match a destination exactly.
    /// A close match routes; otherwise we pass the text through to the current
    /// app and carry a `didYouMean` hint for the toast.
    private func matchAfterGreeting(in normalized: String, lower: String) -> RouteParseResult? {
        var verbUsed: String?
        var remainderLower = lower
        for verb in routingVerbs.sorted(by: { $0.count > $1.count }) where lower.hasPrefix("\(verb) ") {
            verbUsed = verb
            remainderLower = String(lower.dropFirst(verb.count + 1))
            break
        }
        guard let verb = verbUsed else { return nil }

        let nextWord = remainderLower
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        // Need a real, reasonably long word before we'll even consider routing.
        guard nextWord.count >= 4 else { return nil }

        // Only DISTINCTIVE mispronunciations — never common English words like
        // "chat", "cloud", "ocean" that would false-trigger during normal speech.
        let phonetic: [String: String] = [
            "claudia": "claude", "claudio": "claude", "clawd": "claude",
            "chatgpt": "chatgpt", "chatgbt": "chatgpt",
            "jiminy": "gemini", "gemeni": "gemini",
            "kurser": "cursor", "kursor": "cursor",
            "perplexity": "perplexity", "perplexed": "perplexity",
        ]
        let corrected = phonetic[nextWord] ?? nextWord

        var best: (dest: Destination, dist: Int)?
        for dest in registry.destinations.filter(\.enabled) where dest.id != "current_app" {
            for alias in dest.allAliases {
                let d = levenshtein(corrected, alias.lowercased())
                if best == nil || d < best!.dist { best = (dest, d) }
            }
        }
        guard let match = best else { return nil }

        // Only AUTO-ROUTE when the spoken word is essentially the alias (exact
        // or a single edit away). Anything looser pastes in place — a wrong app
        // opening is far more disruptive than a missed route.
        if match.dist <= 1 {
            let prefix = "\(verb) \(nextWord)"
            return buildResult(
                prefix: prefix,
                source: normalized,
                destination: match.dest,
                matched: prefix,
                baseConfidence: 0.85
            )
        }

        // Close-but-not-confident → don't route, just offer a "did you mean" hint.
        let suggestion = (match.dist <= 2 && nextWord.count >= 5) ? match.dest.displayName : nil
        return RouteParseResult(
            destination: nil,
            subdestination: nil,
            matchedPhrase: nil,
            strippedText: normalized.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: 1,
            didYouMean: suggestion
        )
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var row = Array(0...bChars.count)
        for (i, ca) in aChars.enumerated() {
            var prev = row[0]
            row[0] = i + 1
            for (j, cb) in bChars.enumerated() {
                let temp = row[j + 1]
                let cost = ca == cb ? 0 : 1
                row[j + 1] = min(row[j + 1] + 1, row[j] + 1, prev + cost)
                prev = temp
            }
        }
        return row[bChars.count]
    }

    /// True if `text` starts with `prefix` followed by a non-alphanumeric
    /// character (or end-of-string). This prevents "hey claude" from
    /// matching "hey claudette" while still allowing "hey claude," and
    /// "hey claude:" to match.
    private func hasRoutingPrefix(_ text: String, prefix: String) -> Bool {
        guard text.hasPrefix(prefix) else { return false }
        let endIndex = text.index(text.startIndex, offsetBy: prefix.count)
        if endIndex == text.endIndex { return true }
        let next = text[endIndex]
        return !next.isLetter && !next.isNumber
    }

    /// Normalize input for matching:
    /// - Drop leading non-letter characters (commas, ellipses, leftover punctuation).
    /// - Collapse "Hey," / "Okay," / "Yo," → "Hey ", "Okay ", "Yo " so that the
    ///   alias matcher doesn't need to know about ASR comma quirks.
    static func normalizeForMatching(_ input: String) -> String {
        var s = input
        while let first = s.first, !first.isLetter && !first.isNumber {
            s.removeFirst()
        }

        // Remove commas/periods immediately after common routing verbs.
        let leaders = ["hey", "okay", "ok", "yo", "open", "ask", "go to", "go",
                       "tell", "send to", "send", "launch", "show me", "show",
                       "switch to", "switch", "to", "in"]
        for leader in leaders {
            let patterns = ["\(leader),", "\(leader)."]
            for pattern in patterns {
                if s.lowercased().hasPrefix(pattern) {
                    let dropCount = pattern.count
                    let after = s.index(s.startIndex, offsetBy: dropCount)
                    s = String(s[..<s.index(s.startIndex, offsetBy: leader.count)]) + " " + s[after...]
                    s = s.replacingOccurrences(of: "  ", with: " ")
                    break
                }
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchCurrentAppPhrase(in input: String, alias: String, destination: Destination) -> RouteParseResult? {
        let lower = input.lowercased()
        let withComma = "\(alias),"
        if lower.hasPrefix(withComma) {
            return buildResult(
                prefix: withComma,
                source: input,
                destination: destination,
                matched: alias,
                baseConfidence: 0.9
            )
        }
        return nil
    }

    /// Strips the destination prefix, then looks for an optional subdestination
    /// at the start of the remainder ("nate levy, …" or "to nate levy, …").
    private func buildResult(
        prefix: String,
        source: String,
        destination: Destination,
        matched: String,
        baseConfidence: Float
    ) -> RouteParseResult? {
        guard source.count >= prefix.count else { return nil }
        var remainder = String(source.dropFirst(prefix.count))
        if let first = remainder.first, first == "," || first == "." || first == ":" {
            remainder.removeFirst()
        }
        remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to peel a subdestination off the front.
        let (sub, afterSub) = peelSubdestination(remainder, in: destination)
        return RouteParseResult(
            destination: destination,
            subdestination: sub,
            matchedPhrase: matched,
            strippedText: afterSub,
            confidence: baseConfidence
        )
    }

    /// If `text` begins with (optionally a connector word and then) the name
    /// of a subdestination of `destination`, return the subdestination plus
    /// the rest of the text. Otherwise return `(nil, text)`.
    private func peelSubdestination(_ text: String, in destination: Destination) -> (Subdestination?, String) {
        guard !destination.subdestinations.isEmpty, !text.isEmpty else { return (nil, text) }

        // Build (name, sub) pairs, longest-first so "nate levy capstone" beats "nate levy".
        let entries: [(name: String, sub: Subdestination)] = destination.subdestinations
            .flatMap { sub in sub.allMatchableNames.map { ($0, sub) } }
            .sorted { $0.name.count > $1.name.count }

        let lower = text.lowercased()

        // Optionally consume a connector ("to", "in", …) at the start, but
        // only if it's followed by a sub name. We try with and without.
        for (name, sub) in entries {
            // With connector: "to nate levy"
            for connector in subConnectors {
                let prefix = "\(connector) \(name)"
                if matchesAtStart(lower, prefix: prefix) {
                    return (sub, dropPrefix(prefix, from: text))
                }
            }
            // Bare name: "nate levy"
            if matchesAtStart(lower, prefix: name) {
                return (sub, dropPrefix(name, from: text))
            }
        }
        return (nil, text)
    }

    /// Whether `text` begins with `prefix` followed by a non-alphanumeric (or end).
    private func matchesAtStart(_ text: String, prefix: String) -> Bool {
        guard text.hasPrefix(prefix) else { return false }
        let endIndex = text.index(text.startIndex, offsetBy: prefix.count)
        if endIndex == text.endIndex { return true }
        let next = text[endIndex]
        return !next.isLetter && !next.isNumber
    }

    /// Drops `prefix.count` chars from `text` plus any single leading delimiter,
    /// then trims whitespace.
    private func dropPrefix(_ prefix: String, from text: String) -> String {
        var remainder = String(text.dropFirst(prefix.count))
        if let first = remainder.first, first == "," || first == "." || first == ":" {
            remainder.removeFirst()
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
