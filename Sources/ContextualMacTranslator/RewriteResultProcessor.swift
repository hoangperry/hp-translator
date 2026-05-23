import Foundation

/// Post-processing for raw LLM output of a rewrite job. Pure + synchronous
/// so it is trivially testable. Two jobs:
///  1. `clean` — strip the cruft an LLM adds despite "output only the text"
///     (code fences, leading "Rewritten:" labels, outer quotes).
///  2. `isLikelyRefusal` — heuristic detection of a refusal / moralizing
///     reply so the workflow can retry or fall back instead of pasting it.
enum RewriteResultProcessor {
    /// Leading labels an LLM may prepend, lowercased. Matched only at the
    /// very start, followed by a colon.
    private static let leadingLabels = [
        "rewritten", "rewrite", "rewritten message", "output", "result",
        "bản viết lại", "câu viết lại", "kết quả", "viết lại",
    ]

    /// Refusal / moralizing markers. Anchored to a first-person speaker
    /// ("I", "tôi", "mình") so a rewrite that legitimately contains a
    /// negation (em/anh/chị pronouns) is not mistaken for a refusal.
    private static let refusalMarkers = [
        "i can't", "i can’t", "i cannot", "i can not", "i'm not able",
        "i am not able", "i'm unable", "i am unable", "i won't", "i will not",
        "i'd rather not", "i would rather not",
        "i'm sorry, but i", "i'm sorry but i", "i am sorry, but i",
        "sorry, i ", "sorry but i ", "as an ai",
        "tôi không thể", "mình không thể", "tôi không được", "rất tiếc, tôi",
        "tôi e rằng", "tôi xin lỗi nhưng tôi", "tôi rất tiếc",
        "xin lỗi, tôi", "xin lỗi nhưng tôi",
    ]

    /// Strip code fences, a leading label, and matching outer quotes.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip a ```…``` fence wrapping the whole output.
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        text = stripLeadingLabel(text)
        return PromptBuilder.normalize(text)
    }

    /// `true` when `output` reads like a refusal rather than a rewrite.
    /// Empty output also counts — there is nothing usable to paste.
    static func isLikelyRefusal(_ output: String) -> Bool {
        let lower = output
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return true }
        // A refusal leads with the marker; checking only the prefix avoids
        // flagging a long, valid rewrite that contains a negation later.
        let prefix = String(lower.prefix(90))
        return refusalMarkers.contains { prefix.contains($0) }
    }

    /// v0.8.5 — split a multi-variant rewrite response into its
    /// component drafts. The model is instructed to separate variants
    /// with `PromptBuilder.variantSentinel` (`---VARIANT---`) on its own
    /// line. We:
    ///   1. Split on the sentinel.
    ///   2. Fall back to numbered-list heuristics (`1.` / `1)` / `**1**`
    ///      at line start) if the sentinel produced only one chunk —
    ///      some models ignore the sentinel and number anyway.
    ///   3. `clean` each chunk + drop empties + drop likely refusals.
    /// Returns an empty array when nothing survives (caller falls back
    /// to single-variant retry).
    static func splitVariants(_ raw: String) -> [String] {
        let primary = splitOnSentinel(raw)
        let candidates = primary.count >= 2 ? primary : splitOnNumberedList(raw)
        let cleaned = candidates
            .map { clean($0) }
            .filter { !$0.isEmpty && !isLikelyRefusal($0) }
        // Drop duplicates while preserving order — some models echo the
        // same variant twice when they run out of ideas.
        var seen = Set<String>()
        var out: [String] = []
        for v in cleaned where seen.insert(v).inserted {
            out.append(v)
        }
        return out
    }

    private static func splitOnSentinel(_ raw: String) -> [String] {
        let sentinel = PromptBuilder.variantSentinel
        return raw
            .components(separatedBy: sentinel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Fallback: parse `1. ...\n2. ...\n3. ...` (and `1)`, `**1.**`,
    /// `Variant 1:`) variants when the model ignored the sentinel.
    /// Splits on lines that look like the start of a numbered item.
    private static func splitOnNumberedList(_ raw: String) -> [String] {
        let lines = raw.components(separatedBy: "\n")
        var chunks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if looksLikeListItemStart(line) {
                if !current.isEmpty { chunks.append(current) }
                current = [stripListMarker(line)]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        // Only treat this as a variant list if we found at least 2 markers.
        guard chunks.count >= 2 else { return [raw] }
        return chunks.map { $0.joined(separator: "\n") }
    }

    private static func looksLikeListItemStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // 1. / 1) / 1: — but only single/double-digit prefixes so a body
        // sentence starting with a year ("2024 was…") isn't a false hit.
        for prefix in ["1.", "2.", "3.", "4.", "5.",
                       "1)", "2)", "3)", "4)", "5)",
                       "**1.", "**2.", "**3.", "**4.", "**5.",
                       "Variant 1", "Variant 2", "Variant 3"] {
            if trimmed.hasPrefix(prefix) { return true }
        }
        return false
    }

    private static func stripListMarker(_ line: String) -> String {
        var s = line
        // Strip a leading run of digits + closing punctuation + label.
        while let first = s.first, first == " " || first == "\t" || first == "*" {
            s.removeFirst()
        }
        // Drop "Variant N:" / "Variant N -" labels.
        let lower = s.lowercased()
        if lower.hasPrefix("variant ") {
            if let colon = s.firstIndex(where: { $0 == ":" || $0 == "-" }) {
                s = String(s[s.index(after: colon)...])
            }
        }
        // Drop "N." / "N)" prefix.
        var i = s.startIndex
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        if i > s.startIndex, i < s.endIndex, ".)".contains(s[i]) {
            s = String(s[s.index(after: i)...])
        }
        // Drop bold-closing markers / leading ws.
        return s.replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingLabel(_ text: String) -> String {
        let lowered = text.lowercased()
        for label in leadingLabels {
            for colon in [":", "："] {
                let token = label + colon
                if lowered.hasPrefix(token) {
                    return String(text.dropFirst(token.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return text
    }
}
