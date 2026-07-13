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
    /// Includes the common ASR manglings of "hey" (it's one syllable and gets
    /// heard as "hay" / "heya" / "hi" constantly). "hey there" stays longest so
    /// it's stripped whole before the bare "hey".
    private let greetingVerbs: [String] = [
        "hey there", "hello", "hey", "hay", "heya", "hi", "yo", "yoh", "okay", "ok"
    ]

    /// The subset of greetings short enough that Apple Speech routinely glues
    /// them onto the next word ("heyclaude", "yochat"). Used for un-gluing.
    private let gluableGreetings: [String] = ["heythere", "hey", "hay", "heya", "yo"]

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

        // "current_app" uses distinctive markers ("here," / "this,") and is the
        // one destination that does NOT require a greeting indicator.
        for dest in registry.destinations where dest.enabled && dest.id == "current_app" {
            for alias in dest.allAliases {
                if let result = matchCurrentAppPhrase(in: normalized, alias: alias, destination: dest) {
                    return result
                }
            }
        }

        // Every other destination REQUIRES a greeting indicator at the very
        // start ("hey", "ok", "yo" …) — the baseball sign. Given that gate, we
        // resolve the destination generously from whatever follows.
        if let routed = matchGreetingRoute(normalized: normalized, lower: lower) {
            return routed
        }

        return RouteParseResult(destination: nil, subdestination: nil, matchedPhrase: nil, strippedText: trimmed, confidence: 1)
    }

    /// Given the greeting indicator at the start, intelligently resolve the
    /// destination from the words that follow — even when Apple Speech mangles
    /// or comma-splits the app name ("hey chat, GBT" → ChatGPT). We collapse
    /// spaces/punctuation and test the first one-to-three spoken words against
    /// every destination's aliases (also collapsed), so multi-word names match.
    private func matchGreetingRoute(normalized: String, lower: String) -> RouteParseResult? {
        // 1. Require and strip the greeting indicator (longest verb first).
        var verbUsed: String?
        var remainderRaw = ""
        for g in routingVerbs.sorted(by: { $0.count > $1.count }) where lower.hasPrefix("\(g) ") {
            verbUsed = g
            remainderRaw = String(normalized.dropFirst(g.count + 1))
            break
        }

        // 1b. No spaced greeting — try an un-glued one ("heyclaude", "yochat").
        //     Only for the short greetings ASR runs together, and only when a
        //     real chunk of word follows (so we never split "heyday"/"history").
        if verbUsed == nil {
            let tokens = normalized.split(separator: " ").map(String.init)
            if let firstTok = tokens.first {
                let firstCollapsed = Self.collapse(firstTok)
                for g in gluableGreetings.sorted(by: { $0.count > $1.count })
                where firstCollapsed.hasPrefix(g) && firstCollapsed.count >= g.count + 3 {
                    verbUsed = g
                    let leftover = String(firstCollapsed.dropFirst(g.count))
                    remainderRaw = ([leftover] + tokens.dropFirst()).joined(separator: " ")
                    break
                }
            }
        }

        guard let verb = verbUsed else { return nil }

        // 2. Tokenize the remainder. Keep the raw tokens (to rebuild the content)
        //    alongside clean collapsed words (to match).
        let rawTokens = remainderRaw.split(separator: " ").map(String.init)
        let words = rawTokens.map { Self.collapse($0) }
        guard let firstWord = words.first, !firstWord.isEmpty else { return nil }

        // 3. Build collapsed alias keys once.
        var aliasKeys: [(dest: Destination, key: String)] = []
        for dest in registry.destinations where dest.enabled && dest.id != "current_app" {
            for alias in dest.allAliases {
                let key = Self.collapse(alias)
                if !key.isEmpty { aliasKeys.append((dest, key)) }
            }
        }

        // 4. Test candidates built from the first 1…3 spoken words joined with no
        //    spaces ("chat" then "chatgbt" then "chatgbtplease"). Smaller edit
        //    distance wins; ties prefer consuming more words (the fuller name).
        var best: (dest: Destination, dist: Int, wordsUsed: Int)?
        let maxWords = min(3, words.count)
        for n in 1...maxWords where !words[n - 1].isEmpty {
            let candidate = Self.phoneticCollapse(words[0..<n].joined())
            guard candidate.count >= 2 else { continue }
            for ak in aliasKeys {
                let d = levenshtein(candidate, ak.key)
                guard d <= allowedDistance(forKeyLength: ak.key.count) else { continue }
                let better = best.map { d < $0.dist || (d == $0.dist && n > $0.wordsUsed) } ?? true
                if better { best = (ak.dest, d, n) }
            }
        }

        guard let match = best else {
            // Greeting was spoken but nothing matched — offer a "did you mean".
            return RouteParseResult(
                destination: nil, subdestination: nil, matchedPhrase: nil,
                strippedText: normalized.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: 1,
                didYouMean: closestSuggestion(for: Self.phoneticCollapse(firstWord))
            )
        }

        // 5. Rebuild the content from the raw tokens after the consumed words.
        var remainder = rawTokens.dropFirst(match.wordsUsed).joined(separator: " ")
        if let f = remainder.first, f == "," || f == "." || f == ":" { remainder.removeFirst() }
        remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)

        let (sub, afterSub) = peelSubdestination(remainder, in: match.dest)
        let matchedPhrase = "\(verb) \(rawTokens.prefix(match.wordsUsed).joined(separator: " "))"
        return RouteParseResult(
            destination: match.dest,
            subdestination: sub,
            matchedPhrase: matchedPhrase,
            strippedText: afterSub,
            confidence: match.dist == 0 ? 0.95 : 0.85
        )
    }

    /// Allowed edit distance scales with alias length: short aliases ("gpt")
    /// demand an exact hit, longer ones tolerate a mangled character or two.
    private func allowedDistance(forKeyLength len: Int) -> Int {
        switch len {
        case 0...4: return 0
        case 5...7: return 1
        default: return 2
        }
    }

    /// When a greeting was spoken but nothing matched confidently, find the
    /// closest destination name for a "Did you mean X?" hint (no routing).
    private func closestSuggestion(for candidate: String) -> String? {
        guard candidate.count >= 4 else { return nil }
        var best: (name: String, dist: Int)?
        for dest in registry.destinations where dest.enabled && dest.id != "current_app" {
            for alias in dest.allAliases {
                let d = levenshtein(candidate, Self.collapse(alias))
                if best == nil || d < best!.dist { best = (dest.displayName, d) }
            }
        }
        guard let b = best, b.dist <= 2 else { return nil }
        return b.name
    }

    /// Lowercase and strip everything that isn't a letter or digit.
    static func collapse(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }

    /// Collapse + a few distinctive sound-alike fixes the alias lists don't
    /// already cover (Apple Speech loves "GBT" for "GPT").
    static func phoneticCollapse(_ collapsed: String) -> String {
        collapsed.replacingOccurrences(of: "gbt", with: "gpt")
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
