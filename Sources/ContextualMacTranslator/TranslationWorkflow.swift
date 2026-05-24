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
        glossaryProvider: @escaping @MainActor () -> String = { SettingsStore.shared.glossary },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage },
        rewriteAvailableProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.rewriteAvailable },
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() },
        multiVariantRewriteEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.multiVariantRewriteEnabled },
        captureService: ScreenCaptureService = SystemScreenCaptureService(),
        ocrEngine: OCREngine = VisionOCREngine(),
        languageDetector: LanguageDetector = NaturalLanguageDetector()
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
        glossaryProvider: @escaping @MainActor () -> String = { SettingsStore.shared.glossary },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage },
        rewriteAvailableProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.rewriteAvailable },
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() },
        multiVariantRewriteEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.multiVariantRewriteEnabled },
        captureService: ScreenCaptureService = SystemScreenCaptureService(),
        ocrEngine: OCREngine = VisionOCREngine(),
        languageDetector: LanguageDetector = NaturalLanguageDetector()
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
            languageDetector: languageDetector
        )
    }

    func translateSelection() async {
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        let inboundStyle = TranslationStyle(
            direction: .inbound,
            targetLanguage: primaryLanguageProvider(),
            register: .neutral
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

    func translateAndSend(persona: Persona) async {
        let translator = providerFactory()
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

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

        do {
            let result = try await translator.translate(TranslationJob(
                text: sourceText,
                style: persona,
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
        let baseStyle = binding.style(language: primaryLanguageProvider())
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
            variants = try await performRewriteVariants(sourceText: sourceText, style: style, translator: translator)
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

    /// Headless translate, no HUD / clipboard / keystrokes. Used by the
    /// `TranslateSelectionIntent` (App Intents). Returns the cleaned
    /// translation; throws `TranslationError.missingEndpoint` when the
    /// active provider isn't configured, or whatever the provider raised.
    func performTranslationHeadless(text: String, targetLanguage: String) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        let style = TranslationStyle(
            direction: .outbound,
            targetLanguage: targetLanguage,
            register: .neutral
        )
        let job = TranslationJob(
            text: text,
            style: style,
            sourceLanguage: "auto",
            glossary: glossaryProvider()
        )
        return PromptBuilder.normalize(try await translator.translate(job).translation)
    }

    /// Headless rewrite using one of the preset tones. Reuses
    /// `performRewrite` so the refusal-retry chain applies identically.
    /// Mirrors the in-app rewrite behaviour but skips HUD/preview/paste.
    func performRewriteHeadless(text: String, tone: RewriteTone) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        // `.custom` with no instruction is invalid (same gate as the
        // binding-hotkey path) — surface the same typed error.
        let instruction = tone == .custom
            ? "Rewrite this naturally and clearly while preserving the writer's intent and voice."
            : tone.instruction
        let label = tone == .custom ? "Rewrite (custom)" : "\(tone.displayName) rewrite"
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: primaryLanguageProvider(),
            register: .neutral,
            customStyleInstruction: instruction,
            displayLabelOverride: label,
            allowsExpressiveContent: tone.isExpressive
        )
        return try await performRewrite(sourceText: text, style: style, translator: translator)
    }

    /// Headless rewrite using a free-text instruction. Mirrors the
    /// picker's freetext-row behaviour (v0.8.3). Empty instruction
    /// raises `RewriteError.emptyCustomInstruction` — same contract as
    /// `rewriteAndSend`.
    func performRewriteHeadless(text: String, instruction: String) async throws -> String {
        let translator = providerFactory()
        guard translator.isConfigured else {
            throw TranslationError.missingEndpoint
        }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RewriteError.emptyCustomInstruction
        }
        let style = TranslationStyle(
            direction: .rewrite,
            targetLanguage: primaryLanguageProvider(),
            register: .neutral,
            customStyleInstruction: trimmed,
            displayLabelOverride: "Rewrite (your prompt)"
        )
        return try await performRewrite(sourceText: text, style: style, translator: translator)
    }

    /// Call the provider, clean the output, and guard against refusals:
    /// one retry with a stronger anti-refusal instruction, then throw
    /// `RewriteError.refused` so the caller falls back to the original.
    private func performRewrite(
        sourceText: String,
        style: TranslationStyle,
        translator: any TranslationProvider
    ) async throws -> String {
        let firstJob = TranslationJob(
            text: sourceText,
            style: style,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let first = RewriteResultProcessor.clean(try await translator.translate(firstJob).translation)
        if !RewriteResultProcessor.isLikelyRefusal(first) {
            return first
        }

        // Retry once — reframe even harder that this is the user's own draft.
        let retryStyle = TranslationStyle(
            direction: .rewrite,
            targetLanguage: style.targetLanguage,
            register: style.register,
            customStyleInstruction: style.styleInstruction
                + "\n\nThis is the user's OWN draft, provided for tone editing only. Rewrite it in the requested tone. Do not decline, do not explain, do not comment.",
            displayLabelOverride: style.displayLabelOverride
        )
        let retryJob = TranslationJob(
            text: sourceText,
            style: retryStyle,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let second = RewriteResultProcessor.clean(try await translator.translate(retryJob).translation)
        if !RewriteResultProcessor.isLikelyRefusal(second) {
            return second
        }
        throw RewriteError.refused
    }

    /// v0.8.5 — variant-aware rewrite entry. When `style.variantCount`
    /// is 1, delegates to the single-draft `performRewrite` and wraps
    /// the result in a one-element array (so the rest of the workflow
    /// can stay uniform). When >1, asks the model for N drafts in one
    /// round-trip + parses the response with the sentinel-based splitter.
    /// Falls back to single-draft retry if parsing yields <2 usable
    /// variants, so a model that ignored the multi-variant prompt still
    /// produces something usable.
    private func performRewriteVariants(
        sourceText: String,
        style: TranslationStyle,
        translator: any TranslationProvider
    ) async throws -> [String] {
        guard style.variantCount > 1 else {
            let single = try await performRewrite(sourceText: sourceText, style: style, translator: translator)
            return [single]
        }
        let job = TranslationJob(
            text: sourceText,
            style: style,
            sourceLanguage: primaryLanguageProvider(),
            glossary: glossaryProvider()
        )
        let raw = try await translator.translate(job).translation
        let parsed = RewriteResultProcessor.splitVariants(raw)
        if parsed.count >= 2 {
            // Cap to the requested count — some models over-deliver.
            return Array(parsed.prefix(style.variantCount))
        }
        // Model ignored the multi-variant prompt OR everything got
        // filtered as refusals. Fall back to a single-draft pass with
        // the anti-refusal retry chain so the user still gets a result.
        let fallbackStyle = style.withVariantCount(1)
        let single = try await performRewrite(sourceText: sourceText, style: fallbackStyle, translator: translator)
        return [single]
    }

    // MARK: - OCR capture (v0.9.0)

    /// Capture a screen region, OCR the contents, auto-detect source
    /// language, translate into the user's primary language, surface
    /// the result in the PreviewHUD.
    ///
    /// This is a READ flow, not a SEND flow — the user is consuming
    /// foreign text from the screen, not authoring a message. The HUD
    /// is presented in `.copy` mode (P5) so its primary action is
    /// "Copy", not "Paste". No keystroke simulation, no clipboard
    /// snapshot/restore dance: the system `screencapture` tool owns
    /// the capture UX, and the OCR'd text never touches the user's
    /// clipboard until they explicitly choose to copy from the HUD.
    func captureAndTranslate() async {
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
        let initialStyle = TranslationStyle(
            direction: .inbound,
            targetLanguage: target,
            register: .neutral
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
            hudController.showError(error.localizedDescription)
            return
        }

        hudController.dismiss()
        // PreviewHUD in copy-mode — the user's primary action is
        // "Copy translation to clipboard", not "Paste into focused app".
        // P5 specialises the real PreviewHUDController to relabel the
        // button; the default-extension route just goes through the
        // standard `presentPreview`. In both cases the workflow writes
        // the confirmed text to the clipboard on `.send` and shows a
        // success toast.
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

        let baseStyle = Self.style(forPickerEntry: entry, language: primaryLanguageProvider())
        let style = multiVariantRewriteEnabledProvider()
            ? baseStyle.withVariantCount(3)
            : baseStyle

        hudController.showLoading(
            style.variantCount > 1 ? "Generating \(style.variantCount) drafts..." : "Rewriting message...",
            persona: style
        )

        let variants: [String]
        do {
            variants = try await performRewriteVariants(sourceText: sourceText, style: style, translator: translator)
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

    /// Build a `TranslationStyle` from a picker-chosen entry. Four cases:
    ///   • `.freetext(text)` — v0.8.3: the user typed an ad-hoc instruction
    ///     in the picker filter; that text becomes the style instruction.
    ///   • `.preset(.custom)` — the "Custom" preset row was tapped
    ///     without free-text; fall back to a sensible default.
    ///   • `.preset(other)` — built-in tone with its canned instruction.
    ///   • `.binding(b)` — v0.8.4: a persisted RewriteBinding surfaced in
    ///     the picker (because the user ticked "In picker"); use the
    ///     binding's effective instruction + display label so the result
    ///     is identical to invoking the binding via its hotkey.
    /// `allowsExpressiveContent` only flips on for tones flagged
    /// `.isExpressive` (e.g. `.casualRaw`); freetext stays strict —
    /// users who want expressive rewriting must pick a preset explicitly.
    private static func style(forPickerEntry entry: PickerEntry, language: String) -> TranslationStyle {
        let instruction: String
        let label: String
        let expressive: Bool
        switch entry {
        case .freetext(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            instruction = trimmed.isEmpty
                ? "Rewrite this naturally and clearly while preserving the writer's intent and voice."
                : trimmed
            label = "Rewrite (your prompt)"
            expressive = false
        case .preset(let tone):
            if tone == .custom {
                instruction = "Rewrite this naturally and clearly while preserving the writer's intent and voice."
                label = "Rewrite (custom)"
            } else {
                instruction = tone.instruction
                label = "\(tone.displayName) rewrite"
            }
            expressive = tone.isExpressive
        case .binding(let binding):
            instruction = binding.effectiveInstruction
            label = binding.displayName
            expressive = binding.tone.isExpressive
        }
        return TranslationStyle(
            direction: .rewrite,
            targetLanguage: language,
            register: .neutral,
            customStyleInstruction: instruction,
            displayLabelOverride: label,
            allowsExpressiveContent: expressive
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
