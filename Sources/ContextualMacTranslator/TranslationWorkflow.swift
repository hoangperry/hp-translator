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
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() }
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
        focusedElementKindProvider: @escaping @MainActor () -> FocusedElementKind = { FocusedElementInspector().currentKind() }
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
            focusedElementKindProvider: focusedElementKindProvider
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

        let style = binding.style(language: primaryLanguageProvider())
        focusGuard.capture()

        hudController.showLoading("Rewriting message...", persona: style)
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

        let rewritten: String
        do {
            rewritten = try await performRewrite(sourceText: sourceText, style: style, translator: translator)
        } catch {
            pasteboard.restore(snapshot)
            hudController.showError(error.localizedDescription)
            return
        }

        // Always preview — never auto-send a tone-changed message.
        hudController.dismiss()
        let decision = await previewPresenter.presentPreview(
            original: sourceText,
            translated: rewritten,
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

        guard let tone = chosen else {
            // User cancelled — clipboard already restored, selection
            // already collapsed. Quiet exit.
            return
        }

        let style = Self.style(forPickerTone: tone, language: primaryLanguageProvider())

        hudController.showLoading("Rewriting message...", persona: style)

        let rewritten: String
        do {
            rewritten = try await performRewrite(sourceText: sourceText, style: style, translator: translator)
        } catch {
            hudController.showError(error.localizedDescription)
            return
        }

        hudController.dismiss()
        let decision = await previewPresenter.presentPreview(
            original: sourceText,
            translated: rewritten,
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

    /// Build a `TranslationStyle` from a picker-chosen tone. For `.custom`
    /// we substitute a sensible default instruction because the v0.8.0
    /// picker doesn't (yet) include a free-text input.
    private static func style(forPickerTone tone: RewriteTone, language: String) -> TranslationStyle {
        let instruction: String
        let label: String
        if tone == .custom {
            instruction = "Rewrite this naturally and clearly while preserving the writer's intent and voice."
            label = "Rewrite (custom)"
        } else {
            instruction = tone.instruction
            label = "\(tone.displayName) rewrite"
        }
        return TranslationStyle(
            direction: .rewrite,
            targetLanguage: language,
            register: .neutral,
            customStyleInstruction: instruction,
            displayLabelOverride: label
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
