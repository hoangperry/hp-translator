import AppKit
import SwiftUI

/// v0.10.0 — Privacy section for the Settings window. Shows the
/// active provider's class ribbon, an Ollama-installation onboarding
/// card, and a one-click test-connection button. Extracted to its own
/// file (mirrors the SettingsRegisterCardSection / SettingsGlossarySection
/// pattern from earlier v0.10.0 phases) so SettingsWindowController.swift
/// stays under the 800-line guideline.
///
/// Provider class is resolved from `TranslationProviderFactory.make()`
/// — same source the workflow uses. Reactive: switching providers in
/// Settings updates the ribbon on the next view-model observation pass
/// without manual refresh.
struct SettingsPrivacySection: View {
    @Bindable var settings: SettingsStore
    @State private var ollamaExpanded = false
    @State private var testResult: TestResult? = nil

    private enum TestResult: Equatable {
        case ok(model: String)
        case failed(reason: String)
    }

    // MARK: - Provider resolution

    /// Resolves the currently-active provider's class + display name.
    /// Reads through `TranslationProviderFactory` so the same logic
    /// the workflow uses drives the badge — no chance of drift.
    private var activeProvider: (cls: ProviderPrivacyClass, name: String) {
        let provider = TranslationProviderFactory(settings: settings).make()
        return (
            type(of: provider).privacyClass,
            type(of: provider).displayName
        )
    }

    var body: some View {
        Section("Privacy") {
            ribbon

            DisclosureGroup(isExpanded: $ollamaExpanded) {
                ollamaCard
            } label: {
                Label("Run translations locally with Ollama", systemImage: "shield.lefthalf.filled")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Ribbon

    @ViewBuilder
    private var ribbon: some View {
        let provider = activeProvider
        HStack(spacing: 10) {
            Text("\(provider.cls.badgeSymbol) \(provider.cls.badgeLabel)")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint(for: provider.cls), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(ribbonHeadline(for: provider.cls))
                    .font(.body)
                Text("Active provider: \(provider.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func ribbonHeadline(for cls: ProviderPrivacyClass) -> String {
        switch cls {
        case .local:
            return "🛡 Local only — không gửi dữ liệu khách ra nước ngoài."
        case .cloud:
            return "Text is sent to a 3rd-party cloud provider."
        case .hosted:
            return "Text is sent to your configured 1st-party backend."
        }
    }

    private func tint(for cls: ProviderPrivacyClass) -> AnyShapeStyle {
        switch cls {
        case .local:  return AnyShapeStyle(.green.opacity(0.22))
        case .cloud:  return AnyShapeStyle(.blue.opacity(0.20))
        case .hosted: return AnyShapeStyle(.orange.opacity(0.22))
        }
    }

    // MARK: - Ollama onboarding card

    @ViewBuilder
    private var ollamaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ollama runs LLMs on your Mac with zero cloud round-trip. Recommended for chats with customers or anything that touches PII.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Download Ollama for Mac", destination: URL(string: "https://ollama.com/download")!)
                Spacer()
                Link("Browse models", destination: URL(string: "https://ollama.com/library")!)
            }
            .font(.caption)

            ForEach(curatedCommands, id: \.self) { command in
                HStack(spacing: 6) {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            .secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    Button {
                        copyToClipboard(command)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .help("Copy command")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Button("Test Ollama connection") {
                    Task { await testConnection() }
                }
                .controlSize(.small)
                Spacer()
                resultLabel
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var resultLabel: some View {
        switch testResult {
        case .none:
            EmptyView()
        case .ok(let model):
            Label(model.isEmpty ? "Connected" : "Connected — \(model) ready",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    private let curatedCommands = [
        "ollama pull qwen2.5:7b-instruct",
        "ollama pull gemma3:4b-it",
    ]

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    // MARK: - Connection test

    /// Pings `<ollamaBaseURL>/api/tags` with a 2s timeout. Surfaces a
    /// red/green inline label rather than an alert — keeps the
    /// Settings window in flow.
    private func testConnection() async {
        let base = settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base + "/api/tags") else {
            testResult = .failed(reason: "Bad Ollama URL.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                testResult = .failed(reason: "Ollama returned HTTP \(status).")
                return
            }
            // Look for the configured model in /api/tags. If the body is
            // unparseable or the model isn't listed, still report
            // success — the daemon is reachable, just no model pulled.
            let configuredModel = settings.ollamaModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if !configuredModel.isEmpty && bodyText.contains(configuredModel) {
                testResult = .ok(model: configuredModel)
            } else {
                testResult = .ok(model: "")
            }
        } catch {
            testResult = .failed(reason: "Couldn't reach Ollama: \(error.localizedDescription)")
        }
    }
}
