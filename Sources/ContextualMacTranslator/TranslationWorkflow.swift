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

    /// Production initialiser — wires `providerFactory` to a closure that
    /// resolves the active provider every call.
    init(
        providerFactory: @escaping @MainActor () -> any TranslationProvider,
        hudController: HUDController,
        keyboard: KeyboardSimulator,
        pasteboard: ClipboardService,
        focusGuard: FocusGuard = FocusGuard(),
        previewPresenter: PreviewPresenter = PreviewHUDController(),
        glossaryProvider: @escaping @MainActor () -> String = { SettingsStore.shared.glossary },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage }
    ) {
        self.providerFactory = providerFactory
        self.hudController = hudController
        self.keyboard = keyboard
        self.pasteboard = pasteboard
        self.focusGuard = focusGuard
        self.previewPresenter = previewPresenter
        self.glossaryProvider = glossaryProvider
        self.focusGuardEnabledProvider = focusGuardEnabledProvider
        self.primaryLanguageProvider = primaryLanguageProvider
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
        glossaryProvider: @escaping @MainActor () -> String = { SettingsStore.shared.glossary },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled },
        primaryLanguageProvider: @escaping @MainActor () -> String = { SettingsStore.shared.primaryLanguage }
    ) {
        self.init(
            providerFactory: { translator },
            hudController: hudController,
            keyboard: keyboard,
            pasteboard: pasteboard,
            focusGuard: focusGuard,
            previewPresenter: previewPresenter,
            glossaryProvider: glossaryProvider,
            focusGuardEnabledProvider: focusGuardEnabledProvider,
            primaryLanguageProvider: primaryLanguageProvider
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
            guard await isFocusStillAllowed() else {
                pasteboard.restore(snapshot)
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
