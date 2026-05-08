import Foundation

@MainActor
final class TranslationWorkflow {
    private let translator: TranslatorAPI
    private let hudController: HUDController
    private let keyboard: KeyboardSimulator
    private let pasteboard: ClipboardService
    private let focusGuard: FocusGuard
    private let previewPresenter: PreviewPresenter
    private let glossaryProvider: @MainActor () -> String
    private let focusGuardEnabledProvider: @MainActor () -> Bool

    init(
        translator: TranslatorAPI,
        hudController: HUDController,
        keyboard: KeyboardSimulator,
        pasteboard: ClipboardService,
        focusGuard: FocusGuard = FocusGuard(),
        previewPresenter: PreviewPresenter = PreviewHUDController(),
        glossaryProvider: @escaping @MainActor () -> String = { SettingsStore.shared.glossary },
        focusGuardEnabledProvider: @escaping @MainActor () -> Bool = { SettingsStore.shared.focusGuardEnabled }
    ) {
        self.translator = translator
        self.hudController = hudController
        self.keyboard = keyboard
        self.pasteboard = pasteboard
        self.focusGuard = focusGuard
        self.previewPresenter = previewPresenter
        self.glossaryProvider = glossaryProvider
        self.focusGuardEnabledProvider = focusGuardEnabledProvider
    }

    func translateSelection() async {
        guard translator.isConfigured else {
            hudController.showError(TranslationError.missingEndpoint.localizedDescription)
            return
        }

        hudController.showLoading("Translating selection...", persona: .vietnameseReader)
        let snapshot = pasteboard.capture()
        let previousChangeCount = pasteboard.changeCount

        await keyboard.copySelection()
        guard let selectedText = await pasteboard.waitForCopiedString(after: previousChangeCount)?.trimmedNonEmpty else {
            pasteboard.restore(snapshot)
            hudController.showError(TranslationError.emptyClipboard.localizedDescription)
            return
        }
        pasteboard.restore(snapshot)

        do {
            let result = try await translator.translate(TranslationJob(
                text: selectedText,
                direction: .inbound,
                sourceLanguage: "auto",
                targetLanguage: Persona.vietnameseReader.targetLanguage,
                persona: .vietnameseReader,
                glossary: glossaryProvider()
            ))
            hudController.showResult(result.translation, persona: .vietnameseReader)
        } catch {
            hudController.showError(error.localizedDescription)
        }
    }

    func translateAndSend(persona: Persona) async {
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
                direction: .outbound,
                sourceLanguage: "vi",
                targetLanguage: persona.targetLanguage,
                persona: persona,
                glossary: glossaryProvider()
            ))

            // Branch on persona policy: keigo defaults to preview-then-send;
            // casual defaults to auto-send. Define spec §A Q9 / PRD US-5.
            let textToSend: String
            if persona.previewByDefault {
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
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
