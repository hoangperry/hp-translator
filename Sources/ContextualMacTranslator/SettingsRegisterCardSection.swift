import SwiftUI

/// v0.10.0 — VN social Register Card panel for the Settings →
/// Contextual rewrite section. Extracted to its own file (like
/// `SettingsBindingRows.swift`) so `SettingsWindowController.swift`
/// stays under the 800-line guideline.
///
/// Renders 3 axis Pickers (dialect / kinship / formality) + a free-text
/// roleHint + a Reset button + a 1-line composed-prompt preview so the
/// user can see exactly what the LLM will receive.
///
/// Binding shim: the parent passes `Binding<RegisterCard?>` so a nil
/// card stays nil until the user touches a control; saving an
/// all-inactive card collapses back to nil to keep persisted Settings
/// state clean.
struct SettingsRegisterCardSection: View {
    @Binding var registerCard: RegisterCard?

    /// Live card view backing every axis Picker. Reads as a defaulted
    /// `RegisterCard()` when the underlying is `nil`; writes collapse
    /// back to `nil` on inactive (so an opened-then-cleared panel
    /// doesn't leave an empty shell persisted).
    private var card: Binding<RegisterCard> {
        Binding<RegisterCard>(
            get: { registerCard ?? RegisterCard() },
            set: { new in
                registerCard = new.isActive ? new : nil
            }
        )
    }

    /// One-line preview of the composed prompt block — caption-style
    /// so the user knows exactly what the LLM receives. Shows
    /// "(no register)" when the card is inactive (so the user can
    /// confirm the no-op is intentional).
    private var previewLine: String {
        let prompt = (registerCard ?? RegisterCard()).prompted(prefix: "")
        if prompt.isEmpty {
            return "(no register block sent — v0.9.x behaviour)"
        }
        // Collapse to single line for inline preview. Replace newlines
        // with " · " separator.
        return prompt
            .replacingOccurrences(of: "\n", with: " · ")
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vietnamese register card")
                    .font(.subheadline.bold())
                Spacer()
                Button(role: .destructive) {
                    registerCard = nil
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .disabled(registerCard == nil)
                .help("Clear the register card (revert to v0.9.x behaviour)")
            }

            Text("Inject Vietnamese kinship + dialect + formality into every rewrite + outbound translate. Apple Intelligence cannot do this per-locale precision; this is the v0.10.0 moat.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Three Pickers in one row.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                axisPicker(
                    title: "Dialect",
                    selection: card.dialect,
                    cases: RegisterCard.Dialect.allCases
                )
                axisPicker(
                    title: "Kinship",
                    selection: card.kinship,
                    cases: RegisterCard.Kinship.allCases
                )
                axisPicker(
                    title: "Formality",
                    selection: card.formality,
                    cases: RegisterCard.Formality.allCases
                )
            }

            // Free-text role hint (truncated to 80 chars before prompt
            // injection — UI doesn't enforce the limit, the model does).
            VStack(alignment: .leading, spacing: 4) {
                Text("Context (optional, ≤ 80 chars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "e.g. \"TikTok Shop seller addressing customer\"",
                    text: card.roleHint
                )
                .textFieldStyle(.roundedBorder)
            }

            // Composed-prompt preview (AC20).
            VStack(alignment: .leading, spacing: 4) {
                Text("Composed prompt preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Build a labelled `Picker` for one RegisterCard axis. Generic over
    /// the enum so all three axes share the same layout + accessibility
    /// shape.
    private func axisPicker<E: RawRepresentable & CaseIterable & Identifiable & Hashable>(
        title: String,
        selection: Binding<E>,
        cases: E.AllCases
    ) -> some View where E.AllCases.Element == E {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(Array(cases)) { value in
                    Text(displayName(for: value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
        }
    }

    /// Pull `displayName` off whichever RegisterCard enum case the
    /// generic axisPicker bound — Swift can't deduce the property
    /// from a constrained-protocol generic, so dispatch manually.
    private func displayName(for value: Any) -> String {
        switch value {
        case let d as RegisterCard.Dialect:    return d.displayName
        case let k as RegisterCard.Kinship:    return k.displayName
        case let f as RegisterCard.Formality:  return f.displayName
        default:                               return "?"
        }
    }
}
