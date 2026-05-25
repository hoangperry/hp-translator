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
    @State private var captureRecorderShown = false
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
            // v0.10.0 — Privacy section sits BETWEEN translation source
            // and glossary so users see the privacy class of whatever
            // they just picked (cloud / local / hosted) before reaching
            // glossary + rewrite config.
            SettingsPrivacySection(settings: settings)
            glossarySection
            rewriteSection
            captureSection
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
                hotkey: optionalHotkeyBinding(
                    \.pickerHotkey,
                    fallback: HotkeyConfig.defaultPicker
                ),
                isPresented: $pickerRecorderShown,
                ownerBindingID: nil
            )
        }
        // v0.9.0 — OCR capture recorder sheet. Default suggestion is
        // ⌘⌥G (mnemonic: "grab") when the user opens the recorder for
        // the first time; saved on confirm.
        .sheet(isPresented: $captureRecorderShown) {
            HotkeyRecorderSheet(
                hotkey: optionalHotkeyBinding(
                    \.captureHotkey,
                    fallback: HotkeyConfig.defaultCapture
                ),
                isPresented: $captureRecorderShown,
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

    /// v0.10.0 — section body extracted to `SettingsGlossarySection.swift`
    /// so this file stays under the 800-line guideline. Now wraps the
    /// typed `glossaryEntries` editor + the preserved legacy free-text
    /// blob into one Section.
    private var glossarySection: some View {
        SettingsGlossarySection(
            entries: $settings.glossaryEntries,
            legacyText: $settings.glossary
        )
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

            // v0.10.0 — VN social register card. Inactive by default
            // (registerCard == nil) → v0.9.x prompt behaviour byte-
            // identical. Section view lives in SettingsRegisterCardSection.swift
            // to keep this file under the 800-line guideline.
            SettingsRegisterCardSection(registerCard: $settings.registerCard)

            // v0.8.5 — multi-variant rewrite. Off by default to keep
            // existing users on the cheaper single-draft path.
            Toggle(isOn: $settings.multiVariantRewriteEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate 3 drafts per rewrite")
                    Text("Each rewrite invocation produces 3 different drafts in one round-trip. Browse them in the preview HUD with ← / → or ⌘1–3 before sending. Uses ~1.5–2× tokens but only one network call.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: - OCR capture (v0.9.0)

    /// "Capture" section — bind a hotkey to OCR-from-screen translate.
    /// User presses hotkey → system crosshair → OCR → translate into
    /// primary language → PreviewHUD in copy-mode.
    private var captureSection: some View {
        Section("Capture") {
            Text("Bind a hotkey to OCR text from any region of your screen, then translate it into \(LanguageCatalog.englishName(for: settings.primaryLanguage)). Works with the system crosshair (drag to select, Esc to cancel) — same UX as ⌘⇧4.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("OCR capture hotkey")
                        .font(.subheadline.bold())
                    Spacer()
                    if let hotkey = settings.captureHotkey {
                        Text(hotkey.displayLabel)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        Button("Change…") { captureRecorderShown = true }
                        Button(role: .destructive) {
                            settings.captureHotkey = nil
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Disable the OCR capture hotkey")
                    } else {
                        Text("Not set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Set hotkey") { captureRecorderShown = true }
                    }
                }
                Text("Recognises Vietnamese, English, Simplified Chinese, Japanese, Korean. Language auto-detected; result opens in a copy-mode preview (no auto-paste).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Onboarding card — first OCR invocation triggers the
            // Screen Recording TCC prompt, so prime users to expect it
            // and give them a direct link to fix it if they denied.
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "First capture asks for Screen Recording permission. If you denied it, re-enable here:",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings → Screen Recording") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
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

    /// v0.9.2 — synthetic `Binding<HotkeyConfig>` over an optional
    /// settings property with a pre-allocated fallback. Centralises the
    /// pattern shared by the picker + capture recorder sheets so they
    /// stay byte-identical, and avoids allocating a new HotkeyConfig
    /// per SwiftUI render pass (LOW-2 from the v0.9.0 review).
    private func optionalHotkeyBinding(
        _ keyPath: ReferenceWritableKeyPath<SettingsStore, HotkeyConfig?>,
        fallback: HotkeyConfig
    ) -> Binding<HotkeyConfig> {
        Binding<HotkeyConfig>(
            get: { settings[keyPath: keyPath] ?? fallback },
            set: { settings[keyPath: keyPath] = $0 }
        )
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

// `OutboundBindingRow` + `RewriteBindingRow` extracted to
// `SettingsBindingRows.swift` in v0.9.0 (P6) so this file stays under
// the 800-line guideline after the new Capture section landed. Pure
// move — no behaviour change.

// MARK: - UUID `Identifiable` for `.sheet(item:)` binding

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
