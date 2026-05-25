import Foundation

/// v0.10.0 — pure composer that turns the v0.10.0 typed entries + the
/// v0.9.x free-text blob into one glossary string the LLM sees.
///
/// Output shape (from `docs/v0.10.0/define.md` §1 C.3):
/// ```
/// Glossary rules (apply exactly):
/// - Don't translate: React, JIRA-1234
/// - Always rewrite: "shopee" → "Shopee"
/// - Always translate: "freeship" → "free shipping"
///
/// [Free-text glossary]
/// <existing glossary string blob, if non-empty>
/// ```
///
/// Both halves are optional: empty entries → no structured block;
/// empty blob → no legacy section. When BOTH are empty, returns `""`
/// so PromptBuilder's existing `(empty)` fallback triggers unchanged.
enum GlossaryComposer {

    /// Hard cap on rendered entries — defensive double-bound on top of
    /// the UI's `entryCap` (in `SettingsGlossarySection`). Bounds prompt
    /// budget even if persisted state somehow exceeds it.
    static let renderCap = 50

    static func compose(
        entries: [GlossaryEntry],
        legacyBlob: String
    ) -> String {
        let structured = renderStructured(entries)
        let trimmedLegacy = legacyBlob.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (structured.isEmpty, trimmedLegacy.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return legacyBlob
        case (false, true):
            return structured
        case (false, false):
            return structured + "\n\n[Free-text glossary]\n" + legacyBlob
        }
    }

    /// Group entries by kind so the LLM sees `Don't translate: X, Y, Z`
    /// as a comma-joined list instead of three separate lines — fewer
    /// instructions to parse, cheaper attention. Aliases + always-
    /// translate stay one-per-line because each is a directional pair.
    private static func renderStructured(_ entries: [GlossaryEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let capped = Array(entries.prefix(renderCap))

        var dontTranslate: [String] = []
        var aliases: [(from: String, to: String)] = []
        var alwaysTranslate: [(term: String, to: String)] = []

        for entry in capped {
            switch entry.kind {
            case .dontTranslate(let term):
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { dontTranslate.append(trimmed) }
            case .alias(let from, let to):
                let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
                let t = to.trimmingCharacters(in: .whitespacesAndNewlines)
                if !f.isEmpty && !t.isEmpty { aliases.append((f, t)) }
            case .alwaysTranslate(let term, let to):
                let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
                let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
                if !term.isEmpty && !to.isEmpty {
                    alwaysTranslate.append((term, to))
                }
            }
        }

        // Every kind empty after trimming → no structured block emitted.
        guard !dontTranslate.isEmpty || !aliases.isEmpty || !alwaysTranslate.isEmpty else {
            return ""
        }

        var lines: [String] = ["Glossary rules (apply exactly):"]
        if !dontTranslate.isEmpty {
            lines.append("- Don't translate: " + dontTranslate.joined(separator: ", "))
        }
        for alias in aliases {
            lines.append("- Always rewrite: \"\(alias.from)\" → \"\(alias.to)\"")
        }
        for at in alwaysTranslate {
            lines.append("- Always translate: \"\(at.term)\" → \"\(at.to)\"")
        }
        return lines.joined(separator: "\n")
    }
}
