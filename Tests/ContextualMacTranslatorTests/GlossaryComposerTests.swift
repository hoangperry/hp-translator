import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("GlossaryComposer")
struct GlossaryComposerTests {

    @Test("Empty entries + empty blob → empty string (PromptBuilder's `(empty)` fallback triggers)")
    func bothEmpty() {
        let out = GlossaryComposer.compose(entries: [], legacyBlob: "")
        #expect(out == "")
    }

    @Test("Legacy blob only → blob flows verbatim (v0.9.x byte-identical)")
    func legacyOnly() {
        let blob = "React = リアクト\nReact Native = React Native"
        let out = GlossaryComposer.compose(entries: [], legacyBlob: blob)
        #expect(out == blob)
        // Critically: no '[Free-text glossary]' header is added when
        // the structured block is empty.
        #expect(!out.contains("[Free-text glossary]"))
    }

    @Test("Structured entries only → 'Glossary rules' block, no legacy section")
    func structuredOnly() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React"))
        ]
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "")
        #expect(out.hasPrefix("Glossary rules (apply exactly):"))
        #expect(out.contains("Don't translate: React"))
        #expect(!out.contains("[Free-text glossary]"))
    }

    @Test("Both present → structured block first, then '[Free-text glossary]' header + blob")
    func bothPresent() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React"))
        ]
        let blob = "OldKey = OldValue"
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: blob)
        // Structured block first
        #expect(out.hasPrefix("Glossary rules (apply exactly):"))
        // Then header
        #expect(out.contains("[Free-text glossary]"))
        // Then blob
        #expect(out.contains("OldKey = OldValue"))
        // Sanity: header sits between the two
        let headerRange = out.range(of: "[Free-text glossary]")!
        let blobRange = out.range(of: "OldKey = OldValue")!
        let dontRange = out.range(of: "Don't translate: React")!
        #expect(dontRange.upperBound < headerRange.lowerBound)
        #expect(headerRange.upperBound < blobRange.lowerBound)
    }

    @Test("dontTranslate entries are comma-joined under one bullet")
    func dontTranslateGrouping() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React")),
            GlossaryEntry(kind: .dontTranslate(term: "JIRA-1234")),
            GlossaryEntry(kind: .dontTranslate(term: "FREESHIP")),
        ]
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "")
        #expect(out.contains("Don't translate: React, JIRA-1234, FREESHIP"))
        // Only ONE 'Don't translate' line (grouped), not three.
        let count = out.components(separatedBy: "Don't translate:").count - 1
        #expect(count == 1)
    }

    @Test("alias + alwaysTranslate render as one-per-line directional pairs")
    func directionalPairs() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee")),
            GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "free shipping")),
        ]
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "")
        #expect(out.contains("- Always rewrite: \"shopee\" → \"Shopee\""))
        #expect(out.contains("- Always translate: \"freeship\" → \"free shipping\""))
    }

    @Test("Whitespace-only / empty payload entries are filtered out (no degenerate output)")
    func emptyEntriesFiltered() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "   ")),
            GlossaryEntry(kind: .alias(from: "", to: "Shopee")),
            GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "")),
        ]
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "")
        // Every entry has at least one empty field → all dropped →
        // structured block is empty → with empty blob the composer
        // returns "" (no '(empty)' marker, no header).
        #expect(out == "")
    }

    @Test("Entries beyond renderCap (50) are dropped from the output")
    func renderCap() {
        // 60 entries; only the first 50 should appear.
        let entries: [GlossaryEntry] = (1...60).map {
            GlossaryEntry(kind: .dontTranslate(term: "term\($0)"))
        }
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "")
        #expect(out.contains("term1,"))
        #expect(out.contains("term50"))
        #expect(!out.contains("term51"))
        #expect(!out.contains("term60"))
    }

    @Test("Whitespace-only legacy blob counts as empty for header decisions")
    func whitespaceLegacyTreatedEmpty() {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React"))
        ]
        // Pure whitespace blob → no '[Free-text glossary]' header.
        let out = GlossaryComposer.compose(entries: entries, legacyBlob: "   \n\n  ")
        #expect(!out.contains("[Free-text glossary]"))
        #expect(out.contains("Don't translate: React"))
    }
}
