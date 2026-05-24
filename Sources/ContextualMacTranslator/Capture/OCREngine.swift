import Foundation
import Vision
import CoreGraphics

/// Result of an OCR pass. `nothingDetected` is a distinct case from
/// `failed`: the model ran fine but found no text, so the workflow
/// surfaces a friendly toast instead of an error.
enum OCRResult: Sendable, Equatable {
    case recognized(String)
    case nothingDetected
    case failed(String)
}

/// Protocol so the workflow can be tested with a stubbed OCR engine
/// (fixed text, fixed failure, fixed empty result) without invoking
/// real `Vision` requests.
protocol OCREngine: Sendable {
    /// Run OCR on `image` constrained to the configured language list.
    /// Returns the joined-text result; preserves Vietnamese diacritics
    /// and Han/Kana glyphs verbatim.
    func recognizeText(in image: CGImage) async -> OCRResult
}

/// Production implementation backed by `VNRecognizeTextRequest`.
///
/// Language list is fixed at construction for predictable behaviour
/// across calls. Default covers the audience identified in
/// docs/v0.9.0/discovery.md (VN seller / freelancer): Vietnamese
/// (primary user output), English (most foreign chat), Simplified
/// Chinese (1688 / Taobao suppliers), Japanese (JP work clients),
/// Korean (KR partners). Order matters — Vision uses it as a soft
/// preference for tie-breaking ambiguous glyphs.
final class VisionOCREngine: OCREngine {
    /// BCP47 language tags accepted by `VNRecognizeTextRequest`. The
    /// list is intentionally short — adding too many slows the request
    /// and hurts accuracy on the actually-likely languages.
    static let defaultLanguages: [String] = [
        "vi-VN", "en-US", "zh-Hans", "ja-JP", "ko-KR",
    ]

    private let languages: [String]
    /// When `true`, Vision applies its built-in lexicon correction to
    /// reduce OCR misrecognition. For Vietnamese this can occasionally
    /// strip valid diacritics; default to true and let v0.9.x flip it
    /// via Settings if users complain.
    private let usesLanguageCorrection: Bool

    init(
        languages: [String] = VisionOCREngine.defaultLanguages,
        usesLanguageCorrection: Bool = true
    ) {
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    func recognizeText(in image: CGImage) async -> OCRResult {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: .nothingDetected)
                    return
                }
                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                let joined = OCRPostprocessor.clean(lines: lines)
                if joined.isEmpty {
                    continuation.resume(returning: .nothingDetected)
                } else {
                    continuation.resume(returning: .recognized(joined))
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = self.usesLanguageCorrection
            request.recognitionLanguages = self.languages
            // Automatic language ID off — we provide the candidate set
            // ourselves to keep results deterministic per locale.
            request.automaticallyDetectsLanguage = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: .failed(error.localizedDescription))
            }
        }
    }
}

/// Post-processing for the joined OCR output. Pure + synchronous so
/// it's trivially testable in P7 with VN-text fixtures.
///
/// Two jobs:
/// 1. **Join lines** without losing paragraph breaks. Vision returns
///    text line-by-line; we glue lines into paragraphs when adjacent
///    lines don't end in sentence-final punctuation.
/// 2. **Strip control characters** while preserving every diacritic.
///    Unicode normalisation form NFC is mandatory: Vietnamese
///    pre-combined forms (ạ U+1EA1) round-trip safely; decomposed
///    forms (a + U+0323) sometimes lose accents in downstream
///    text-field rendering.
enum OCRPostprocessor {
    static func clean(lines: [String]) -> String {
        let joined = joinIntoParagraphs(lines: lines)
        return normalise(joined)
    }

    /// Glue OCR lines into paragraphs. Lines that end with sentence-
    /// final punctuation start a new paragraph; mid-sentence wraps get
    /// joined with a space.
    static func joinIntoParagraphs(lines: [String]) -> String {
        var out: [String] = []
        var current = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                continue
            }
            if current.isEmpty {
                current = line
            } else {
                current += " " + line
            }
            if endsParagraph(line) {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            out.append(current)
        }
        return out.joined(separator: "\n\n")
    }

    private static let paragraphTerminators: Set<Character> = [
        ".", "。", "!", "?", "！", "？", ":", "：",
    ]

    private static func endsParagraph(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return paragraphTerminators.contains(last)
    }

    /// Force NFC composition + strip ASCII control bytes (Vision can
    /// emit C1 control chars on noisy edges).
    static func normalise(_ text: String) -> String {
        let composed = text.precomposedStringWithCanonicalMapping
        // Strip C0/C1 controls (U+0000..U+001F, U+007F..U+009F) but
        // preserve newlines, which we use as paragraph separators.
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(composed.unicodeScalars.count)
        for scalar in composed.unicodeScalars {
            let v = scalar.value
            if scalar == "\n" {
                scalars.append(scalar)
            } else if (v < 0x20) || (v >= 0x7F && v <= 0x9F) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
