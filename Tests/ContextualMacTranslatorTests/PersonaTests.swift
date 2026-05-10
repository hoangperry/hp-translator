import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("Persona policy")
struct PersonaTests {
    @Test("Japanese keigo defaults to preview-before-send (US-5 / Define Q9)")
    func keigoPreviewDefault() {
        #expect(Persona.japaneseBusiness.previewByDefault == true)
    }

    @Test("Japanese casual defaults to auto-send (Define Q9)")
    func casualAutoSend() {
        #expect(Persona.japaneseCasual.previewByDefault == false)
    }

    @Test("Vietnamese reader (inbound) does not preview")
    func inboundNoPreview() {
        #expect(Persona.vietnameseReader.previewByDefault == false)
    }

    @Test("All legacy personas have a non-empty display badge")
    func badgesPresent() {
        let personas: [Persona] = [.vietnameseReader, .japaneseBusiness, .japaneseCasual]
        for persona in personas {
            #expect(!persona.displayBadge.isEmpty)
        }
    }

    @Test("Keigo badge is in Japanese kanji for visual unmistakability")
    func keigoBadgeKanji() {
        #expect(Persona.japaneseBusiness.displayBadge == "敬語")
    }

    @Test("Casual badge marks the chat register clearly")
    func casualBadge() {
        #expect(Persona.japaneseCasual.displayBadge == "カジュアル")
    }
}
