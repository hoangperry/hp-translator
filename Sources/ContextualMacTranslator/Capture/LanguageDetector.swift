import Foundation
import NaturalLanguage

/// On-device language detection for OCR'd text. Output is BCP47 with
/// the same shape `TranslationJob.sourceLanguage` expects ("auto" /
/// "vi" / "en" / "zh-Hans" / …), so the workflow can drop it straight
/// into the existing translate path.
///
/// Wrapped behind a protocol so the OCR pipeline can be tested with
/// a stub that returns deterministic values, independent of how the
/// underlying `NLLanguageRecognizer` would score a fixture string.
protocol LanguageDetector: Sendable {
    /// Best-guess BCP47 source language for `text`, or `"auto"` if the
    /// detector isn't confident enough to commit. "auto" lets the
    /// translation provider do its own detection, which is what
    /// happens today on the inbound-translate path.
    func detectLanguage(in text: String) -> String
}

/// Production implementation backed by `NLLanguageRecognizer`.
/// Reuses a single recognizer per call (the recognizer is not
/// thread-safe, so we don't keep one around).
struct NaturalLanguageDetector: LanguageDetector {
    /// Minimum confidence required to commit to a non-"auto" answer.
    /// 0.6 is the empirical threshold below which language guesses
    /// on short / mixed strings start to flip-flop between calls.
    let confidenceThreshold: Double

    init(confidenceThreshold: Double = 0.6) {
        self.confidenceThreshold = confidenceThreshold
    }

    func detectLanguage(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "auto" }

        let recogniser = NLLanguageRecognizer()
        recogniser.processString(trimmed)
        let hypotheses = recogniser.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = hypotheses.first,
              confidence >= confidenceThreshold else {
            return "auto"
        }
        return Self.bcp47(for: language)
    }

    /// Map `NLLanguage` to the BCP47 string the translation providers
    /// expect. Special-cases Chinese (NL returns `.simplifiedChinese`
    /// vs `.traditionalChinese`; providers want `zh-Hans` / `zh-Hant`)
    /// and a few aliases.
    static func bcp47(for language: NLLanguage) -> String {
        switch language {
        case .simplifiedChinese:   return "zh-Hans"
        case .traditionalChinese:  return "zh-Hant"
        default:
            // NLLanguage's rawValue is already BCP47 for everything
            // else we care about (vi, en, ja, ko, th, …).
            return language.rawValue
        }
    }
}
