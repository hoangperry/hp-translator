import SwiftUI

/// v0.10.0 — Glossary section for the Settings window. Owns BOTH the
/// new typed `glossaryEntries` editor (added in v0.10.0) and the
/// legacy `glossary: String` free-text TextEditor (preserved in a
/// collapsed disclosure so v0.9.x users still see their data).
///
/// Extracted from `SettingsWindowController.swift` so the host file
/// stays under the 800-line guideline after the v0.10.0 surface
/// landed. Pure refactor on the legacy side; the new editor lives
/// here from day one.
struct SettingsGlossarySection: View {
    @Binding var entries: [GlossaryEntry]
    @Binding var legacyText: String

    /// Soft cap mirrored from `define.md` §1 C.3 — keeps prompt budget
    /// bounded + prevents accidental long-term growth. Enforced in the
    /// UI (Add button disables); render-time cap is enforced again in
    /// `TranslationJob.structuredGlossary` during P6 (not implemented
    /// yet).
    private static let entryCap = 50

    @State private var legacyExpanded = false

    var body: some View {
        Section("Glossary") {
            Text("Pin brand names + casing rules + force-translate jargon. Applied by every LLM-class provider (Gemini, Ollama, OpenAI-compat, hosted backends). DeepL / Google Translate / LibreTranslate ignore glossary rules — that's a provider limitation, not a bug.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            entriesEditor

            DisclosureGroup(isExpanded: $legacyExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lines like `term = preferred translation`. Applied AFTER the structured rules above. Existing v0.9.x users: your data is preserved here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $legacyText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.separator, lineWidth: 1)
                        )
                }
            } label: {
                Label("Legacy free-text glossary", systemImage: "text.alignleft")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Entries editor

    @ViewBuilder
    private var entriesEditor: some View {
        HStack {
            Text("Structured rules")
                .font(.subheadline.bold())
            Spacer()
            Text("\(entries.count) / \(Self.entryCap)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            addEntryMenu
                .disabled(entries.count >= Self.entryCap)
                .help(entries.count >= Self.entryCap
                      ? "At cap — delete an entry to add more"
                      : "Add a new glossary rule")
        }

        if entries.isEmpty {
            Text("No structured rules yet. Use the Add button to pin brand names (don't translate), casing aliases (\"shopee\" → \"Shopee\"), or force-translate jargon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach($entries) { $entry in
                GlossaryEntryRow(entry: $entry) {
                    remove(entry)
                }
            }
            .onMove { source, destination in
                entries.move(fromOffsets: source, toOffset: destination)
            }
        }
    }

    private var addEntryMenu: some View {
        Menu {
            Button("Don't translate (brand / code)") {
                add(.dontTranslate(term: ""))
            }
            Button("Alias (casing / spelling)") {
                add(.alias(from: "", to: ""))
            }
            Button("Always translate (jargon)") {
                add(.alwaysTranslate(term: "", to: ""))
            }
        } label: {
            Label("Add entry", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func add(_ kind: GlossaryEntry.Kind) {
        entries.append(GlossaryEntry(kind: kind))
    }

    private func remove(_ entry: GlossaryEntry) {
        entries.removeAll { $0.id == entry.id }
    }
}

/// One editable row in the structured-glossary list. Type pill is
/// read-only — to change the kind, the user deletes + re-adds via the
/// menu. Keeps the row's state machine simple (1 vs 2 TextFields per
/// kind) without nested pickers.
private struct GlossaryEntryRow: View {
    @Binding var entry: GlossaryEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.kindLabel)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    pillTint,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .frame(width: 130, alignment: .leading)

            fields

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
        }
        .padding(.vertical, 2)
    }

    /// Per-kind 1-or-2 TextField layout. Bindings synthesise a new
    /// `GlossaryEntry.Kind` on each edit so the parent's `entries`
    /// array stays the single source of truth.
    @ViewBuilder
    private var fields: some View {
        switch entry.kind {
        case .dontTranslate:
            TextField(
                "Term (e.g. React, JIRA-1234, FREESHIP)",
                text: termBinding
            )
            .textFieldStyle(.roundedBorder)
        case .alias:
            TextField("From", text: fromBinding)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            TextField("To", text: toBinding)
                .textFieldStyle(.roundedBorder)
        case .alwaysTranslate:
            TextField("Term", text: termBinding)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            TextField("To", text: toBinding)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Subtle tint so each kind is recognisable at a glance without
    /// reading the pill text. Keeps with the v0.8 picker visual tone.
    private var pillTint: some ShapeStyle {
        switch entry.kind {
        case .dontTranslate:    return AnyShapeStyle(.blue.opacity(0.18))
        case .alias:            return AnyShapeStyle(.green.opacity(0.18))
        case .alwaysTranslate:  return AnyShapeStyle(.orange.opacity(0.18))
        }
    }

    // MARK: - Synthesized payload bindings

    private var termBinding: Binding<String> {
        Binding<String>(
            get: {
                switch entry.kind {
                case .dontTranslate(let term):       return term
                case .alwaysTranslate(let term, _):   return term
                case .alias:                          return ""
                }
            },
            set: { new in
                switch entry.kind {
                case .dontTranslate:
                    entry.kind = .dontTranslate(term: new)
                case .alwaysTranslate(_, let to):
                    entry.kind = .alwaysTranslate(term: new, to: to)
                case .alias:
                    break
                }
            }
        )
    }

    private var fromBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .alias(let from, _) = entry.kind { return from }
                return ""
            },
            set: { new in
                if case .alias(_, let to) = entry.kind {
                    entry.kind = .alias(from: new, to: to)
                }
            }
        )
    }

    private var toBinding: Binding<String> {
        Binding<String>(
            get: {
                switch entry.kind {
                case .alias(_, let to):              return to
                case .alwaysTranslate(_, let to):    return to
                case .dontTranslate:                  return ""
                }
            },
            set: { new in
                switch entry.kind {
                case .alias(let from, _):
                    entry.kind = .alias(from: from, to: new)
                case .alwaysTranslate(let term, _):
                    entry.kind = .alwaysTranslate(term: term, to: new)
                case .dontTranslate:
                    break
                }
            }
        )
    }
}
