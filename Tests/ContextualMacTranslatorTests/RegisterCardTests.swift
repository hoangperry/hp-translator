import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("RegisterCard.isActive gate")
struct RegisterCardActivityTests {

    @Test("Default-init card (all unspecified, empty roleHint) is inactive")
    func defaultIsInactive() {
        let card = RegisterCard()
        #expect(card.isActive == false)
    }

    @Test("Any single non-unspecified axis flips isActive to true")
    func singleAxisActivates() {
        var dialect = RegisterCard()
        dialect.dialect = .northern
        #expect(dialect.isActive)

        var kinship = RegisterCard()
        kinship.kinship = .chi
        #expect(kinship.isActive)

        var formality = RegisterCard()
        formality.formality = .formal
        #expect(formality.isActive)
    }

    @Test("RoleHint-only (no axes) still activates the card")
    func roleHintOnlyActivates() {
        var card = RegisterCard()
        card.roleHint = "seller addressing customer"
        #expect(card.isActive)
    }

    @Test("Whitespace-only roleHint does NOT activate")
    func whitespaceRoleHintInactive() {
        var card = RegisterCard()
        card.roleHint = "   \n\t "
        #expect(card.isActive == false)
    }
}

@Suite("RegisterCard.prompted(prefix:) composition")
struct RegisterCardPromptedTests {

    @Test("Inactive card returns prefix unchanged (v0.9.x byte-identical)")
    func inactiveCardIsNoOp() {
        let card = RegisterCard()
        let prefix = "Rewrite politely."
        #expect(card.prompted(prefix: prefix) == prefix)
    }

    @Test("Inactive card with empty prefix returns empty string")
    func inactiveCardWithEmptyPrefix() {
        #expect(RegisterCard().prompted(prefix: "") == "")
    }

    @Test("Bắc + chị + formal block renders Northern particles + chị pronoun + formal tier")
    func northernChiFormal() {
        let card = RegisterCard(
            dialect: .northern,
            kinship: .chi,
            formality: .formal
        )
        let out = card.prompted(prefix: "Rewrite politely.")
        // Header tags present
        #expect(out.contains("[Register]"))
        #expect(out.contains("[Tone]"))
        // Northern dialect specifics
        #expect(out.contains("Northern (Bắc) dialect"))
        #expect(out.contains("nhé"))
        #expect(out.contains("avoid \"nha\"/\"nhen\""))
        // Kinship: chị (production string uses third-person "addresses")
        #expect(out.contains("addresses the listener as \"chị\""))
        // Formality: formal
        #expect(out.contains("formality: formal"))
        // Prefix preserved verbatim
        #expect(out.contains("Rewrite politely."))
        // Sanity: prefix appears AFTER the [Tone] tag, not before
        let toneIdx = out.range(of: "[Tone]")!
        let prefixIdx = out.range(of: "Rewrite politely.")!
        #expect(prefixIdx.lowerBound > toneIdx.upperBound)
    }

    @Test("Nam + em + casual block renders Southern particles + em pronoun + casual tier")
    func southernEmCasual() {
        let card = RegisterCard(
            dialect: .southern,
            kinship: .em,
            formality: .casual
        )
        let out = card.prompted(prefix: "Be friendly.")
        #expect(out.contains("Southern (Nam) dialect"))
        #expect(out.contains("nha"))
        #expect(out.contains("speaker is younger"))
        #expect(out.contains("formality: casual"))
        #expect(out.contains("Be friendly."))
    }

    @Test("Bắc + cháu (kid → adult) renders the much-younger speaker frame")
    func northernChauKidAdult() {
        let card = RegisterCard(
            dialect: .northern,
            kinship: .chau,
            formality: .formal
        )
        let out = card.prompted(prefix: "")
        #expect(out.contains("speaker is much younger"))
        #expect(out.contains("kid-to-adult"))
        #expect(out.contains("refer to self as \"cháu\""))
        // Empty prefix shouldn't produce a trailing dangling [Tone] body
        #expect(out.hasSuffix("[Tone]"))
    }

    @Test("RoleHint-only card (no axes) still emits a [Register] block with Context line")
    func roleHintOnlyEmitsContext() {
        var card = RegisterCard()
        card.roleHint = "TikTok Shop seller addressing customer"
        let out = card.prompted(prefix: "Be professional.")
        #expect(out.contains("[Register]"))
        // Vietnamese-register line should NOT appear (all axes unspecified)
        #expect(!out.contains("Vietnamese register:"))
        // Context line should appear
        #expect(out.contains("Context: TikTok Shop seller addressing customer."))
        // Tone follows
        #expect(out.contains("[Tone]"))
        #expect(out.contains("Be professional."))
    }

    @Test("RoleHint exceeding 80 chars truncates at the boundary")
    func roleHintTruncates() {
        var card = RegisterCard()
        // 100-char string; first 80 chars chosen so the truncation is
        // observably mid-word.
        card.roleHint = String(repeating: "a", count: 100)
        let out = card.prompted(prefix: "")
        let truncated = String(repeating: "a", count: 80)
        let notTruncated = String(repeating: "a", count: 81)
        #expect(out.contains("Context: \(truncated)."))
        #expect(!out.contains("Context: \(notTruncated)"))
    }

    @Test("Mixed axes — only the specified ones contribute to the line")
    func mixedAxesSubset() {
        let card = RegisterCard(
            dialect: .northern,
            kinship: .unspecified,
            formality: .neutral
        )
        let out = card.prompted(prefix: "X")
        #expect(out.contains("Northern (Bắc) dialect"))
        #expect(out.contains("formality: neutral"))
        // Kinship phrases should NOT appear
        #expect(!out.contains("addresses the listener as"))
        #expect(!out.contains("speaker is younger"))
        #expect(!out.contains("speaker is much younger"))
        #expect(!out.contains("peer-to-peer neutral"))
    }
}

@Suite("RegisterCard Codable round-trip")
struct RegisterCardCodableTests {

    @Test("Round-trip preserves every field")
    func roundTripFull() throws {
        let original = RegisterCard(
            dialect: .southern,
            kinship: .anh,
            formality: .casual,
            roleHint: "freelancer to JP client"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RegisterCard.self, from: data)
        #expect(decoded == original)
    }

    @Test("Default-init card encodes + decodes without throwing")
    func roundTripDefaults() throws {
        let original = RegisterCard()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RegisterCard.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isActive == false)
    }

    @Test("Unknown raw enum values fail decoding (forward-compat contract)")
    func unknownEnumValueFails() {
        // If a future v0.10.x adds a 4th dialect ('central'), older
        // builds should fail-closed rather than silently misinterpreting.
        // The Settings UI handles the failure by treating the persisted
        // card as nil (per SettingsStore init).
        let forwardShape = Data("""
        {"dialect":"central","kinship":"anh","formality":"formal","roleHint":""}
        """.utf8)
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            try decoder.decode(RegisterCard.self, from: forwardShape)
        }
    }
}

@Suite("RegisterCard enum display labels")
struct RegisterCardLabelTests {

    @Test("Every dialect case has a non-empty Vietnamese display label")
    func dialectsLabelled() {
        for d in RegisterCard.Dialect.allCases {
            #expect(!d.displayName.isEmpty, "Dialect \(d.rawValue) missing displayName")
        }
    }

    @Test("Every kinship case has a non-empty Vietnamese display label")
    func kinshipLabelled() {
        for k in RegisterCard.Kinship.allCases {
            #expect(!k.displayName.isEmpty, "Kinship \(k.rawValue) missing displayName")
        }
    }

    @Test("Every formality case has a non-empty display label")
    func formalityLabelled() {
        for f in RegisterCard.Formality.allCases {
            #expect(!f.displayName.isEmpty, "Formality \(f.rawValue) missing displayName")
        }
    }

    @Test("Unspecified cases have empty promptPhrase (no prompt noise)")
    func unspecifiedSilent() {
        #expect(RegisterCard.Dialect.unspecified.promptPhrase.isEmpty)
        #expect(RegisterCard.Kinship.unspecified.promptPhrase.isEmpty)
        #expect(RegisterCard.Formality.unspecified.promptPhrase.isEmpty)
    }
}
