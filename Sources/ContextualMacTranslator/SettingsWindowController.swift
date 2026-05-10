import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(permissionManager: PermissionManager) {
        let view = SettingsView(permissionManager: permissionManager)
        let controller = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: controller)
        window.title = "Contextual Mac Translator"
        window.setContentSize(NSSize(width: 600, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                languagesSection
                Divider()
                sourcePicker
                Divider()
                sourceForm
                Divider()
                glossarySection
                Divider()
                permissionsSection
                Divider()
                advancedSection
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 700)
    }

    // MARK: - Languages (v0.3)

    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Languages")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("My language (incoming translations target this)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("My language", selection: $settings.primaryLanguage) {
                    ForEach(LanguageCatalog.supported) { lang in
                        Text("\(lang.englishName) — \(lang.nativeName)").tag(lang.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Inbound hotkey (selection → my language)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settings.inboundBinding.hotkey.displayLabel)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Outbound translations")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Add target") { addOutboundBinding() }
                }
                ForEach($settings.outboundBindings) { $binding in
                    OutboundBindingRow(binding: $binding) { removeBinding(binding) }
                }
                if settings.outboundBindings.isEmpty {
                    Text("No outbound targets configured. Add one above to translate from your primary language to another.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addOutboundBinding() {
        // Pick the first language not yet bound, fallback to English.
        let usedCodes = Set(settings.outboundBindings.map { $0.languageCode })
        let nextLang = LanguageCatalog.supported.first(where: { !usedCodes.contains($0.code) })?.code ?? "en"
        let nextRegister: Register = .formal
        // Pick a free hotkey: cycle ⌘1, ⌘2, ⌘3, ... when defaults are taken.
        let nextHotkey: HotkeyConfig = {
            let defaults: [HotkeyConfig] = [.defaultOutboundFormal, .defaultOutboundCasual]
            let used = Set(settings.outboundBindings.map { $0.hotkey })
            for cand in defaults where !used.contains(cand) {
                return cand
            }
            // Fallback: ⌘ + digit
            let digits: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                 kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
            for d in digits {
                let cand = HotkeyConfig(keyCode: UInt32(d), modifiers: UInt32(cmdKey))
                if !used.contains(cand) { return cand }
            }
            return .defaultOutboundFormal
        }()
        settings.outboundBindings.append(OutboundBinding(
            languageCode: nextLang,
            register: nextRegister,
            hotkey: nextHotkey
        ))
    }

    private func removeBinding(_ binding: OutboundBinding) {
        settings.outboundBindings.removeAll { $0.id == binding.id }
    }

    // MARK: - Sections

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translation Source")
                .font(.headline)
            Picker("Translation Source", selection: $settings.translationSource) {
                ForEach(TranslationSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(settings.translationSource.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourceForm: some View {
        switch settings.translationSource {
        case .directAPI:
            directForm
        case .customBackend:
            customBackendForm
        case .firstPartyBackend:
            firstPartyForm
        }
    }

    private var directForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Direct provider")
                    .font(.headline)
                Spacer()
                Picker("Provider", selection: $settings.directProvider) {
                    ForEach(DirectProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
            }
            Text(settings.directProvider.requirementHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            providerCredentialFields(for: settings.directProvider)
        }
    }

    @ViewBuilder
    private func providerCredentialFields(for kind: DirectProviderKind) -> some View {
        switch kind {
        case .gemini:
            VStack(alignment: .leading, spacing: 8) {
                LabeledSecureField(label: "API key", text: $settings.geminiAPIKey, placeholder: "Google AI Studio key")
                LabeledTextField(label: "Model", text: $settings.geminiModel, placeholder: SettingsStore.ProviderDefaults.geminiModel)
            }
        case .ollama:
            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField(label: "Base URL", text: $settings.ollamaBaseURL, placeholder: SettingsStore.ProviderDefaults.ollamaBaseURL)
                LabeledTextField(label: "Model", text: $settings.ollamaModel, placeholder: SettingsStore.ProviderDefaults.ollamaModel)
            }
        case .googleTranslate:
            LabeledSecureField(label: "API key", text: $settings.googleTranslateAPIKey, placeholder: "Google Cloud Translate API key")
        case .openAICompatible:
            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField(label: "Base URL", text: $settings.openAICompatBaseURL, placeholder: SettingsStore.ProviderDefaults.openAICompatBaseURL)
                LabeledSecureField(label: "API key", text: $settings.openAICompatAPIKey, placeholder: "Bearer token")
                LabeledTextField(label: "Model", text: $settings.openAICompatModel, placeholder: SettingsStore.ProviderDefaults.openAICompatModel)
            }
        case .deepl:
            VStack(alignment: .leading, spacing: 8) {
                LabeledSecureField(label: "API key", text: $settings.deeplAPIKey, placeholder: "DeepL Free or Pro key")
                Toggle("Use Free endpoint (api-free.deepl.com)", isOn: $settings.deeplUseFree)
                    .help("Untick if your key is for the Pro plan (api.deepl.com).")
            }
        case .libreTranslate:
            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField(label: "Base URL", text: $settings.libreTranslateBaseURL, placeholder: SettingsStore.ProviderDefaults.libreTranslateBaseURL)
                LabeledSecureField(label: "API key (optional)", text: $settings.libreTranslateAPIKey, placeholder: "Leave empty if self-hosted without auth")
            }
        case .geminiCLI, .codexCLI:
            Text("Spawns the CLI per request. Make sure the binary is installed and authenticated (\\`gemini login\\` or \\`codex login\\`).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .mock:
            Text("Mock returns `[language] text` echoes — useful when testing hotkeys without a live API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customBackendForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom backend")
                .font(.headline)
            LabeledTextField(label: "Endpoint", text: $settings.endpoint, placeholder: "https://your-api.example.com/translate")
            if let warning = EndpointPolicy.warning(for: settings.endpoint) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledSecureField(label: "Bearer token", text: $settings.apiKey, placeholder: "TRANSLATOR_TOKEN value")
        }
    }

    private var firstPartyForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1st-party backend")
                .font(.headline)
            LabeledTextField(label: "Endpoint", text: $settings.firstPartyEndpoint, placeholder: "https://translator.lookerlab.app/translate")
            if let warning = EndpointPolicy.warning(for: settings.firstPartyEndpoint) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledSecureField(label: "Issued token", text: $settings.firstPartyToken, placeholder: "Bearer token from service operator")
            Text("Switching to 1st-party preserves your custom backend credentials in the other tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var glossarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glossary")
                .font(.headline)
            Text("Lines like `term = preferred translation` — applied across all LLM-based providers.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.glossary)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(
                title: "Accessibility",
                granted: permissionManager.accessibilityGranted,
                action: permissionManager.requestAccessibilityIfNeeded
            )
            PermissionRow(
                title: "Input Monitoring",
                granted: permissionManager.inputMonitoringGranted,
                action: permissionManager.requestInputMonitoringIfNeeded
            )
            HStack {
                Button("Refresh") {
                    permissionManager.refresh()
                }
                Button("Open Privacy Settings") {
                    openPrivacySettings()
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced")
                .font(.headline)
            Toggle("Enable focus guard before paste/send", isOn: $settings.focusGuardEnabled)
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Reusable rows

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct LabeledSecureField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            Button(granted ? "Granted" : "Request", action: action)
                .disabled(granted)
        }
    }
}

/// Editable row for one outbound binding (target language + register +
/// hotkey display). Hotkey recorder UI is deferred to a follow-up; for
/// now the hotkey is shown but immutable from here — users can edit by
/// removing + re-adding.
private struct OutboundBindingRow: View {
    @Binding var binding: OutboundBinding
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Language", selection: $binding.languageCode) {
                    ForEach(LanguageCatalog.supported) { lang in
                        Text(lang.englishName).tag(lang.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Picker("Register", selection: $binding.register) {
                    ForEach(Register.allCases) { reg in
                        Text(reg.displayName).tag(reg)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 130)

                Spacer()

                Text(binding.hotkey.displayLabel)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this outbound target")
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
