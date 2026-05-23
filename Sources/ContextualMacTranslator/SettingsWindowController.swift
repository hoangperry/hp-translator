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
        // Translucent window so the grouped Form's material backing
        // samples the desktop — the macOS 26 System Settings look.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var permissionManager: PermissionManager
    @State private var inboundRecorderShown = false
    @State private var outboundRecorderID: UUID?
    @State private var rewriteRecorderID: UUID?
    @State private var pickerRecorderShown = false
    @State private var expressiveTonePromptShown = false
    @State private var cloudAuth: SupabaseAuthViewModel

    init(permissionManager: PermissionManager) {
        self.settings = SettingsStore.shared
        self.permissionManager = permissionManager
        _cloudAuth = State(initialValue: SupabaseAuthViewModel(settings: .shared))
    }

    /// Grouped `Form` — gives the native macOS System-Settings look (inset
    /// grouped cards) instead of a flat divider-separated scroll.
    var body: some View {
        Form {
            languagesSection
            translationSourceSection
            glossarySection
            rewriteSection
            permissionsSection
            advancedSection
        }
        .formStyle(.grouped)
        // Hide the Form's opaque scroll backing so the translucent window
        // shows through, then lay real Liquid Glass (`.glassEffect()` on
        // macOS 26) behind the grouped sections.
        .scrollContentBackground(.hidden)
        .liquidGlassBackground(in: Rectangle())
        .frame(minWidth: 620, minHeight: 700)
        .sheet(isPresented: $inboundRecorderShown) {
            HotkeyRecorderSheet(
                hotkey: $settings.inboundBinding.hotkey,
                isPresented: $inboundRecorderShown,
                ownerBindingID: nil
            )
        }
        .sheet(item: $outboundRecorderID) { bindingID in
            if let index = settings.outboundBindings.firstIndex(where: { $0.id == bindingID }) {
                HotkeyRecorderSheet(
                    hotkey: $settings.outboundBindings[index].hotkey,
                    isPresented: Binding(
                        get: { outboundRecorderID != nil },
                        set: { if !$0 { outboundRecorderID = nil } }
                    ),
                    ownerBindingID: bindingID
                )
            }
        }
        .sheet(item: $rewriteRecorderID) { bindingID in
            if let index = settings.rewriteBindings.firstIndex(where: { $0.id == bindingID }) {
                HotkeyRecorderSheet(
                    hotkey: $settings.rewriteBindings[index].hotkey,
                    isPresented: Binding(
                        get: { rewriteRecorderID != nil },
                        set: { if !$0 { rewriteRecorderID = nil } }
                    ),
                    ownerBindingID: bindingID
                )
            }
        }
        .sheet(isPresented: $pickerRecorderShown) {
            HotkeyRecorderSheet(
                hotkey: Binding<HotkeyConfig>(
                    get: { settings.pickerHotkey ?? HotkeyConfig(keyCode: kVK_Return, modifiers: cmdKey | optionKey) },
                    set: { settings.pickerHotkey = $0 }
                ),
                isPresented: $pickerRecorderShown,
                ownerBindingID: nil
            )
        }
    }

    // MARK: - Languages (v0.3)

    private var languagesSection: some View {
        Section("Languages") {
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
                HStack {
                    Text(settings.inboundBinding.hotkey.displayLabel)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    Button("Change…") { inboundRecorderShown = true }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Outbound translations")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Add target") { addOutboundBinding() }
                }
                ForEach($settings.outboundBindings) { $binding in
                    OutboundBindingRow(
                        binding: $binding,
                        onChangeHotkey: { outboundRecorderID = binding.id },
                        onDelete: { removeBinding(binding) }
                    )
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

    // MARK: - Translation source

    private var translationSourceSection: some View {
        Section("Translation Source") {
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
            sourceForm
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
                    .font(.subheadline.bold())
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
                .font(.subheadline.bold())
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Contextual MT backend")
                .font(.subheadline.bold())
            Picker("Authentication", selection: $settings.backendAuthMode) {
                Text("Self-hosted · issued token")
                    .tag(BackendAuthMode.selfHostStaticToken)
                Text("Contextual MT Cloud · email sign-in")
                    .tag(BackendAuthMode.saasSupabaseSession)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if settings.backendAuthMode == .selfHostStaticToken {
                selfHostBackendFields
            } else {
                cloudConnectForm
            }
        }
    }

    private var selfHostBackendFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledTextField(label: "Endpoint", text: $settings.firstPartyEndpoint, placeholder: "https://translator.lookerlab.app/translate")
            if let warning = EndpointPolicy.warning(for: settings.firstPartyEndpoint) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledSecureField(label: "Issued token", text: $settings.firstPartyToken, placeholder: "Bearer token from service operator")
            Text("Switching modes preserves your custom backend credentials in the other tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Connect to Cloud" email-OTP flow (M2.1-a). State machine driven by
    /// `cloudAuth.phase`.
    private var cloudConnectForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Supabase URL + anon key ship pre-filled (ProviderDefaults) —
            // no manual entry needed. Sign in with just an email + code.
            switch cloudAuth.phase {
            case .idle, .error:
                cloudEmailEntry
            case .sending:
                ProgressView("Sending code…").controlSize(.small)
            case .codeSent:
                cloudCodeEntry
            case .verifying:
                ProgressView("Connecting…").controlSize(.small)
            case .connected(let email):
                cloudConnected(email: email)
            }

            if case let .error(message) = cloudAuth.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await cloudAuth.refreshConnectionState() }
    }

    private var cloudEmailEntry: some View {
        @Bindable var cloudAuth = cloudAuth
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await cloudAuth.connectViaBrowser() }
            } label: {
                Label("Connect with contextmt.dev", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            Text("Opens your browser — authorize once, nothing to type here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Or sign in with an email code")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            LabeledTextField(label: "Email", text: $cloudAuth.emailInput, placeholder: "[email protected]")
            Button("Send sign-in code") {
                Task { await cloudAuth.sendCode() }
            }
        }
    }

    private var cloudCodeEntry: some View {
        @Bindable var cloudAuth = cloudAuth
        return VStack(alignment: .leading, spacing: 8) {
            LabeledTextField(label: "6-digit code", text: $cloudAuth.codeInput, placeholder: "123456")
            HStack {
                Button("Verify & connect") {
                    Task { await cloudAuth.verify() }
                }
                Button("Use a different email") {
                    Task { await cloudAuth.signOut() }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func cloudConnected(email: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                email.isEmpty ? "Connected to Contextual MT Cloud" : "Connected as \(email)",
                systemImage: "checkmark.seal.fill"
            )
            .font(.callout)
            .foregroundStyle(.green)
            Button("Sign out") {
                Task { await cloudAuth.signOut() }
            }
            .buttonStyle(.link)
        }
    }

    // MARK: - Glossary / permissions / advanced

    private var glossarySection: some View {
        Section("Glossary") {
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

    // MARK: - Contextual rewrite (v0.7)

    private var rewriteSection: some View {
        Section("Contextual rewrite") {
            Text("Bind a hotkey to a tone (Polite, Professional, De-escalate…) and the app rewrites the current input line in that tone — same language, intent preserved. Always shown in a preview before sending.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !settings.rewriteAvailable {
                Label("Rewrite needs an LLM provider (Gemini, Ollama, OpenAI-compatible). DeepL and Google Translate cannot rewrite — switch provider above to enable.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // v0.8 — single hotkey that opens a tone picker popup. Lives
            // beside the per-binding hotkeys; bind both or just one.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tone picker hotkey")
                        .font(.subheadline.bold())
                    Spacer()
                    if let hotkey = settings.pickerHotkey {
                        Text(hotkey.displayLabel)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        Button("Change…") { pickerRecorderShown = true }
                        Button(role: .destructive) {
                            settings.pickerHotkey = nil
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Disable the picker hotkey")
                    } else {
                        Text("Not set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Set hotkey") { pickerRecorderShown = true }
                    }
                }
                Text("One hotkey, popup picker with every tone — no need to bind each tone separately. Cancel anywhere with Esc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // v0.8.2 — opt-in to "Chửi thề" (casual-raw friend register).
            // Default OFF; flipping ON shows a confirmation alert so the
            // user knows the tone is intended for friends, not customers.
            Toggle(isOn: Binding<Bool>(
                get: { settings.expressiveTonesEnabled },
                set: { newValue in
                    if newValue && !settings.expressiveTonesEnabled {
                        // Defer the actual toggle to the alert's
                        // "Continue" handler so Cancel reverts cleanly.
                        expressiveTonePromptShown = true
                    } else {
                        settings.expressiveTonesEnabled = newValue
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable expressive tones (Chửi thề)")
                    Text("Adds a casual-raw friend register that uses vl/vcl/đm as intensifiers. Intended for chats with close friends, not customer or work messages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .alert("Use expressive tones?", isPresented: $expressiveTonePromptShown) {
                Button("Continue") { settings.expressiveTonesEnabled = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This adds the \"Chửi thề\" tone — a casual-with-edge rewrite for close-friends Vietnamese chat, using profanity markers like vl/vcl/đm as natural intensifiers. The rewrite always shows in a preview before sending. Make sure your active provider supports this (Gemini works out of the box; some providers may refuse). You can turn this off any time.")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rewrite bindings")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Add binding") { addRewriteBinding() }
                }
                ForEach($settings.rewriteBindings) { $binding in
                    RewriteBindingRow(
                        binding: $binding,
                        expressiveEnabled: settings.expressiveTonesEnabled,
                        onChangeHotkey: { rewriteRecorderID = binding.id },
                        onDelete: { removeRewriteBinding(binding) }
                    )
                }
                if settings.rewriteBindings.isEmpty {
                    Text("No rewrite bindings yet. Add one above to assign a hotkey to a tone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addRewriteBinding() {
        // Cycle through ⌥R / ⌥E / ⌥W / ⌥T / ⌥Y, skipping anything already
        // used by inbound / outbound / existing rewrite bindings.
        let candidates: [HotkeyConfig] = [
            HotkeyConfig(keyCode: kVK_ANSI_R, modifiers: optionKey),
            HotkeyConfig(keyCode: kVK_ANSI_E, modifiers: optionKey),
            HotkeyConfig(keyCode: kVK_ANSI_W, modifiers: optionKey),
            HotkeyConfig(keyCode: kVK_ANSI_T, modifiers: optionKey),
            HotkeyConfig(keyCode: kVK_ANSI_Y, modifiers: optionKey),
        ]
        var used = Set(settings.outboundBindings.map(\.hotkey))
        used.formUnion(settings.rewriteBindings.map(\.hotkey))
        used.insert(settings.inboundBinding.hotkey)
        let hotkey = candidates.first { !used.contains($0) } ?? candidates[0]
        settings.rewriteBindings.append(RewriteBinding(tone: .polite, hotkey: hotkey))
    }

    private func removeRewriteBinding(_ binding: RewriteBinding) {
        settings.rewriteBindings.removeAll { $0.id == binding.id }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
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
        Section("Advanced") {
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
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: granted)
            Text(title)
            Spacer()
            Button(granted ? "Granted" : "Request", action: action)
                .disabled(granted)
        }
    }
}

/// Editable row for one outbound binding (target language + register +
/// hotkey + optional custom style instruction). Hotkey is changed via a
/// modal recorder sheet (`onChangeHotkey` triggers parent to present it).
private struct OutboundBindingRow: View {
    @Binding var binding: OutboundBinding
    let onChangeHotkey: () -> Void
    let onDelete: () -> Void
    @State private var showCustomStyle = false

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

                Button("Change…") { onChangeHotkey() }
                    .help("Re-record this hotkey")

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this outbound target")
            }

            HStack {
                Toggle(isOn: $showCustomStyle) {
                    Text("Custom style instruction")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                Spacer()
            }
            if showCustomStyle || !binding.customStyleInstruction.isEmpty {
                TextEditor(text: $binding.customStyleInstruction)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                Text("Overrides the default LLM style for this target. Leave empty to use the auto-derived register-aware instruction.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Editable row for one rewrite binding (tone + optional custom instruction
/// + hotkey). Custom tone always shows the instruction editor (it's the
/// instruction); preset tones expose it as an optional override.
private struct RewriteBindingRow: View {
    @Binding var binding: RewriteBinding
    /// Reflects `SettingsStore.expressiveTonesEnabled` — the parent
    /// passes it through so this row's tone dropdown hides expressive
    /// tones unless the user has opted in. If the row's current tone is
    /// expressive but the toggle is OFF, that tone is still shown as the
    /// current selection (so the user can see what's bound) but no other
    /// expressive option appears.
    let expressiveEnabled: Bool
    let onChangeHotkey: () -> Void
    let onDelete: () -> Void
    @State private var showCustom = false

    private var visibleTones: [RewriteTone] {
        let base = RewriteTone.available(expressive: expressiveEnabled)
        return base.contains(binding.tone) ? base : base + [binding.tone]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Tone", selection: $binding.tone) {
                    ForEach(visibleTones) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Spacer()

                Text(binding.hotkey.displayLabel)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                Button("Change…") { onChangeHotkey() }
                    .help("Re-record this hotkey")

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this rewrite binding")
            }

            HStack {
                Toggle(isOn: $showCustom) {
                    Text(binding.tone == .custom
                         ? "Custom instruction (required)"
                         : "Custom instruction (overrides preset)")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                Spacer()
                // v0.8.4 — opt this binding into the tone picker popup
                // (default ON for back-compat). Lets users surface saved
                // instructions in the picker without remembering hotkeys.
                Toggle(isOn: $binding.showInPicker) {
                    Text("In picker")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Show this binding as a row in the tone picker popup")
            }

            if showCustom || !binding.customInstruction.isEmpty || binding.tone == .custom {
                TextEditor(text: $binding.customInstruction)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 50, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                Text(binding.tone == .custom
                     ? "Describe the desired tone, e.g. \"warm reply to an angry client, under 2 sentences\"."
                     : "Optional — overrides the preset's built-in instruction.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - UUID `Identifiable` for `.sheet(item:)` binding

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
