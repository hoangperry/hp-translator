import Foundation

enum TranslationDirection: String, Codable {
    case inbound
    case outbound
}

enum Persona: String, CaseIterable, Codable, Identifiable {
    case vietnameseReader
    case japaneseBusiness
    case japaneseCasual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vietnameseReader:
            return "Vietnamese Reader"
        case .japaneseBusiness:
            return "Japanese Keigo"
        case .japaneseCasual:
            return "Japanese Casual"
        }
    }

    /// Short visual badge shown in the HUD/menu bar to indicate active register.
    var displayBadge: String {
        switch self {
        case .vietnameseReader:
            return "VN"
        case .japaneseBusiness:
            return "敬語"
        case .japaneseCasual:
            return "カジュアル"
        }
    }

    var targetLanguage: String {
        switch self {
        case .vietnameseReader:
            return "vi"
        case .japaneseBusiness, .japaneseCasual:
            return "ja"
        }
    }

    var styleInstruction: String {
        switch self {
        case .vietnameseReader:
            return "Translate into natural Vietnamese. Preserve technical terms from the glossary."
        case .japaneseBusiness:
            return "Translate into business Japanese using polite keigo. Keep the tone concise and suitable for workplace chat."
        case .japaneseCasual:
            return "Translate into casual Japanese suitable for friendly chat. Keep it natural, direct, and not overly formal."
        }
    }

    /// When `true`, outbound workflows show a preview HUD before injecting
    /// `paste` + `Return`. Keigo defaults to preview because mistakes are
    /// catastrophic for register; casual defaults to auto-send for velocity.
    /// (PRD §5.1 FW-2 / FW-3, Define Section A Q9.)
    var previewByDefault: Bool {
        switch self {
        case .vietnameseReader, .japaneseCasual:
            return false
        case .japaneseBusiness:
            return true
        }
    }
}

struct TranslationJob: Codable {
    let text: String
    let direction: TranslationDirection
    let sourceLanguage: String
    let targetLanguage: String
    let persona: Persona
    let glossary: String
}

struct TranslationResult: Codable {
    let translation: String
}

/// Top-level "where does the translation come from" picker. Mirrors the
/// Settings UX choice: direct LLM/MT call from the app, a backend the
/// user runs themselves, or a 1st-party hosted instance.
enum TranslationSource: String, Codable, CaseIterable, Identifiable {
    case directAPI
    case customBackend
    case firstPartyBackend

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .directAPI:
            return "Direct API"
        case .customBackend:
            return "Custom backend"
        case .firstPartyBackend:
            return "1st-party backend"
        }
    }

    var summary: String {
        switch self {
        case .directAPI:
            return "Call your chosen LLM / translate API straight from the app — no backend hop."
        case .customBackend:
            return "Point at a translator-server you (or a colleague) hosts."
        case .firstPartyBackend:
            return "Use a hosted translator-server (token issued by the service operator)."
        }
    }
}

/// Concrete provider chosen when `translationSource == .directAPI`.
/// Order matches Python `make_provider()` dispatch and Settings picker.
enum DirectProviderKind: String, Codable, CaseIterable, Identifiable {
    case gemini
    case ollama
    case googleTranslate
    case openAICompatible
    case geminiCLI
    case codexCLI
    case mock

    var id: String { rawValue }

    /// Stable key shared with the backend's per-request `provider` field.
    var providerKey: String {
        switch self {
        case .gemini: return "gemini"
        case .ollama: return "ollama"
        case .googleTranslate: return "google-translate"
        case .openAICompatible: return "openai-compatible"
        case .geminiCLI: return "gemini-cli"
        case .codexCLI: return "codex-cli"
        case .mock: return "mock"
        }
    }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini (Google AI Studio)"
        case .ollama: return "Ollama (local)"
        case .googleTranslate: return "Google Translate Basic"
        case .openAICompatible: return "OpenAI-compatible API"
        case .geminiCLI: return "Gemini CLI (experimental)"
        case .codexCLI: return "Codex CLI (experimental)"
        case .mock: return "Mock (echo)"
        }
    }

    /// Hint shown beneath the picker so users know what they need before
    /// switching to this provider.
    var requirementHint: String {
        switch self {
        case .gemini:
            return "Requires a Google AI Studio API key (free tier available)."
        case .ollama:
            return "Requires a running Ollama instance (default http://127.0.0.1:11434)."
        case .googleTranslate:
            return "Requires a Google Cloud API key with Translate Basic enabled."
        case .openAICompatible:
            return "Works with any OpenAI-compatible /chat/completions endpoint."
        case .geminiCLI:
            return "Spawns the `gemini` CLI per request — slower but reuses the CLI's auth."
        case .codexCLI:
            return "Spawns `codex exec` per request — slower; useful when you already have a Codex login."
        case .mock:
            return "Returns `[persona] text` without calling any API. Useful for smoke tests."
        }
    }
}

enum TranslationError: LocalizedError {
    case missingEndpoint
    case emptyClipboard
    case missingTranslation
    case invalidResponse(Int)
    case backendUnreachable(endpoint: String)
    case insecureEndpoint(endpoint: String)
    case rateLimited(retryAfter: Int, detail: String?)
    case serverProblem(status: Int, title: String?, detail: String?)
    case focusChangedBeforePaste
    case focusChangedAfterPaste

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Configure the backend API endpoint in Settings first."
        case .emptyClipboard:
            return "No text was copied from the active app."
        case .missingTranslation:
            return "The backend response did not include a translation."
        case .invalidResponse(let statusCode):
            switch statusCode {
            case 401, 403:
                return "Backend rejected the request (HTTP \(statusCode)). Check the API key in Settings."
            case 404:
                return "Backend endpoint not found (HTTP 404). Verify the URL in Settings ends with /translate."
            case 500...599:
                return "Backend error (HTTP \(statusCode)). Check the server logs."
            default:
                return "Backend request failed with HTTP \(statusCode)."
            }
        case .backendUnreachable(let endpoint):
            return "Could not reach backend at \(endpoint). Make sure the server is running and the endpoint URL is correct in Settings."
        case .insecureEndpoint(let endpoint):
            return "Endpoint must use HTTPS unless it is localhost or 127.0.0.1: \(endpoint)"
        case .rateLimited(let retryAfter, let detail):
            // v2: backend signalled 429. Surface the wait so the user knows
            // when to retry instead of staring at a generic error.
            let suffix: String
            if let detail, !detail.isEmpty {
                suffix = " (\(detail))"
            } else {
                suffix = ""
            }
            return "Rate limit hit — slow down and retry in \(retryAfter)s\(suffix)."
        case .serverProblem(let status, let title, let detail):
            // v2: RFC 7807 problem body parsed; prefer detail > title > generic.
            if let detail, !detail.isEmpty {
                return "Backend (HTTP \(status)): \(detail)"
            }
            if let title, !title.isEmpty {
                return "Backend (HTTP \(status)): \(title)"
            }
            return "Backend request failed with HTTP \(status)."
        case .focusChangedBeforePaste:
            return "Focus changed during translation — paste was suppressed to avoid typing into the wrong app."
        case .focusChangedAfterPaste:
            return "Focus changed after paste — Send was suppressed. The translated text was already pasted; review the target app."
        }
    }
}
