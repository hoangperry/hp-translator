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

enum TranslationError: LocalizedError {
    case missingEndpoint
    case emptyClipboard
    case missingTranslation
    case invalidResponse(Int)
    case backendUnreachable(endpoint: String)
    case insecureEndpoint(endpoint: String)
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
        case .focusChangedBeforePaste:
            return "Focus changed during translation — paste was suppressed to avoid typing into the wrong app."
        case .focusChangedAfterPaste:
            return "Focus changed after paste — Send was suppressed. The translated text was already pasted; review the target app."
        }
    }
}
