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
    /// v0.10.0 — guard against concurrent taps of "Test Ollama
    /// connection" launching multiple URLSession pings that race on
    /// `testResult` (M1 from v0.10.0 deliver-phase review).
    @State private var isTesting = false
    /// v0.10.0 — cached provider class + name, populated once on view
    /// appear and refreshed only when the user actually flips the
    /// provider source in Settings (H1 from review — was re-allocating
    /// a TranslationProviderFactory on every SwiftUI render pass via
    /// the `activeProvider` computed property).
    @State private var cachedClass: ProviderPrivacyClass = .cloud
    @State private var cachedName: String = ""

    private enum TestResult: Equatable {
        case ok(model: String)
        case failed(reason: String)
    }

    /// v0.10.0 — `static let` URL constants so the URL(string:)
    /// force-unwrap evaluates once at module load instead of on every
    /// SwiftUI render pass (H2 from review — matches the codebase's
    /// zero-runtime-`!` policy enforced across v0.9.x).
    private enum OllamaLinks {
        static let download = URL(string: "https://ollama.com/download")!
        static let library  = URL(string: "https://ollama.com/library")!
    }

    // MARK: - Provider resolution

    /// Re-resolve the active provider class + display name. Cheap
    /// when called on-change (not per-render). Reads through
    /// TranslationProviderFactory so the same logic the workflow uses
    /// drives the badge — no chance of drift.
    private func refreshProvider() {
        let provider = TranslationProviderFactory(settings: settings).make()
        cachedClass = type(of: provider).privacyClass
        cachedName = type(of: provider).displayName
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
        // v0.10.0 — refresh the cached provider only on appear + when
        // the user changes the source/provider in Settings, NOT on
        // every SwiftUI invalidation (H1 mitigation from review).
        .onAppear { refreshProvider() }
        .onChange(of: settings.directProvider) { _, _ in refreshProvider() }
        .onChange(of: settings.translationSource) { _, _ in refreshProvider() }
    }

    // MARK: - Ribbon

    @ViewBuilder
    private var ribbon: some View {
        HStack(spacing: 10) {
            Text("\(cachedClass.badgeSymbol) \(cachedClass.badgeLabel)")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint(for: cachedClass), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(ribbonHeadline(for: cachedClass))
                    .font(.body)
                Text("Active provider: \(cachedName.isEmpty ? "Resolving…" : cachedName)")
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
                Link("Download Ollama for Mac", destination: OllamaLinks.download)
                Spacer()
                Link("Browse models", destination: OllamaLinks.library)
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
                Button(isTesting ? "Testing…" : "Test Ollama connection") {
                    // M1 mitigation — guard against concurrent taps
                    // launching racing URLSession pings.
                    guard !isTesting else { return }
                    Task { await testConnection() }
                }
                .controlSize(.small)
                .disabled(isTesting)
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
        isTesting = true
        defer { isTesting = false }

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
            testResult = decodeTagsResponse(data: data)
        } catch {
            testResult = .failed(reason: "Couldn't reach Ollama: \(error.localizedDescription)")
        }
    }

    /// v0.10.0 — parse Ollama's `/api/tags` JSON and do exact-name
    /// matching against `settings.ollamaModel` (M3 from review — was
    /// using raw `bodyText.contains(...)` which gave false positives
    /// for "qwen2" against "qwen2.5:7b-instruct"). Falls back to
    /// "connected (no model name match)" when JSON is unparseable or
    /// the configured model isn't listed.
    private func decodeTagsResponse(data: Data) -> TestResult {
        let configuredModel = settings.ollamaModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        struct TagsBody: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        if let body = try? JSONDecoder().decode(TagsBody.self, from: data) {
            let names = body.models.map(\.name)
            if !configuredModel.isEmpty && names.contains(configuredModel) {
                return .ok(model: configuredModel)
            }
        }
        // Daemon reachable but model not (yet) pulled.
        return .ok(model: "")
    }
}
