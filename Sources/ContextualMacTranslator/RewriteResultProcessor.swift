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
