import CoreGraphics
import Foundation
import Testing

@testable import ContextualMacTranslator

/// `VisionOCREngine` is integration-tested by manual smoke during the
/// deliver phase (capture a real VN chat screenshot → verify diacritics
/// survive). We tried programmatic CGImage rendering here, but Vision's
/// recogniser is trained on natural screenshots and behaves poorly on
/// freshly-rasterised text — false-negative noise that would gate the
/// CI suite without actually testing the diacritic-preservation
/// contract.
///
/// The diacritic guarantee that DOES matter — Unicode NFC normalisation
/// + control-character stripping — is exercised by
/// `OCRPostprocessor.normalise` tests in OCRPostprocessorTests.swift.
/// Those tests pin every Vietnamese vowel combo the workflow will
/// realistically encounter.

@Suite("OCRResult convenience")
struct OCRResultTests {
    @Test("Equatable conformance compares cases + payloads")
    func equality() {
        #expect(OCRResult.nothingDetected == .nothingDetected)
        #expect(OCRResult.recognized("a") == .recognized("a"))
        #expect(OCRResult.recognized("a") != .recognized("b"))
        #expect(OCRResult.failed("x") == .failed("x"))
        #expect(OCRResult.failed("x") != .nothingDetected)
    }
}

@Suite("VisionOCREngine contract")
struct VisionOCREngineContractTests {
    @Test("Default language list covers the v0.9.0 target audience (vi/en/zh/ja/ko)")
    func defaultLanguagesAreSane() {
        let langs = VisionOCREngine.defaultLanguages
        #expect(langs.contains("vi-VN"))
        #expect(langs.contains("en-US"))
        #expect(langs.contains("zh-Hans"))
        #expect(langs.contains("ja-JP"))
        #expect(langs.contains("ko-KR"))
        // Order matters — Vision uses earlier entries as soft preference.
        #expect(langs.first == "vi-VN")
    }

    @Test("Engine constructs with a custom language list without crashing")
    func customLanguagesAccepted() {
        let engine = VisionOCREngine(languages: ["en-US"], usesLanguageCorrection: false)
        // Construction should not throw or assert; the engine is now
        // ready to recognise English-only input.
        _ = engine
    }
}
