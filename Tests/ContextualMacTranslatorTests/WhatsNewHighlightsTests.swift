import Foundation
import Testing

@testable import ContextualMacTranslator

/// v0.9.1 — pin the version-table that `AppDelegate.maybeShowWhatsNew`
/// uses to decide whether to pop the upgrade window. The v0.9.0 deliver-
/// phase review (MED-2) flagged the previous `hasPrefix("0.9.")` gate as
/// a v0.10.0 time bomb — the fix inverted the logic to a per-version
/// lookup, but the lookup itself had no test. These tests pin every
/// branch so a future build that adds entries without thinking about
/// the catch-all path triggers a failure rather than silent surprise.
@Suite("WhatsNewWindowController.highlights(for:)")
@MainActor
struct WhatsNewHighlightsTests {

    @Test("v0.9.0 returns the populated highlight list")
    func v0_9_0Lookup() {
        let result = WhatsNewWindowController.highlights(for: "0.9.0")
        #expect(result != nil)
        #expect(result?.isEmpty == false)
        // Three highlights: Shortcuts/Siri, OCR-from-screen, Settings pointer.
        #expect(result?.count == 3)
    }

    @Test("Unknown versions return nil (catch-all branch)")
    func unknownVersionReturnsNil() {
        // Earlier patches, future minors, and the empty string should
        // all funnel into the default branch. AppDelegate uses `nil` as
        // the gate that means 'silently mark this version seen without
        // popping a window' — verify the catch-all stays catch-all.
        for version in ["0.8.5", "0.9.1", "0.10.0", "1.0.0", "0.0.0", ""] {
            #expect(
                WhatsNewWindowController.highlights(for: version) == nil,
                "Expected nil for version '\(version)'"
            )
        }
    }

    @Test("Highlight payload uses SF Symbol names + non-empty title/body")
    func v0_9_0HighlightsAreWellFormed() throws {
        let highlights = try #require(WhatsNewWindowController.highlights(for: "0.9.0"))
        for h in highlights {
            #expect(!h.symbol.isEmpty, "SF Symbol name must be non-empty")
            #expect(!h.title.isEmpty, "Title must be non-empty")
            #expect(!h.body.isEmpty, "Body must be non-empty")
            // Each highlight has a unique UUID — used as the ForEach id
            // in the SwiftUI view. Duplicate ids would cause a runtime
            // assertion in SwiftUI.
        }
        let ids = highlights.map(\.id)
        #expect(Set(ids).count == ids.count, "Highlight ids must be unique")
    }

    @Test("v0_9_0Highlights static catalogue matches the lookup result")
    func staticCatalogueConsistency() {
        // The lookup at `case "0.9.0":` returns `v0_9_0Highlights`. Pin
        // that they stay aligned — if someone adds a highlight to the
        // static catalogue but forgets to thread it through the lookup,
        // this test fires.
        let viaLookup = WhatsNewWindowController.highlights(for: "0.9.0")
        let viaStatic = WhatsNewWindowController.v0_9_0Highlights
        #expect(viaLookup?.count == viaStatic.count)
    }
}
