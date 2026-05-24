import Foundation
import Testing

@testable import ContextualMacTranslator

@Suite("OCRPostprocessor.joinIntoParagraphs")
struct OCRPostprocessorJoinTests {
    @Test("Single line passes through verbatim")
    func singleLine() {
        let out = OCRPostprocessor.joinIntoParagraphs(lines: ["Xin chào anh ạ."])
        #expect(out == "Xin chào anh ạ.")
    }

    @Test("Multiple lines without terminators join with a single space")
    func midSentenceJoinsWithSpace() {
        // Visual line-wrap should reassemble into one sentence.
        let out = OCRPostprocessor.joinIntoParagraphs(lines: [
            "Em xin lỗi anh",
            "về sự cố vừa rồi",
            "bên em sẽ kiểm tra lại",
        ])
        #expect(out == "Em xin lỗi anh về sự cố vừa rồi bên em sẽ kiểm tra lại")
    }

    @Test("Sentence-terminator characters break paragraphs")
    func paragraphsSeparated() {
        let out = OCRPostprocessor.joinIntoParagraphs(lines: [
            "Cảm ơn anh.",
            "Em sẽ xử lý ngay.",
        ])
        #expect(out == "Cảm ơn anh.\n\nEm sẽ xử lý ngay.")
    }

    @Test("CJK terminators (。！？) also break paragraphs")
    func cjkTerminators() {
        let out = OCRPostprocessor.joinIntoParagraphs(lines: [
            "今日はいい天気です。",
            "明日は雨でしょう。",
        ])
        #expect(out == "今日はいい天気です。\n\n明日は雨でしょう。")
    }

    @Test("Blank lines flush the current paragraph")
    func blanksFlush() {
        let out = OCRPostprocessor.joinIntoParagraphs(lines: [
            "first line of one paragraph",
            "second line of the same paragraph",
            "",
            "third line is a new paragraph",
        ])
        #expect(out == "first line of one paragraph second line of the same paragraph\n\nthird line is a new paragraph")
    }

    @Test("Empty input yields empty output, not crash")
    func emptyInput() {
        #expect(OCRPostprocessor.joinIntoParagraphs(lines: []) == "")
        #expect(OCRPostprocessor.joinIntoParagraphs(lines: ["", "", ""]) == "")
    }
}

@Suite("OCRPostprocessor.normalise (Vietnamese diacritic safety)")
struct OCRPostprocessorNormaliseTests {
    @Test("Pre-composed VN diacritics round-trip unchanged")
    func precomposedRoundTrips() {
        // Every NFC-composed Vietnamese vowel diacritic combo we'll
        // realistically encounter in OCR output.
        let samples = [
            "Xin chào, em muốn hỏi về đơn hàng số 12345 ạ.",
            "Cảm ơn anh đã liên hệ với bên em nhé.",
            "Dạ, em xin phép gửi thông tin chi tiết ạ.",
            "Ưu đãi đặc biệt — giảm 50% trong tuần này!",
        ]
        for sample in samples {
            let cleaned = OCRPostprocessor.normalise(sample)
            #expect(cleaned == sample, "Diacritics lost in: \(sample) → \(cleaned)")
        }
    }

    @Test("Decomposed diacritics are recomposed to NFC")
    func decomposedRecomposed() {
        // a + U+0323 (combining dot below) = ạ (U+1EA1) under NFC.
        let decomposed = "a\u{0323}"   // a + combining dot below
        let composed = "\u{1EA1}"      // ạ (precomposed)
        let cleaned = OCRPostprocessor.normalise(decomposed)
        #expect(cleaned == composed)
        #expect(cleaned.unicodeScalars.count == 1)
    }

    @Test("C0 control characters are stripped, newlines preserved")
    func stripsControlsKeepsNewlines() {
        let input = "Hello\u{0001}\u{0007}\nWorld\u{0008}\u{007F}"
        let cleaned = OCRPostprocessor.normalise(input)
        #expect(cleaned == "Hello\nWorld")
    }

    @Test("Surrounding whitespace gets trimmed")
    func trimsEdges() {
        #expect(OCRPostprocessor.normalise("\n  hello  \n\n") == "hello")
    }
}

@Suite("OCRPostprocessor.clean (full pipeline)")
struct OCRPostprocessorCleanTests {
    @Test("Multi-line VN with mid-sentence wraps and terminators round-trips correctly")
    func vnPipeline() {
        let lines = [
            "Em xin lỗi anh về sự cố vừa rồi",
            "bên em đang kiểm tra lại đơn hàng.",
            "Cảm ơn anh đã thông cảm ạ.",
        ]
        let cleaned = OCRPostprocessor.clean(lines: lines)
        #expect(cleaned == "Em xin lỗi anh về sự cố vừa rồi bên em đang kiểm tra lại đơn hàng.\n\nCảm ơn anh đã thông cảm ạ.")
    }

    @Test("Mixed VN+EN content preserves both scripts")
    func mixedLanguages() {
        let lines = [
            "Em check lại pull request số 1234,",
            "merge xong sẽ deploy lên staging ạ.",
        ]
        let cleaned = OCRPostprocessor.clean(lines: lines)
        #expect(cleaned.contains("Em check"))
        #expect(cleaned.contains("pull request số 1234"))
        #expect(cleaned.contains("deploy lên staging ạ"))
    }
}
