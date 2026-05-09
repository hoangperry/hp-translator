import AppKit
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
        .frame(minWidth: 580, minHeight: 600)
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
        case .geminiCLI, .codexCLI:
            Label("CLI providers will be available after Phase 3c. Pick another provider for now.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .mock:
            Text("Mock returns `[persona] text` echoes — useful when testing hotkeys without a live API.")
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
