import CoreGraphics
import Foundation

@MainActor
final class TranslationWorkflow {
    /// Lazy provider resolution — invoked at the start of every workflow
    /// run so Settings changes apply on the next hotkey press without
    /// recreating the workflow. Defaults to a closure that calls into the
    /// shared `TranslationProviderFactory`; tests inject a static
    /// provider via the convenience initialiser below.
    private let providerFactory: @MainActor () -> any TranslationProvider
    private let hudController: HUDController
    private let keyboard: KeyboardSimulator
    private let pasteboard: ClipboardService
    private let focusGuard: FocusGuard
    private let previewPresenter: PreviewPresenter
    private let glossaryProvider: @MainActor () -> String
    private let focusGuardEnabledProvider: @MainActor () -> Bool
    /// User's primary language (where inbound translations go, source of
    /// outbound translations). BCP47 code, e.g. "vi", "en".
    private let primaryLanguageProvider: @MainActor () -> String
    /// Whether the active provider can perform a tone rewrite. Gates the
    /// rewrite hotkey so a non-LLM provider surfaces a clear error.
    private let rewriteAvailableProvider: @MainActor () -> Bool
    /// Picker presenter (v0.8) — `nil` when the workflow is constructed
    /// without picker support (e.g. older tests).
    private let pickerPresenter: TonePickerPresenter?
    /// Inspects the focused UI element's AX role so the picker workflow
    /// can refuse paste into a `AXSecureTextField` before capturing anything.
    private let focusedElementKindProvider: @MainActor () -> FocusedElementKind
    /// v0.8.5 — when this returns `true`, rewrite paths ask the model for
    /// 3 drafts in a single round-trip and surface them in the multi-variant
    /// PreviewHUD. Default reads from `SettingsStore.shared`.
    private let multiVariantRewriteEnabledProvider: @MainActor () -> Bool
    /// v0.9.0 — region screenshot capture (defaults to system screencapture
    /// subprocess; tests inject a stub).
    private let captureService: ScreenCaptureService
    /// v0.9.0 — Vision OCR; tests inject a fixed-text stub.
    private let ocrEngine: OCREngine
    /// v0.9.0 — NLLanguageRecognizer wrapper for auto-detecting OCR'd text.
    private let languageDetector: LanguageDetector
    /// v0.9.1 — rewrite primitives (single-shot + multi-variant +
    /// headless) extracted from this file. Constructed in the init
    /// below from the same providerFactory/glossaryProvider/
    /// primaryLanguageProvider seams.
    private let rewriteService: RewriteService
    /// v0.10.0 — current VN social register card. `nil` (the default
    /// reading from `SettingsStore`) → no register block prepended to
    /// the per-binding tone instruction; v0.9.x prompt is byte-identical.
    /// Resolved at every workflow call so a Settings change applies on
    /// the next hotkey press without recreating the workflow.
    private let registerCardProvider: @MainActor () -> RegisterCard?

    /// Production initialiser — wires `providerFactory` to a closure that
    /// resolves the active provider every call.
    init(
        providerFactory: @escaping @MainActor () -> any TranslationProvider,
        hudController: HUDController,
        keyboard: KeyboardSimulator,
        pasteboard: ClipboardService,
        focusGuard: FocusGuard = FocusGuard(),
        previewPresenter: PreviewPresenter = PreviewHUDController(),
        pickerPresenter: TonePickerPresenter? = TonePickerController(),
        glossaryProvider: @escaping @MainActor () -> String = {
            // v0.10.0 — default composes typed entries + legacy blob
            // into one string. Tests can still inject their own closure
            // to bypass; production sites pick this up automatically so
            // every translate / rewrite / OCR path honours the
            // structured rules.
            GlossaryComposer.compose(
                entries: SettingsStore.shared.glossaryEntries,
                legacyBlob: SettingsStore.shared.glossary
            )
        },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage },
        rewriteAvailableProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.rewriteAvailable },
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() },
        multiVariantRewriteEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.multiVariantRewriteEnabled },
        captureService: ScreenCaptureService = SystemScreenCaptureService(),
        ocrEngine: OCREngine = VisionOCREngine(),
        languageDetector: LanguageDetector = NaturalLanguageDetector(),
        registerCardProvider: @escaping @MainActor () -> RegisterCard? = { SettingsStore.shared.registerCard }
    ) {
        self.providerFactory = providerFactory
        self.hudController = hudController
        self.keyboard = keyboard
        self.pasteboard = pasteboard
        self.focusGuard = focusGuard
        self.previewPresenter = previewPresenter
        self.pickerPresenter = pickerPresenter
        self.glossaryProvider = glossaryProvider
        self.focusGuardEnabledProvider = focusGuardEnabledProvider
        self.primaryLanguageProvider = primaryLanguageProvider
        self.rewriteAvailableProvider = rewriteAvailableProvider
        self.focusedElementKindProvider = focusedElementKindProvider
        self.multiVariantRewriteEnabledProvider = multiVariantRewriteEnabledProvider
        self.captureService = captureService
        self.ocrEngine = ocrEngine
        self.languageDetector = languageDetector
        self.registerCardProvider = registerCardProvider
        self.rewriteService = RewriteService(
            providerFactory: providerFactory,
            primaryLanguageProvider: primaryLanguageProvider,
            glossaryProvider: glossaryProvider,
            registerCardProvider: registerCardProvider
        )
    }

    /// Convenience initialiser for callers that hold a fixed provider —
    /// chiefly the existing test suite and the hotkey wire-up where the
    /// provider doesn't change between runs.
    convenience init(
        translator: any TranslationProvider,
        hudController: HUDController,
        keyboard: KeyboardSimulator,
        pasteboard: ClipboardService,
        focusGuard: FocusGuard = FocusGuard(),
        previewPresenter: PreviewPresenter = PreviewHUDController(),
        pickerPresenter: TonePickerPresenter? = TonePickerController(),
        glossaryProvider: @escaping @MainActor () -> String = {
            // v0.10.0 — default composes typed entries + legacy blob
            // into one string. Tests can still inject their own closure
            // to bypass; production sites pick this up automatically so
            // every translate / rewrite / OCR path honours the
            // structured rules.
            GlossaryComposer.compose(
                entries: SettingsStore.shared.glossaryEntries,
                legacyBlob: SettingsStore.shared.glossary
            )
        },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage },
        rewriteAvailableProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.rewriteAvailable },
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() },
        multiVariantRewriteEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.multiVariantRewriteEnabled },
        captureService: ScreenCaptureService = SystemScreenCaptureService(),
        ocrEngine: OCREngine = VisionOCREngine(),
        languageDetector: LanguageDetector = NaturalLanguageDetector(),
        registerCardProvider: @escaping @MainActor () -> RegisterCard? = { SettingsStore.shared.registerCard }
    ) {
        self.init(
            providerFactory: { translator },
            hudController: hudController,
            keyboard: keyboard,
            pasteboard: pasteboard,
            focusGuard: focusGuard,
            previewPresenter: previewPresenter,
            pickerPresenter: pickerPresenter,
            glossaryProvider: glossaryProvider,
            focusGuardEnabledProvider: focusGuardEnabledProvider,
            primaryLanguageProvider: primaryLanguageProvider,
            rewriteAvailableProvider: rewriteAvailableProvider,
            focusedElementKindProvider: focusedElementKindProvider,
            multiVariantRewriteEnabledProvider: multiVariantRewriteEnabledProvider,
            captureService: captureService,
            ocrEngine: ocrEngine,
            languageDetector: languageDetector,
            registerCardProvider: registerCardProvider
        )
    }

    func translateSelection() async {
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        let inboundStyle = stamp(
            TranslationStyle(
                direction: .inbound,
                targetLanguage: primaryLanguageProvider(),
                register: .neutral
            ),
            with: translator
        )

        hudController.showLoading("Translating selection...", persona: inboundStyle)
        let snapshot = pasteboard.capture()
        let previousChangeCount = pasteboard.changeCount

        await keyboard.copySelection()
        guard let selectedText = await pasteboard.waitForCopiedString(after: previousChangeCount)?.trimmedNonEmpty else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.emptyClipboard.localizedDescription)
            return
        }
        pasteboard.restore(snapshot)

        let job = TranslationJob(
            text: selectedText,
            style: inboundStyle,
            sourceLanguage: "auto",
            glossary: glossaryProvider()
        )

        // Inbound is the only flow where progressive HUD adds value
        // (outbound has to wait for the full text before pasting). Use
        // streaming when the active provider implements it; fall back to
        // one-shot translate otherwise.
        if let streamer = translator as? any StreamingTranslationProvider {
            await runStreamingInbound(streamer: streamer, job: job)
        } else {
            await runOneShotInbound(translator: translator, job: job)
        }
    }

    func translateAndSend(persona originalPersona: Persona) async {
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }
        // v0.10.0 — eagerly stamp the persona with the active provider's
        // privacy class + display name so the HUD's badge renders without
        // reaching into providerFactory() per SwiftUI pass.
        let persona = stamp(originalPersona, with: translator)

        focusGuard.capture()

        hudController.showLoading("Translating message...", persona: persona)
        let snapshot = pasteboard.capture()
        let previousChangeCount = pasteboard.changeCount

        await keyboard.selectCurrentLineToBeginning()
        guard await isFocusStillAllowed() else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
            return
        }
        await keyboard.copySelection()

        guard let sourceText = await pasteboard.waitForCopiedString(after: previousChangeCount)?.trimmedNonEmpty else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.emptyClipboard.localizedDescription)
            return
        }

        // v0.10.0 — outbound translate composes the active VN register
        // card into the persona style (no-op when nil/inactive).
        let registerPersona = persona.withRegisterCard(registerCardProvider())
        do {
            let result = try await translator.translate(TranslationJob(
                text: sourceText,
                style: registerPersona,
                sourceLanguage: primaryLanguageProvider(),
                glossary: glossaryProvider()
            ))

            // Branch on persona policy: keigo defaults to preview-then-send;
            // casual defaults to auto-send. Define spec §A Q9 / PRD US-5.
            let textToSend: String
            if persona.previewByDefault {
                // Hide the loading HUD before opening preview so the user
                // doesn't see two stacked panels (loading + preview).
                hudController.dismiss()
                let decision = await previewPresenter.presentPreview(
                    original: sourceText,
                    translated: result.translation,
                    persona: persona,
                    isSourceFocused: { [weak self] in
                        guard let self else { return false }
                        guard self.focusGuardEnabledProvider() else { return true }
                        return self.focusGuard.isStillFocused()
                    }
                )
                switch decision {
                case .send(let confirmed):
                    textToSend = confirmed
                case .cancel:
                    pasteboard.restore(snapshot)
                    hudController.showResult("Cancelled — original text restored", persona: persona)
                    return
                }
            } else {
                textToSend = result.translation
            }

            // Focus check before paste — security finding F-5 / AC-9.2.
            // This is the *protective* guard: if focus moved during the LLM
            // round-trip, refuse the paste entirely.
            guard await isFocusStillAllowed() else {
                pasteboard.restore(snapshot)
                hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
                return
            }

            pasteboard.writeString(textToSend)
            await keyboard.paste()

            // Focus check before Return — AC-9.3. WARNING: by this point the
            // paste has already committed text into the target field; we
            // CANNOT undo it. This guard only prevents the auto-submit
            // `Return`. The error message reflects that reality so the user
            // knows to review the target app instead of assuming nothing
            // happened. (Code review finding R-H1.)
            //
            // Use the *delayed* restore (700 ms) on this post-paste path so
            // the target app has fully consumed the pasteboard before we
            // overwrite it with the snapshot — otherwise a slow app could
            // pick up the old snapshot value instead of `textToSend`.
            guard await isFocusStillAllowed() else {
                restoreClipboard(snapshot)
                hudController.showError(TranslationError.focusChangedAfterPaste.localizedDescription)
                return
            }

            await keyboard.enter()
            restoreClipboard(snapshot)
            hudController.showResult("Sent \(persona.displayBadge)", persona: persona)
        } catch {
            pasteboard.restore(snapshot)
            hudController.showError(error.localizedDescription)
        }
    }

    // MARK: - Contextual rewrite (v0.7)

    /// Rewrite the current input line in the binding's tone, then — after
    /// the user confirms in the preview HUD — paste + send it. Unlike
    /// `translateAndSend`, rewrite ALWAYS previews: a tone-changed message
    /// must be reviewed before it goes out.
    func rewriteAndSend(binding: RewriteBinding) async {
        guard rewriteAvailableProvider() else {
            hudController.showError(
                "Rewrite needs an LLM provider (Gemini, Ollama, or an OpenAI-compatible API). DeepL and Google Translate cannot rewrite."
            )
            return
        }
        // A `.custom` binding with no instruction would send an empty
        // `Target tone:` prompt and produce generic output without telling
        // the user. Fail fast with a settings-pointing message instead.
        guard !binding.effectiveInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hudController.showError(RewriteError.emptyCustomInstruction.localizedDescription)
            return
        }
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        // v0.8.5 — decorate the style with N drafts when the user has
        // opted into multi-variant rewriting.
        // v0.10.0 — also compose the active VN register card (no-op when
        // nil/inactive). Order: register first (it's pure prompt
        // composition), then variant decoration (it's an LLM-call-shape
        // change). Either order works for the prompt body but applying
        // register before variant keeps the resulting customStyleInstruction
        // identical between single- and multi-variant paths.
        let baseStyle = stamp(
            binding.style(language: primaryLanguageProvider())
                .withRegisterCard(registerCardProvider()),
            with: translator
        )
        let style = multiVariantRewriteEnabledProvider()
            ? baseStyle.withVariantCount(3)
            : baseStyle
        focusGuard.capture()

        hudController.showLoading(
            style.variantCount > 1 ? "Generating \(style.variantCount) drafts..." : "Rewriting message...",
            persona: style
        )
        let snapshot = pasteboard.capture()
        let previousChangeCount = pasteboard.changeCount

        await keyboard.selectCurrentLineToBeginning()
        guard await isFocusStillAllowed() else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
            return
        }
        await keyboard.copySelection()

        guard let sourceText = await pasteboard.waitForCopiedString(after: previousChangeCount)?.trimmedNonEmpty else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.emptyClipboard.localizedDescription)
            return
        }

        let variants: [String]
        do {
            variants = try await rewriteService.rewriteVariants(sourceText: sourceText, style: style, translator: translator)
        } catch {
            pasteboard.restore(snapshot)
            hudController.showError(error.localizedDescription)
            return
        }

        // Always preview — never auto-send a tone-changed message.
        hudController.dismiss()
        let decision = await previewPresenter.presentVariants(
            original: sourceText,
            variants: variants,
            persona: style,
            isSourceFocused: { [weak self] in
                guard let self else { return false }
                guard self.focusGuardEnabledProvider() else { return true }
                return self.focusGuard.isStillFocused()
            }
        )

        let textToSend: String
        switch decision {
        case .send(let confirmed):
            textToSend = confirmed
        case .cancel:
            pasteboard.restore(snapshot)
            hudController.showResult("Cancelled — original text kept", persona: style)
            return
        }

        guard await isFocusStillAllowed() else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
            return
        }

        pasteboard.writeString(textToSend)
        await keyboard.paste()

        // Delayed restore on the post-paste error path — same reasoning as
        // `translateAndSend`: let the target app finish consuming the
        // pasteboard before we overwrite it with the snapshot.
        guard await isFocusStillAllowed() else {
            restoreClipboard(snapshot)
            hudController.showError(TranslationError.focusChangedAfterPaste.localizedDescription)
            return
        }

        await keyboard.enter()
        restoreClipboard(snapshot)
        hudController.showResult("Sent \(style.displayName)", persona: style)
    }

    // MARK: - Headless (App Intents — v0.9.0)
    //
    // These three façade methods preserve the public contract of the
    // headless workflow that App Intents call into. Bodies live in
    // `RewriteService` (extracted in v0.9.1) so the rewrite primitives
    // can be unit-tested + reused without dragging the rest of this
    // workflow's clipboard/keystroke machinery into the test setup.

    func performTranslationHeadless(text: String, targetLanguage: String) async throws -> String {
        try await rewriteService.translateHeadless(text: text, targetLanguage: targetLanguage)
    }

    func performRewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        try await rewriteService.rewriteHeadless(text: text, tone: tone)
    }

    func performRewriteHeadless(text: String, instruction: String) async throws -> String {
        try await rewriteService.rewriteHeadless(text: text, instruction: instruction)
    }

    // MARK: - OCR capture (v0.9.0)

    /// Capture a screen region, OCR the contents, auto-detect source
    /// language, translate into the user's primary language, surface
    /// the result in the PreviewHUD.
    ///
    /// v0.9.1 — implementation extracted to `CaptureOrchestrator` to
    /// keep this file under the 800-line guideline. This facade just
    /// constructs an orchestrator with the workflow's injected
    /// dependencies and runs it.
    func captureAndTranslate() async {
        await CaptureOrchestrator(
            providerFactory: providerFactory,
            hudController: hudController,
            pasteboard: pasteboard,
            previewPresenter: previewPresenter,
            captureService: captureService,
            ocrEngine: ocrEngine,
            languageDetector: languageDetector,
            glossaryProvider: glossaryProvider,
            primaryLanguageProvider: primaryLanguageProvider
        ).run()
    }

    // MARK: - Tone picker (v0.8)

    /// Picker variant of the rewrite workflow. Capture the current input
    /// line *before* showing the picker (Option A — Discovery analysis):
    /// the picker can sit on screen for many seconds, during which the
    /// originating text field may lose focus or selection. Once the line
    /// is captured we restore the clipboard immediately so the brief
    /// snapshot window doesn't leak into the user's clipboard history.
    func rewriteWithPickerAndSend() async {
        guard rewriteAvailableProvider() else {
            hudController.showError(
                "Rewrite needs an LLM provider (Gemini, Ollama, or an OpenAI-compatible API). DeepL and Google Translate cannot rewrite."
            )
            return
        }
        guard let pickerPresenter else {
            hudController.showError("Tone picker is not available in this build.")
            return
        }
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        // AX role gate — refuse before any keyboard simulation so we
        // never read a password field into a snapshot, even briefly.
        if focusedElementKindProvider() == .secureTextInput {
            hudController.showError("Tone picker is disabled in secure text fields.")
            return
        }

        focusGuard.capture()

        let snapshot = pasteboard.capture()
        let previousChangeCount = pasteboard.changeCount

        await keyboard.selectCurrentLineToBeginning()
        guard await isFocusStillAllowed() else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
            return
        }
        await keyboard.copySelection()

        // AC13 collapse the line selection IMMEDIATELY after copy and
        // BEFORE `waitForCopiedString`. Putting it after the async
        // pasteboard poll would leave a ~50-100 ms window where the
        // user's line is still selected; one keystroke would replace it.
        // Right-Arrow doesn't touch the clipboard, so the poll below
        // still sees the just-copied value.
        await keyboard.collapseSelectionToEnd()

        guard let sourceText = await pasteboard.waitForCopiedString(after: previousChangeCount)?.trimmedNonEmpty else {
            // AC14 empty short-circuit: don't even show the picker.
            pasteboard.restore(snapshot)
            hudController.showError("Nothing to rewrite — no text on the current line.")
            return
        }

        // Eager restore — the LLM call uses `sourceText` from memory, so
        // there's no reason to keep the captured line in the clipboard
        // while the picker dwells.
        pasteboard.restore(snapshot)

        let chosen = await pickerPresenter.present(isSourceFocused: { [weak self] in
            guard let self else { return false }
            guard self.focusGuardEnabledProvider() else { return true }
            return self.focusGuard.isStillFocused()
        })

        guard let entry = chosen else {
            // User cancelled — clipboard already restored, selection
            // already collapsed. Quiet exit.
            return
        }

        let baseStyle = stamp(
            RewriteService.style(forPickerEntry: entry, language: primaryLanguageProvider())
                .withRegisterCard(registerCardProvider()),
            with: translator
        )
        let style = multiVariantRewriteEnabledProvider()
            ? baseStyle.withVariantCount(3)
            : baseStyle

        hudController.showLoading(
            style.variantCount > 1 ? "Generating \(style.variantCount) drafts..." : "Rewriting message...",
            persona: style
        )

        let variants: [String]
        do {
            variants = try await rewriteService.rewriteVariants(sourceText: sourceText, style: style, translator: translator)
        } catch {
            hudController.showError(error.localizedDescription)
            return
        }

        hudController.dismiss()
        let decision = await previewPresenter.presentVariants(
            original: sourceText,
            variants: variants,
            persona: style,
            isSourceFocused: { [weak self] in
                guard let self else { return false }
                guard self.focusGuardEnabledProvider() else { return true }
                return self.focusGuard.isStillFocused()
            }
        )

        let textToSend: String
        switch decision {
        case .send(let confirmed):
            textToSend = confirmed
        case .cancel:
            hudController.showResult("Cancelled — original text kept", persona: style)
            return
        }

        guard await isFocusStillAllowed() else {
            hudController.showError(TranslationError.focusChangedBeforePaste.localizedDescription)
            return
        }

        pasteboard.writeString(textToSend)
        await keyboard.paste()

        // Same delayed-restore pattern as `rewriteAndSend` — give the
        // target app time to consume the pasteboard before we overwrite.
        guard await isFocusStillAllowed() else {
            restoreClipboard(snapshot)
            hudController.showError(TranslationError.focusChangedAfterPaste.localizedDescription)
            return
        }

        await keyboard.enter()
        restoreClipboard(snapshot)
        hudController.showResult("Sent \(style.displayName)", persona: style)
    }

    // `style(forPickerEntry:language:)` extracted to RewriteService in
    // v0.9.1. Call via `RewriteService.style(forPickerEntry:language:)`.

    /// v0.10.0 — stamp a `TranslationStyle` with the active provider's
    /// privacy class + display name so the HUD's Privacy badge can be
    /// rendered without reaching back into `providerFactory()` during
    /// SwiftUI render passes (R4 mitigation from define.md §6).
    private func stamp(
        _ style: TranslationStyle,
        with translator: any TranslationProvider
    ) -> TranslationStyle {
        style.withProvider(
            privacyClass: type(of: translator).privacyClass,
            displayName: type(of: translator).displayName
        )
    }

    private func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            pasteboard.restore(snapshot)
        }
    }

    private func isFocusStillAllowed() async -> Bool {
        guard focusGuardEnabledProvider() else {
            return true
        }
        return await focusGuard.isStillFocused(afterGrace: .milliseconds(250))
    }

    private func runStreamingInbound(
        streamer: any StreamingTranslationProvider,
        job: TranslationJob
    ) async {
        var buffer = ""
        do {
            for try await update in streamer.translateStreaming(job) {
                switch update {
                case .chunk(let chunk):
                    buffer += chunk
                    hudController.updateLoading(buffer, persona: job.style)
                case .done(let translation, _):
                    let final = translation.isEmpty ? buffer : translation
                    hudController.showResult(final, persona: job.style)
                    return
                }
            }
            if !buffer.isEmpty {
                hudController.showResult(buffer, persona: job.style)
            } else {
                hudController.showError(TranslationError.missingTranslation.localizedDescription)
            }
        } catch {
            hudController.showError(error.localizedDescription)
        }
    }

    private func runOneShotInbound(
        translator: any TranslationProvider,
        job: TranslationJob
    ) async {
        do {
            let result = try await translator.translate(job)
            hudController.showResult(result.translation, persona: job.style)
        } catch {
            hudController.showError(error.localizedDescription)
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
