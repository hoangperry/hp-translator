import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("GlossaryEntry Codable round-trip")
struct GlossaryEntryCodableTests {

    @Test("dontTranslate entry round-trips term verbatim")
    func dontTranslateRoundTrip() throws {
        let entry = GlossaryEntry(kind: .dontTranslate(term: "React"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GlossaryEntry.self, from: data)
        #expect(decoded == entry)
        if case .dontTranslate(let term) = decoded.kind {
            #expect(term == "React")
        } else {
            Issue.record("Expected .dontTranslate, got \(decoded.kind)")
        }
    }

    @Test("alias entry round-trips from + to")
    func aliasRoundTrip() throws {
        let entry = GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GlossaryEntry.self, from: data)
        #expect(decoded == entry)
        if case .alias(let from, let to) = decoded.kind {
            #expect(from == "shopee")
            #expect(to == "Shopee")
        } else {
            Issue.record("Expected .alias, got \(decoded.kind)")
        }
    }

    @Test("alwaysTranslate entry round-trips term + to")
    func alwaysTranslateRoundTrip() throws {
        let entry = GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "free shipping"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GlossaryEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("Array of mixed-kind entries round-trips order + contents")
    func arrayRoundTrip() throws {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React")),
            GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee")),
            GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "free shipping")),
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([GlossaryEntry].self, from: data)
        #expect(decoded == entries)
        #expect(decoded.count == 3)
    }

    @Test("Unknown KindTag fails decoding (forward-compat fail-closed)")
    func unknownKindFailsClosed() {
        // What a future v0.10.x build might persist with a new
        // `.scoped(...)` kind. Older builds should refuse to decode
        // rather than silently misinterpret — SettingsStore.init
        // catches the failure by falling back to `glossaryEntries = []`.
        let forwardShape = Data("""
        {"id":"F47AC10B-58CC-4372-A567-0E02B2C3D479","kind":"scoped","term":"X","to":"Y"}
        """.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GlossaryEntry.self, from: forwardShape)
        }
    }

    @Test("Missing payload field fails decoding")
    func missingPayloadFails() {
        // alias requires both `from` and `to` — missing `to` should
        // throw, not silently default to empty string.
        let bad = Data("""
        {"id":"F47AC10B-58CC-4372-A567-0E02B2C3D479","kind":"alias","from":"shopee"}
        """.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GlossaryEntry.self, from: bad)
        }
    }

    @Test("ID is preserved across encode + decode")
    func idPreserved() throws {
        let id = UUID()
        let entry = GlossaryEntry(id: id, kind: .dontTranslate(term: "JIRA-1234"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GlossaryEntry.self, from: data)
        #expect(decoded.id == id)
    }

    @Test("Empty array round-trips cleanly")
    func emptyArrayRoundTrip() throws {
        let entries: [GlossaryEntry] = []
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([GlossaryEntry].self, from: data)
        #expect(decoded.isEmpty)
    }
}

@Suite("GlossaryEntry.decodeArray (partial recovery)")
struct GlossaryEntryDecodeArrayTests {

    @Test("All-valid array decodes to the same shape as plain JSONDecoder")
    func allValidEquivalent() throws {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(kind: .dontTranslate(term: "React")),
            GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee")),
        ]
        let data = try JSONEncoder().encode(entries)
        let recovered = GlossaryEntry.decodeArray(from: data)
        let plain = try JSONDecoder().decode([GlossaryEntry].self, from: data)
        #expect(recovered == plain)
        #expect(recovered.count == 2)
    }

    @Test("Mixed array with one unknown KindTag preserves the valid entries (H3 fix)")
    func mixedArrayPreservesValid() {
        // Simulates v0.10.0 reading data persisted by a hypothetical
        // v0.10.1 that ships a `.scoped` KindTag. Pre-H3-fix behaviour:
        // whole list nuked → []. Post-fix: valid entries survive.
        let mixed = Data("""
        [
          {"id":"00000000-0000-0000-0000-000000000001","kind":"dontTranslate","term":"React"},
          {"id":"00000000-0000-0000-0000-000000000002","kind":"scoped","term":"X","to":"Y"},
          {"id":"00000000-0000-0000-0000-000000000003","kind":"alias","from":"shopee","to":"Shopee"}
        ]
        """.utf8)
        let recovered = GlossaryEntry.decodeArray(from: mixed)
        #expect(recovered.count == 2)
        #expect(recovered.contains { entry in
            if case .dontTranslate(let term) = entry.kind { return term == "React" }
            return false
        })
        #expect(recovered.contains { entry in
            if case .alias(let from, let to) = entry.kind { return from == "shopee" && to == "Shopee" }
            return false
        })
    }

    @Test("Corrupted outer shape returns empty array (still no crash)")
    func corruptedOuterShapeReturnsEmpty() {
        let notAnArray = Data("\"oops, this is a string\"".utf8)
        #expect(GlossaryEntry.decodeArray(from: notAnArray) == [])

        let garbage = Data("not json at all".utf8)
        #expect(GlossaryEntry.decodeArray(from: garbage) == [])
    }

    @Test("Empty array round-trips through decodeArray")
    func emptyArrayPreserved() throws {
        let data = try JSONEncoder().encode([GlossaryEntry]())
        #expect(GlossaryEntry.decodeArray(from: data) == [])
    }
}

@Suite("GlossaryEntry display helpers")
struct GlossaryEntryDisplayTests {

    @Test("kindLabel returns user-facing pill text for each kind")
    func kindLabels() {
        #expect(GlossaryEntry(kind: .dontTranslate(term: "X")).kindLabel == "Don't translate")
        #expect(GlossaryEntry(kind: .alias(from: "x", to: "y")).kindLabel == "Alias")
        #expect(GlossaryEntry(kind: .alwaysTranslate(term: "x", to: "y")).kindLabel == "Always translate")
    }

    @Test("primaryTerm extracts the configured term for each kind")
    func primaryTerms() {
        #expect(GlossaryEntry(kind: .dontTranslate(term: "React")).primaryTerm == "React")
        #expect(GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee")).primaryTerm == "shopee")
        #expect(GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "free shipping")).primaryTerm == "freeship")
    }

    @Test("secondaryValue is empty for dontTranslate; populated for alias/alwaysTranslate")
    func secondaryValues() {
        #expect(GlossaryEntry(kind: .dontTranslate(term: "React")).secondaryValue == "")
        #expect(GlossaryEntry(kind: .alias(from: "shopee", to: "Shopee")).secondaryValue == "Shopee")
        #expect(GlossaryEntry(kind: .alwaysTranslate(term: "freeship", to: "free shipping")).secondaryValue == "free shipping")
    }
}
