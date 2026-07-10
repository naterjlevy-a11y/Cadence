import Foundation

struct CleanupContext {
    let destinationId: String?
    let destinationDisplayName: String?
    let preserveTechnicalTerms: Bool
}

protocol CleanupProvider: AnyObject {
    func clean(rawText: String, context: CleanupContext) -> String
    /// Lighter-weight pre-clean used when an LLM polish stage follows.
    /// Removes only the noise the model can't easily fix (fillers, repeated
    /// stutters, leading conjunctions, whitespace, brand caps). Leaves
    /// punctuation, lists, and sentence structure to the LLM.
    func preCleanForAI(rawText: String, context: CleanupContext) -> String
}

/// Deterministic, dependency-free cleanup. Removes filler words, fixes
/// double-words, normalizes whitespace, capitalizes sentences, and adds a
/// terminating punctuation if missing.
final class RuleBasedCleanupProvider: CleanupProvider {
    /// True verbal fillers only. We intentionally do NOT remove words like
    /// "like", "actually", or "literally" — they carry meaning in real speech.
    private static let fillerWords: Set<String> = [
        "um", "uh", "uhh", "umm", "er", "erm", "ah", "ahh", "hmm",
        "you know", "sort of", "kind of",
    ]

    /// Explicit correction phrases only. Broad patterns like bare "i mean"
    /// were deleting large chunks of legitimate dictation.
    private static let selfCorrectionTriggers: [String] = [
        "scratch that", "no wait", "wait no", "never mind", "nevermind",
    ]

    func clean(rawText: String, context: CleanupContext) -> String {
        let prefs = UserPreferences.shared
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Honor "raw" cleanup level by short-circuiting.
        if prefs.cleanupLevel == .raw {
            return text
        }

        // For long-form dictation (>~80 words), force a much lighter cleanup.
        // Long monologues regularly include phrases that look like filler in
        // isolation but carry meaning; aggressive cleanup has caused real
        // content loss. Light cleanup keeps everything except hard fillers.
        let wordCount = text.split { $0.isWhitespace }.count
        let effectiveLevel: CleanupLevel = wordCount > 80 ? .light : prefs.cleanupLevel

        // 1. Normalize whitespace.
        text = text.replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // 2. Strip leading conjunctions/fillers like "so um, ".
        text = stripLeadingFiller(text)

        // 3. Remove filler words (light/standard/professional).
        if prefs.removeFillerWords && effectiveLevel != .light {
            text = removeFillers(in: text)
        } else if prefs.removeFillerWords {
            // Even in light mode, drop the truly empty fillers.
            text = removeHardFillers(in: text)
        }

        // 4. Collapse repeated consecutive words (stutters).
        text = collapseRepeatedWords(text)

        // 5. Self-correction: only on explicit "scratch that" / "never mind" style phrases.
        if effectiveLevel == .professional {
            text = applySelfCorrection(text)
        }

        // 6. Spoken punctuation tokens -> real punctuation.
        text = applySpokenPunctuation(text)

        // 7. Auto-format spoken lists. Allowed at standard/professional. The
        //    detector requires at least two ordinals so accidental triggers
        //    on light cleanup are rare; this matches Wispr Flow's behavior.
        if prefs.autoFormatLists && effectiveLevel != .light {
            text = formatSpokenLists(text)
        }

        // 8. Capitalize sentence starts.
        text = capitalizeSentences(text)

        // 9. Brand dictionary (case-only fixes for known product names).
        if prefs.brandDictionaryEnabled {
            text = applyBrandDictionary(text)
        }

        // 10. Personal dictionary corrections (case-preserving).
        text = applyPersonalDictionary(text, terms: prefs.personalDictionary)

        // 11. Smart formatting — safe touch-ups that never remove words:
        //     lowercase "i" -> "I", common contractions, smart quotes, em dash.
        if prefs.smartFormattingEnabled {
            text = applySmartFormatting(text)
        }

        // 12. Terminating punctuation.
        if prefs.addPunctuation {
            text = ensureTerminatingPunctuation(text)
        }

        // 12. Final whitespace cleanup.
        text = text.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " ([,.!?;:])", with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 12. Safety net: if cleanup ate too much, fall back to a lighter pass.
        let original = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !original.isEmpty, !text.isEmpty {
            let ratio = Double(text.count) / Double(original.count)
            if ratio < 0.55 {
                Log.cleanup.warning("Cleanup removed \(Int((1 - ratio) * 100))% of text — using light pass")
                return lightCleanPass(rawText: original)
            }
        }
        if original.count > 12 && text.isEmpty {
            Log.cleanup.warning("Cleanup emptied transcript — using light pass")
            return lightCleanPass(rawText: original)
        }

        return text
    }

    /// Minimal cleanup used when standard rules would over-delete content.
    private func lightCleanPass(rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = removeHardFillers(in: text)
        text = collapseRepeatedWords(text)
        text = capitalizeSentences(text)
        if UserPreferences.shared.brandDictionaryEnabled {
            text = applyBrandDictionary(text)
        }
        if UserPreferences.shared.addPunctuation {
            text = ensureTerminatingPunctuation(text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pre-clean used when AI polish is about to run. We do the minimum
    /// needed to give the LLM a clean signal — no punctuation invention,
    /// no list formatting, no sentence capitalization, no spoken-punctuation
    /// rewrites. The LLM does those better with context.
    func preCleanForAI(rawText: String, context: CleanupContext) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = text.replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // Drop only the hard fillers — "um", "uh". Keep "you know" / "kind of"
        // because the model sometimes needs them to infer tone or list rhythm.
        text = removeHardFillers(in: text)

        // Collapse stutters: "I I I" -> "I". Apple Speech occasionally emits these.
        text = collapseRepeatedWords(text)

        // Apply brand-name capitalization so the LLM doesn't have to guess.
        if UserPreferences.shared.brandDictionaryEnabled {
            text = applyBrandDictionary(text)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Brand dictionary

    /// Pre-sorted longest-first so multi-word brands beat single-word prefixes.
    private static let sortedBrandTerms: [String] = BrandDictionary.canonical
        .sorted { $0.count > $1.count }

    private func applyBrandDictionary(_ input: String) -> String {
        var text = input
        for term in Self.sortedBrandTerms {
            // Build a case-insensitive whole-word regex. Terms with punctuation
            // (e.g. "Node.js", "X.com") use a more relaxed boundary.
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])"
            text = text.replacingOccurrences(
                of: pattern,
                with: term,
                options: .regularExpression
            )
        }
        return text
    }

    // MARK: - Smart formatting

    /// Safe, non-destructive polish for the look of the text. Designed to
    /// never delete or reorder words — only fix things Apple Speech doesn't.
    private func applySmartFormatting(_ input: String) -> String {
        var text = input

        // Standalone "i" -> "I" (whole word, case-sensitive).
        text = text.replacingOccurrences(
            of: "\\bi\\b",
            with: "I",
            options: .regularExpression
        )

        // Common missing apostrophes in contractions. Whole-word, case-insensitive,
        // preserves the leading character's case via per-pair regex.
        let contractions: [(String, String)] = [
            ("\\bi m\\b", "I'm"),
            ("\\bim\\b", "I'm"),
            ("\\bdont\\b", "don't"),
            ("\\bwont\\b", "won't"),
            ("\\bcant\\b", "can't"),
            ("\\bisnt\\b", "isn't"),
            ("\\barent\\b", "aren't"),
            ("\\bwasnt\\b", "wasn't"),
            ("\\bwerent\\b", "weren't"),
            ("\\bhasnt\\b", "hasn't"),
            ("\\bhavent\\b", "haven't"),
            ("\\bhadnt\\b", "hadn't"),
            ("\\bdoesnt\\b", "doesn't"),
            ("\\bdidnt\\b", "didn't"),
            ("\\bcouldnt\\b", "couldn't"),
            ("\\bshouldnt\\b", "shouldn't"),
            ("\\bwouldnt\\b", "wouldn't"),
            ("\\byoure\\b", "you're"),
            ("\\bwere\\b", "we're"), // ambiguous with past-tense "were", but in modern dictation usually correct
            ("\\btheyre\\b", "they're"),
            ("\\bits a\\b", "it's a"),
            ("\\bthats\\b", "that's"),
            ("\\bwhats\\b", "what's"),
            ("\\bwhos\\b", "who's"),
            ("\\bhes\\b", "he's"),
            ("\\bshes\\b", "she's"),
            ("\\blets\\b", "let's"),
            ("\\byoull\\b", "you'll"),
            ("\\bill\\b", "I'll"),
            ("\\btheyll\\b", "they'll"),
            ("\\bwell be\\b", "we'll be"),
        ]
        for (pattern, replacement) in contractions {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Lowercase ASCII period-space-letter pattern -> proper sentence-case.
        // Apple Speech sometimes lowercases the first letter after a period.
        text = text.replacingOccurrences(
            of: "([.!?]) ([a-z])",
            with: "$1 ",
            options: .regularExpression
        )
        // Re-run capitalizeSentences so any newly-uncased sentence starts get fixed.
        text = capitalizeSentences(text)

        // Collapse double spaces.
        text = text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)

        // Smart quotes & dashes (look much better in chat UIs and docs).
        text = applySmartQuotes(text)
        text = text.replacingOccurrences(of: " -- ", with: " — ")
        text = text.replacingOccurrences(of: " - ", with: " — ")
        text = text.replacingOccurrences(of: "\\.\\.\\.", with: "…", options: .regularExpression)

        return text
    }

    /// Curly quotes via simple state machine. Doesn't try to be perfect on
    /// nested quotes — just gets the common cases right.
    private func applySmartQuotes(_ input: String) -> String {
        var out = ""
        var openDouble = true
        var openSingle = true
        for ch in input {
            switch ch {
            case "\"":
                out.append(openDouble ? "“" : "”")
                openDouble.toggle()
            case "'":
                // Heuristic: if the previous char is a letter, this is an
                // apostrophe (e.g. "it's"). Only flip the quote state for
                // standalone single quotes.
                if let last = out.last, last.isLetter {
                    out.append("’")
                } else {
                    out.append(openSingle ? "‘" : "’")
                    openSingle.toggle()
                }
            default:
                out.append(ch)
            }
        }
        return out
    }

    // MARK: - Helpers

    private func stripLeadingFiller(_ input: String) -> String {
        var s = input
        let leading = ["so", "okay", "ok", "well", "alright", "right", "look", "listen"]
        var changed = true
        while changed {
            changed = false
            let lower = s.lowercased()
            for token in leading {
                let prefix1 = "\(token) "
                let prefix2 = "\(token), "
                if lower.hasPrefix(prefix1) {
                    s = String(s.dropFirst(prefix1.count))
                    changed = true
                    break
                }
                if lower.hasPrefix(prefix2) {
                    s = String(s.dropFirst(prefix2.count))
                    changed = true
                    break
                }
            }
        }
        return s
    }

    private func removeHardFillers(in input: String) -> String {
        let hard = ["um", "uh", "uhh", "umm", "er", "erm", "ah", "ahh"]
        return removeWords(hard, in: input)
    }

    private func removeFillers(in input: String) -> String {
        let words = Array(Self.fillerWords)
        return removeWords(words, in: input)
    }

    private func removeWords(_ words: [String], in input: String) -> String {
        var out = input
        for word in words {
            let pattern = "(?i)(?<=\\s|^|[,.!?;:])\(NSRegularExpression.escapedPattern(for: word))(?=\\s|$|[,.!?;:])"
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return out
    }

    private func collapseRepeatedWords(_ input: String) -> String {
        let pattern = "(?i)\\b(\\w+)(\\s+\\1\\b)+"
        return input.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    private func applySelfCorrection(_ input: String) -> String {
        var text = input
        for trigger in Self.selfCorrectionTriggers {
            // Pattern: "anything , trigger , correction" — keep what comes after.
            let pattern = "(?i)(.*?)(?:[,.\\s])\\s*\(NSRegularExpression.escapedPattern(for: trigger))[,\\s]+"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { continue }
            let upper = match.range.upperBound
            guard upper >= 0, upper <= nsText.length else { continue }
            text = nsText.substring(from: upper)
        }
        return text
    }

    private func applySpokenPunctuation(_ input: String) -> String {
        var t = input
        let map: [(pattern: String, replacement: String)] = [
            ("(?i)\\bnew paragraph\\b", "\n\n"),
            ("(?i)\\bnew line\\b", "\n"),
            ("(?i)\\bperiod\\b", "."),
            ("(?i)\\bcomma\\b", ","),
            ("(?i)\\bquestion mark\\b", "?"),
            ("(?i)\\bexclamation point\\b", "!"),
            ("(?i)\\bexclamation mark\\b", "!"),
            ("(?i)\\bcolon\\b", ":"),
            ("(?i)\\bsemicolon\\b", ";"),
            ("(?i)\\bdash\\b", "—"),
            ("(?i)\\bopen quote\\b", "\""),
            ("(?i)\\bclose quote\\b", "\""),
        ]
        for (pattern, replacement) in map {
            t = t.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return t
    }

    private func formatSpokenLists(_ input: String) -> String {
        // Detect "first X second Y third Z" patterns and convert to a numbered list.
        let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        let lower = input.lowercased()
        var hits: [(ordinal: Int, range: NSRange)] = []
        for (index, ord) in ordinals.enumerated() {
            let pattern = "(?i)\\b\(ord)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
                for m in matches { hits.append((index, m.range)) }
            }
        }
        // Need at least 2 ordinals to consider it a list.
        let sortedHits = hits.sorted { $0.range.location < $1.range.location }
        guard sortedHits.count >= 2 else { return input }

        let nsInput = input as NSString
        var pieces: [String] = []
        if sortedHits.first!.range.location > 0 {
            let prefix = nsInput.substring(to: sortedHits.first!.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { pieces.append(prefix) }
        }
        for (i, hit) in sortedHits.enumerated() {
            let start = hit.range.location + hit.range.length
            let end = (i + 1 < sortedHits.count) ? sortedHits[i + 1].range.location : nsInput.length
            var item = nsInput.substring(with: NSRange(location: start, length: end - start))
            item = item.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            if !item.isEmpty {
                pieces.append("\(hit.ordinal + 1). \(item)")
            }
        }
        return pieces.joined(separator: "\n")
    }

    private func capitalizeSentences(_ input: String) -> String {
        let pattern = "(^|[.!?]\\s+)(\\p{L})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
        let mutable = NSMutableString(string: input)
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        for match in matches.reversed() {
            let letterRange = match.range(at: 2)
            if letterRange.location != NSNotFound {
                let letter = mutable.substring(with: letterRange).uppercased()
                mutable.replaceCharacters(in: letterRange, with: letter)
            }
        }
        // Capitalize standalone "i".
        let result = (mutable as String).replacingOccurrences(
            of: "(^|\\s)i(\\s|$|')",
            with: "$1I$2",
            options: .regularExpression
        )
        return result
    }

    private func applyPersonalDictionary(_ input: String, terms: [String]) -> String {
        guard !terms.isEmpty else { return input }
        var t = input
        for term in terms {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = "(?i)\\b\(escaped)\\b"
            t = t.replacingOccurrences(of: pattern, with: term, options: .regularExpression)
        }
        return t
    }

    private func ensureTerminatingPunctuation(_ input: String) -> String {
        guard let last = input.last else { return input }
        if "?.!:;\"'".contains(last) { return input }
        if input.hasSuffix("\n") { return input }
        return input + "."
    }
}

/// Routes cleanup through the configured provider.
final class CleanupService {
    static let shared = CleanupService()

    private var provider: CleanupProvider

    init(provider: CleanupProvider = RuleBasedCleanupProvider()) {
        self.provider = provider
    }

    func setProvider(_ provider: CleanupProvider) {
        self.provider = provider
    }

    func clean(rawText: String, context: CleanupContext) -> String {
        provider.clean(rawText: rawText, context: context)
    }

    func preCleanForAI(rawText: String, context: CleanupContext) -> String {
        provider.preCleanForAI(rawText: rawText, context: context)
    }
}
