import CoreGraphics
import Foundation

/// End-to-end OCR-translate flow extracted from `TranslationWorkflow`
/// in v0.9.1 so the workflow file stays under the 800-line guideline.
/// Pure refactor — behaviour byte-identical to the v0.9.0 implementation.
///
/// Owns the capture → OCR → language-detect → translate → preview-HUD
/// pipeline. Does NOT manage clipboard snapshots / restores — OCR is
/// a READ flow, the user's existing clipboard is only touched if they
/// explicitly confirm "Copy" in the HUD.
@MainActor
struct CaptureOrchestrator {
    let providerFactory: @MainActor () -> any TranslationProvider
    let hudController: HUDController
    let pasteboard: ClipboardService
    let previewPresenter: PreviewPresenter
    let captureService: ScreenCaptureService
    let ocrEngine: OCREngine
    let languageDetector: LanguageDetector
    let glossaryProvider: @MainActor () -> String
    let primaryLanguageProvider: @MainActor () -> String

    /// Run the full OCR-translate flow once. Public entry from
    /// `TranslationWorkflow.captureAndTranslate()`.
    func run() async {
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        // Capture — system tool owns crosshair + permission UX.
        let captureResult = await captureService.captureRegion()
        let image: CGImage
        switch captureResult {
        case .captured(let img):
            image = img
        case .cancelled:
            // User pressed Esc on the crosshair. Quiet exit — no toast.
            return
        case .failed(let reason):
            hudController.showError("Couldn't capture screen: \(reason)")
            return
        }

        let target = primaryLanguageProvider()
        // v0.10.0 — eagerly stamp privacy class + display name so the
        // HUD's badge renders from style state (R4 mitigation — no
        // providerFactory() call on the SwiftUI render path).
        let initialStyle = TranslationStyle(
            direction: .inbound,
            targetLanguage: target,
            register: .neutral
        ).withProvider(
            privacyClass: type(of: translator).privacyClass,
            displayName: type(of: translator).displayName
        )
        hudController.showLoading("Reading text from screen...", persona: initialStyle)

        // OCR — Vision pipeline.
        let ocrResult = await ocrEngine.recognizeText(in: image)
        let sourceText: String
        switch ocrResult {
        case .recognized(let text):
            sourceText = text
        case .nothingDetected:
            // Dismiss the loading HUD before swapping to error so the
            // user doesn't see both stacked (mirrors the translation-
            // failure path below).
            hudController.dismiss()
            hudController.showError("No text detected in that region.")
            return
        case .failed(let reason):
            hudController.dismiss()
            hudController.showError("OCR failed: \(reason)")
            return
        }

        // Detect language on-device so the provider gets the right hint.
        let sourceLanguage = languageDetector.detectLanguage(in: sourceText)

        let job = TranslationJob(
            text: sourceText,
            style: initialStyle,
            sourceLanguage: sourceLanguage,
            glossary: glossaryProvider()
        )

        let translation: String
        do {
            translation = try await translator.translate(job).translation
        } catch {
            hudController.dismiss()
            hudController.showError(error.localizedDescription)
            return
        }

        hudController.dismiss()
        // PreviewHUD in copy-mode — the user's primary action is
        // "Copy translation to clipboard", not "Paste into focused app".
        // The real PreviewHUDController relabels the button; the default-
        // extension route just goes through the standard presentPreview.
        // In both cases the orchestrator writes the confirmed text to
        // the clipboard on `.send` and shows a success toast.
        let decision = await previewPresenter.presentForCopy(
            original: sourceText,
            translated: PromptBuilder.normalize(translation),
            persona: initialStyle,
            isSourceFocused: { true }    // OCR isn't tied to a source app
        )
        switch decision {
        case .send(let confirmed):
            pasteboard.writeString(confirmed)
            hudController.showResult("Copied translation to clipboard", persona: initialStyle)
        case .cancel:
            // No clipboard write, no toast — silent dismissal.
            return
        }
    }
}
