import Foundation
import Testing

@testable import ContextualMacTranslator

/// v0.10.0 — pin every provider's privacyClass declaration so the
/// HUD Privacy badge + Settings Privacy ribbon stay accurate as new
/// providers ship. Adding a provider without declaring its class
/// falls through to the protocol default (`.cloud`) which this test
/// also exercises as a contract.
@Suite("ProviderPrivacyClass declarations")
@MainActor
struct ProviderPrivacyClassTests {

    @Test("Ollama is .local — on-device only")
    func ollamaIsLocal() {
        #expect(OllamaDirectProvider.privacyClass == .local)
    }

    @Test("MockDirectProvider is .local — in-memory echo, nothing leaves the process")
    func mockIsLocal() {
        #expect(MockDirectProvider.privacyClass == .local)
    }

    @Test("BackendProvider is .hosted — 1st-party / self-hosted proxy")
    func backendIsHosted() {
        #expect(BackendProvider.privacyClass == .hosted)
    }

    @Test("Cloud providers all declare .cloud explicitly")
    func cloudProvidersAreCloud() {
        #expect(GeminiDirectProvider.privacyClass == .cloud)
        #expect(GeminiCLIProvider.privacyClass == .cloud)
        #expect(CodexCLIProvider.privacyClass == .cloud)
        #expect(DeepLDirectProvider.privacyClass == .cloud)
        #expect(GoogleTranslateDirectProvider.privacyClass == .cloud)
        #expect(LibreTranslateDirectProvider.privacyClass == .cloud)
        #expect(OpenAICompatibleDirectProvider.privacyClass == .cloud)
    }

    @Test("Badge symbol + label cover every case (UI integration contract)")
    func badgeDataComplete() {
        for cls in ProviderPrivacyClass.allCases {
            #expect(!cls.badgeSymbol.isEmpty, "Missing symbol for \(cls)")
            #expect(!cls.badgeLabel.isEmpty, "Missing label for \(cls)")
        }
    }

    @Test("Codable round-trip (TranslationStyle.privacyClass persists across encoding)")
    func codableRoundTrip() throws {
        for cls in ProviderPrivacyClass.allCases {
            let data = try JSONEncoder().encode(cls)
            let decoded = try JSONDecoder().decode(ProviderPrivacyClass.self, from: data)
            #expect(decoded == cls)
        }
    }
}

@Suite("TranslationStyle.withProvider stamping")
struct TranslationStyleStampingTests {

    @Test("withProvider stamps both fields + preserves everything else")
    func stampingPreservesRest() {
        let base = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .formal,
            customStyleInstruction: "Be polite.",
            displayLabelOverride: "Polite rewrite",
            allowsExpressiveContent: true,
            variantCount: 3,
            registerCard: RegisterCard(dialect: .northern)
        )
        let stamped = base.withProvider(privacyClass: .local, displayName: "Ollama (local)")

        // Stamped fields
        #expect(stamped.privacyClass == .local)
        #expect(stamped.providerDisplayName == "Ollama (local)")

        // Everything else preserved
        #expect(stamped.direction == base.direction)
        #expect(stamped.targetLanguage == base.targetLanguage)
        #expect(stamped.register == base.register)
        #expect(stamped.customStyleInstruction == base.customStyleInstruction)
        #expect(stamped.displayLabelOverride == base.displayLabelOverride)
        #expect(stamped.allowsExpressiveContent == base.allowsExpressiveContent)
        #expect(stamped.variantCount == base.variantCount)
        #expect(stamped.registerCard == base.registerCard)
    }

    @Test("Default style has nil privacyClass + empty providerDisplayName (HUD hides badge)")
    func defaultStyleHasNoBadge() {
        let style = TranslationStyle(
            direction: .inbound,
            targetLanguage: "vi",
            register: .neutral
        )
        #expect(style.privacyClass == nil)
        #expect(style.providerDisplayName == "")
    }

    @Test("withVariantCount preserves stamped privacy fields")
    func variantCountPreservesStamp() {
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .neutral
        ).withProvider(privacyClass: .hosted, displayName: "Backend")
            .withVariantCount(3)
        #expect(style.privacyClass == .hosted)
        #expect(style.providerDisplayName == "Backend")
        #expect(style.variantCount == 3)
    }

    @Test("withRegisterCard preserves stamped privacy fields")
    func registerCardPreservesStamp() {
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .neutral
        ).withProvider(privacyClass: .local, displayName: "Ollama")
            .withRegisterCard(RegisterCard(kinship: .chi))
        #expect(style.privacyClass == .local)
        #expect(style.providerDisplayName == "Ollama")
        #expect(style.registerCard?.kinship == .chi)
    }
}
