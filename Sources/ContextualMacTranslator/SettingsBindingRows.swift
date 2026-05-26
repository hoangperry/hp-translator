import SwiftUI

/// Editable row for one outbound binding (target language + register +
/// hotkey + optional custom style instruction). Hotkey is changed via a
/// modal recorder sheet (`onChangeHotkey` triggers parent to present it).
///
/// Extracted from `SettingsWindowController.swift` in v0.9.0 to keep
/// that file under the 800-line guideline after adding the OCR-capture
/// section. Pure refactor — no logic change.
struct OutboundBindingRow: View {
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
/// + hotkey + v0.8.4 in-picker toggle). Custom tone always shows the
/// instruction editor (it's the instruction); preset tones expose it as
/// an optional override.
///
/// Extracted from `SettingsWindowController.swift` in v0.9.0 alongside
/// `OutboundBindingRow` to honour the 800-line guideline. Pure refactor.
struct RewriteBindingRow: View {
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

/// v0.11.0 — One row per `PromptBinding` in Settings → Prompt Engineer.
/// Edit the user-visible name, target language, custom expansion
/// guidelines, and the bound hotkey. Mirrors the structure of
/// `RewriteBindingRow` deliberately so power users learn one layout.
struct PromptBindingRow: View {
    @Binding var binding: PromptBinding
    let onChangeHotkey: () -> Void
    let onDelete: () -> Void
    @State private var showCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $binding.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

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
                .help("Remove this prompt binding")
            }

            HStack {
                Text("Output language")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $binding.targetLanguage) {
                    ForEach(LanguageCatalog.supported) { lang in
                        Text("\(lang.englishName) — \(lang.nativeName)").tag(lang.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
                Spacer()
                Toggle(isOn: $showCustom) {
                    Text("Custom expansion guidelines")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Override the default expansion template (e.g. pin a tech stack, switch AI assistant flavour)")
            }

            if showCustom || !binding.styleInstruction.isEmpty {
                TextEditor(text: $binding.styleInstruction)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                Text("Leave blank to use the default expansion template (covers Claude Code, Codex, ChatGPT, Claude Desktop). Pin a specific tech stack or AI-assistant flavour here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
