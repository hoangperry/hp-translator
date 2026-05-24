import Foundation
import NaturalLanguage
import Testing

@testable import ContextualMacTranslator

@Suite("NaturalLanguageDetector")
struct NaturalLanguageDetectorTests {
    @Test("Vietnamese paragraph detects as vi")
    func detectsVietnamese() {
        let detector = NaturalLanguageDetector()
        let result = detector.detectLanguage(in:
            "Em xin lỗi anh về sự cố vừa rồi, bên em đang kiểm tra lại đơn hàng và sẽ phản hồi anh trong vòng 30 phút ạ."
        )
        #expect(result == "vi")
    }

    @Test("English paragraph detects as en")
    func detectsEnglish() {
        let detector = NaturalLanguageDetector()
        let result = detector.detectLanguage(in:
            "Could you please send me the updated quote for the bulk order by end of week?"
        )
        #expect(result == "en")
    }

    @Test("Simplified Chinese maps to BCP47 zh-Hans, not the raw NL string")
    func chineseMaps() {
        let detector = NaturalLanguageDetector()
        let result = detector.detectLanguage(in: "请帮我查一下这个订单的发货状态，谢谢。")
        // NLLanguage.simplifiedChinese.rawValue is "zh-Hans"; our wrapper
        // formalises that mapping so the providers always see the same
        // string regardless of NLLanguage's underlying representation.
        #expect(result == "zh-Hans")
    }

    @Test("Empty input returns 'auto' without crashing the recognizer")
    func emptyReturnsAuto() {
        let detector = NaturalLanguageDetector()
        #expect(detector.detectLanguage(in: "") == "auto")
        #expect(detector.detectLanguage(in: "   \n\n  ") == "auto")
    }

    @Test("Low-confidence detection falls back to 'auto'")
    func lowConfidenceFallsBack() {
        // High threshold = the recognizer essentially never qualifies,
        // so even a clear-language sample returns 'auto'. Verifies the
        // confidence gate works.
        let strict = NaturalLanguageDetector(confidenceThreshold: 0.99999)
        let result = strict.detectLanguage(in: "hello world")
        #expect(result == "auto")
    }

    @Test("NLLanguage → BCP47 mapping covers the special-cased pairs")
    func bcp47Mapping() {
        #expect(NaturalLanguageDetector.bcp47(for: .simplifiedChinese) == "zh-Hans")
        #expect(NaturalLanguageDetector.bcp47(for: .traditionalChinese) == "zh-Hant")
        // Everything else passes the raw NLLanguage value through.
        #expect(NaturalLanguageDetector.bcp47(for: .vietnamese) == NLLanguage.vietnamese.rawValue)
        #expect(NaturalLanguageDetector.bcp47(for: .english) == NLLanguage.english.rawValue)
    }
}
