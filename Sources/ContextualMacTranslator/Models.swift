import Carbon.HIToolbox
import Foundation

enum TranslationDirection: String, Codable, Sendable {
    case inbound
    case outbound
}

/// Formality level / register applied to outbound translations. The
/// LLM/MT provider is responsible for translating the abstract level into
/// per-language conventions:
///
/// - JP: formal = keigo (敬語), casual = タメ口
/// - KR: formal = jondaemal (존댓말), casual = banmal (반말)
/// - FR: formal = vouvoiement, casual = tutoiement
/// - DE: formal = Sie, casual = du
/// - EN: formal = polite professional, casual = informal
///
/// `neutral` is used for inbound flows where the target is reading-only
/// and the LLM should pick whatever sounds most natural.
enum Register: String, Codable, CaseIterable, Identifiable, Sendable {
    case formal
    case casual
    case neutral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .neutral: return "Neutral"
        }
    }

    /// Adverb shown beside the language name in HUD/Settings labels.
    /// e.g. "Japanese (formal)".
    var label: String? {
        switch self {
        case .formal: return "formal"
        case .casual: return "casual"
        case .neutral: return nil
        }
    }
}

/// Concrete style for a single translation. Replaces the v0.2 `Persona`
/// enum so the app supports arbitrary (target language, register) pairs
/// instead of three hardcoded combinations.
struct TranslationStyle: Codable, Equatable, Hashable, Sendable {
    let direction: TranslationDirection
    let targetLanguage: String   // BCP47 — e.g. "vi", "ja", "en", "zh-CN"
    let register: Register
    /// Per-binding LLM style instruction override. When non-empty, used
    /// instead of the derived (lang, register) instruction. Empty string
    /// = use the derived default.
    let customStyleInstruction: String

    init(
        direction: TranslationDirection,
        targetLanguage: String,
        register: Register,
        customStyleInstruction: String = ""
    ) {
        self.direction = direction
        self.targetLanguage = targetLanguage
        self.register = register
        self.customStyleInstruction = customStyleInstruction
    }

    var languageDisplayName: String {
        LanguageCatalog.englishName(for: targetLanguage)
    }

    /// Human-readable label used in HUD title + Settings rows.
    var displayName: String {
        let lang = languageDisplayName
        switch direction {
        case .inbound:
            return "\(lang) reader"
        case .outbound:
            if let label = register.label {
                return "\(lang) (\(label))"
            }
            return lang
        }
    }

    /// Short badge for the HUD persona indicator.
    var displayBadge: String {
        switch (targetLanguage, register, direction) {
        case ("ja", .formal, .outbound): return "敬語"
        case ("ja", .casual, .outbound): return "カジュアル"
        case ("vi", _, _):                return "VN"
        case ("en", _, _):                return "EN"
        case ("ko", .formal, .outbound): return "존댓말"
        case ("ko", .casual, .outbound): return "반말"
        case ("zh-CN", _, _), ("zh", _, _): return "中"
        case ("zh-TW", _, _):             return "繁"
        case ("fr", _, _):                return "FR"
        case ("de", _, _):                return "DE"
        case ("es", _, _):                return "ES"
        case ("it", _, _):                return "IT"
        default:
            return targetLanguage.uppercased()
        }
    }

    /// Outbound formal translations open the preview HUD before injecting
    /// keystrokes — high-stakes register, mistakes are catastrophic.
    /// Casual + inbound auto-display.
    var previewByDefault: Bool {
        direction == .outbound && register == .formal
    }

    /// Style instruction passed alongside the system prompt. Uses
    /// `customStyleInstruction` when set; otherwise derives from
    /// (target language, register).
    var styleInstruction: String {
        if !customStyleInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customStyleInstruction
        }
        return derivedStyleInstruction
    }

    /// Default LLM instruction for this (lang, register) pair, used when
    /// the binding doesn't override it.
    var derivedStyleInstruction: String {
        let langName = languageDisplayName
        switch register {
        case .formal:
            return "Translate into \(langName) using formal/polite register appropriate for business or professional contexts. For Japanese, use keigo (敬語). For Korean, use jondaemal (존댓말). For French/Italian/Spanish, use the formal `vous` / `usted` form. For German, use the polite `Sie`. For English, use a polite professional tone. Match conventions of the target language."
        case .casual:
            return "Translate into \(langName) using casual/informal register suitable for chat between friends or peers. Avoid stiff or overly formal vocabulary. Match conventions of the target language for friendly conversation."
        case .neutral:
            return "Translate into natural \(langName), preserving meaning and nuance. Use a neutral register suitable for general reading."
        }
    }

    // MARK: - Legacy presets (back-compat for existing tests + defaults)

    static let vietnameseReader = TranslationStyle(
        direction: .inbound,
        targetLanguage: "vi",
        register: .neutral
    )

    static let japaneseBusiness = TranslationStyle(
        direction: .outbound,
        targetLanguage: "ja",
        register: .formal
    )

    static let japaneseCasual = TranslationStyle(
        direction: .outbound,
        targetLanguage: "ja",
        register: .casual
    )
}

/// Single translation request as the workflow constructs and providers
/// consume. The `style` carries direction + target lang + register; the
/// source language is sent separately so providers can use `auto` for
/// detection on inbound.
struct TranslationJob: Codable, Sendable {
    let text: String
    let style: TranslationStyle
    let sourceLanguage: String   // BCP47 or "auto"
    let glossary: String

    init(
        text: String,
        style: TranslationStyle,
        sourceLanguage: String,
        glossary: String
    ) {
        self.text = text
        self.style = style
        self.sourceLanguage = sourceLanguage
        self.glossary = glossary
    }

    // Convenience accessors so providers don't have to reach through `style`
    // for the most-common fields.
    var direction: TranslationDirection { style.direction }
    var targetLanguage: String { style.targetLanguage }
    var register: Register { style.register }
}

struct TranslationResult: Codable, Sendable {
    let translation: String
}

// MARK: - Language catalog

/// Curated set of target languages presented in Settings pickers. Codes
/// are BCP47; the LLM/MT providers all accept these. List intentionally
/// kept short (~30) to avoid scroll fatigue; user can add custom code via
/// Settings free-form input as a follow-up.
struct LanguageOption: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let englishName: String
    let nativeName: String

    var id: String { code }
}

enum LanguageCatalog {
    static let supported: [LanguageOption] = [
        .init(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt"),
        .init(code: "ja", englishName: "Japanese", nativeName: "日本語"),
        .init(code: "en", englishName: "English", nativeName: "English"),
        .init(code: "ko", englishName: "Korean", nativeName: "한국어"),
        .init(code: "zh-CN", englishName: "Chinese (Simplified)", nativeName: "简体中文"),
        .init(code: "zh-TW", englishName: "Chinese (Traditional)", nativeName: "繁體中文"),
        .init(code: "th", englishName: "Thai", nativeName: "ไทย"),
        .init(code: "id", englishName: "Indonesian", nativeName: "Bahasa Indonesia"),
        .init(code: "ms", englishName: "Malay", nativeName: "Bahasa Melayu"),
        .init(code: "tl", englishName: "Filipino", nativeName: "Filipino"),
        .init(code: "fr", englishName: "French", nativeName: "Français"),
        .init(code: "de", englishName: "German", nativeName: "Deutsch"),
        .init(code: "es", englishName: "Spanish", nativeName: "Español"),
        .init(code: "pt", englishName: "Portuguese", nativeName: "Português"),
        .init(code: "it", englishName: "Italian", nativeName: "Italiano"),
        .init(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
        .init(code: "ru", englishName: "Russian", nativeName: "Русский"),
        .init(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
        .init(code: "pl", englishName: "Polish", nativeName: "Polski"),
        .init(code: "tr", englishName: "Turkish", nativeName: "Türkçe"),
        .init(code: "ar", englishName: "Arabic", nativeName: "العربية"),
        .init(code: "he", englishName: "Hebrew", nativeName: "עברית"),
        .init(code: "hi", englishName: "Hindi", nativeName: "हिन्दी"),
        .init(code: "bn", englishName: "Bengali", nativeName: "বাংলা"),
        .init(code: "ta", englishName: "Tamil", nativeName: "தமிழ்"),
        .init(code: "fa", englishName: "Persian", nativeName: "فارسی"),
        .init(code: "sv", englishName: "Swedish", nativeName: "Svenska"),
        .init(code: "no", englishName: "Norwegian", nativeName: "Norsk"),
        .init(code: "da", englishName: "Danish", nativeName: "Dansk"),
        .init(code: "fi", englishName: "Finnish", nativeName: "Suomi"),
    ]

    static func englishName(for code: String) -> String {
        supported.first(where: { $0.code == code })?.englishName ?? code
    }

    static func nativeName(for code: String) -> String {
        supported.first(where: { $0.code == code })?.nativeName ?? code
    }
}

// MARK: - Hotkey configuration

/// Persisted hotkey: Carbon keyCode + modifier mask. `RegisterEventHotKey`
/// supports any combination of cmdKey/optionKey/controlKey/shiftKey paired
/// with a single non-modifier key.
struct HotkeyConfig: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    /// Visual label for Settings UI ("⌘⏎", "⌥D", "⌃⌥⏎").
    var displayLabel: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0  { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0     { parts.append("⌘") }
        parts.append(Self.keyCodeLabel(keyCode))
        return parts.joined()
    }

    static func keyCodeLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Return:       return "⏎"
        case kVK_Tab:           return "⇥"
        case kVK_Space:         return "␣"
        case kVK_Escape:        return "⎋"
        case kVK_Delete:        return "⌫"
        case kVK_LeftArrow:     return "←"
        case kVK_RightArrow:    return "→"
        case kVK_UpArrow:       return "↑"
        case kVK_DownArrow:     return "↓"
        case kVK_ANSI_A:        return "A"
        case kVK_ANSI_B:        return "B"
        case kVK_ANSI_C:        return "C"
        case kVK_ANSI_D:        return "D"
        case kVK_ANSI_E:        return "E"
        case kVK_ANSI_F:        return "F"
        case kVK_ANSI_G:        return "G"
        case kVK_ANSI_H:        return "H"
        case kVK_ANSI_I:        return "I"
        case kVK_ANSI_J:        return "J"
        case kVK_ANSI_K:        return "K"
        case kVK_ANSI_L:        return "L"
        case kVK_ANSI_M:        return "M"
        case kVK_ANSI_N:        return "N"
        case kVK_ANSI_O:        return "O"
        case kVK_ANSI_P:        return "P"
        case kVK_ANSI_Q:        return "Q"
        case kVK_ANSI_R:        return "R"
        case kVK_ANSI_S:        return "S"
        case kVK_ANSI_T:        return "T"
        case kVK_ANSI_U:        return "U"
        case kVK_ANSI_V:        return "V"
        case kVK_ANSI_W:        return "W"
        case kVK_ANSI_X:        return "X"
        case kVK_ANSI_Y:        return "Y"
        case kVK_ANSI_Z:        return "Z"
        case kVK_ANSI_0:        return "0"
        case kVK_ANSI_1:        return "1"
        case kVK_ANSI_2:        return "2"
        case kVK_ANSI_3:        return "3"
        case kVK_ANSI_4:        return "4"
        case kVK_ANSI_5:        return "5"
        case kVK_ANSI_6:        return "6"
        case kVK_ANSI_7:        return "7"
        case kVK_ANSI_8:        return "8"
        case kVK_ANSI_9:        return "9"
        default:                return "?"
        }
    }

    // Default presets matching v0.2 hardcoded behaviour (back-compat).
    static let defaultInbound = HotkeyConfig(keyCode: kVK_ANSI_D, modifiers: optionKey)
    static let defaultOutboundFormal = HotkeyConfig(keyCode: kVK_Return, modifiers: cmdKey)
    static let defaultOutboundCasual = HotkeyConfig(keyCode: kVK_Return, modifiers: optionKey)
}

// MARK: - Bindings

/// Hotkey + behaviour for the inbound (selection → my-language) flow.
struct InboundBinding: Codable, Equatable, Sendable {
    var hotkey: HotkeyConfig

    static let `default` = InboundBinding(hotkey: .defaultInbound)
}

/// One outbound binding = (target language + register + hotkey). Users
/// can have N of these; each registers a separate global hotkey.
struct OutboundBinding: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: UUID
    var languageCode: String   // BCP47
    var register: Register
    var hotkey: HotkeyConfig
    /// Optional override for the LLM style instruction. Empty means use
    /// the default derived from (target language, register).
    var customStyleInstruction: String

    init(
        id: UUID = UUID(),
        languageCode: String,
        register: Register,
        hotkey: HotkeyConfig,
        customStyleInstruction: String = ""
    ) {
        self.id = id
        self.languageCode = languageCode
        self.register = register
        self.hotkey = hotkey
        self.customStyleInstruction = customStyleInstruction
    }

    var displayName: String {
        let langName = LanguageCatalog.englishName(for: languageCode)
        if let label = register.label {
            return "\(langName) (\(label))"
        }
        return langName
    }

    func style(direction: TranslationDirection = .outbound) -> TranslationStyle {
        TranslationStyle(
            direction: direction,
            targetLanguage: languageCode,
            register: register,
            customStyleInstruction: customStyleInstruction
        )
    }

    // Default seed bindings reproduce v0.2 keigo + casual hotkeys.
    static let defaultJapaneseFormal = OutboundBinding(
        languageCode: "ja",
        register: .formal,
        hotkey: .defaultOutboundFormal
    )

    static let defaultJapaneseCasual = OutboundBinding(
        languageCode: "ja",
        register: .casual,
        hotkey: .defaultOutboundCasual
    )
}

// MARK: - Source picker (unchanged from v0.2)

/// Top-level "where does the translation come from" picker. Mirrors the
/// Settings UX choice: direct LLM/MT call from the app, a backend the
/// user runs themselves, or a 1st-party hosted instance.
enum TranslationSource: String, Codable, CaseIterable, Identifiable, Sendable {
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
enum DirectProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini
    case ollama
    case deepl              // v0.3 — DeepL Free / Pro
    case libreTranslate     // v0.3 — open-source MT, self-host or community instance
    case googleTranslate
    case openAICompatible
    case geminiCLI
    case codexCLI
    case mock

    var id: String { rawValue }

    var providerKey: String {
        switch self {
        case .gemini: return "gemini"
        case .ollama: return "ollama"
        case .deepl: return "deepl"
        case .libreTranslate: return "libretranslate"
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
        case .deepl: return "DeepL (Free)"
        case .libreTranslate: return "LibreTranslate (self-host or community)"
        case .googleTranslate: return "Google Translate Basic"
        case .openAICompatible: return "OpenAI-compatible API"
        case .geminiCLI: return "Gemini CLI (experimental)"
        case .codexCLI: return "Codex CLI (experimental)"
        case .mock: return "Mock (echo)"
        }
    }

    var requirementHint: String {
        switch self {
        case .gemini:
            return "Requires a Google AI Studio API key (free tier — 1500 req/day)."
        case .ollama:
            return "Requires a running Ollama instance (default http://127.0.0.1:11434)."
        case .deepl:
            return "Requires a DeepL Free or Pro API key (free tier — 500K chars/month). Top NMT quality for Japanese."
        case .libreTranslate:
            return "Open-source MT. Self-host via Docker for privacy + unlimited use; or use a community instance with optional API key."
        case .googleTranslate:
            return "Requires a Google Cloud API key with Translate Basic enabled."
        case .openAICompatible:
            return "Works with any OpenAI-compatible /chat/completions endpoint."
        case .geminiCLI:
            return "Spawns the `gemini` CLI per request — slower but reuses the CLI's auth."
        case .codexCLI:
            return "Spawns `codex exec` per request — slower; useful when you already have a Codex login."
        case .mock:
            return "Returns `[language] text` without calling any API. Useful for smoke tests."
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
            let suffix: String
            if let detail, !detail.isEmpty {
                suffix = " (\(detail))"
            } else {
                suffix = ""
            }
            return "Rate limit hit — slow down and retry in \(retryAfter)s\(suffix)."
        case .serverProblem(let status, let title, let detail):
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

// MARK: - Back-compat aliases

/// Legacy name retained so existing tests + provider code continue to
/// compile. Will be removed in a follow-up release once migrations land.
typealias Persona = TranslationStyle

extension TranslationStyle {
    /// Short identifier suitable for `provider` field on the wire.
    /// Mirrors the v0.2 `Persona` raw value where possible so existing
    /// backends understand the request.
    var rawValue: String {
        switch (direction, targetLanguage, register) {
        case (.inbound, "vi", _): return "vietnameseReader"
        case (.outbound, "ja", .formal): return "japaneseBusiness"
        case (.outbound, "ja", .casual): return "japaneseCasual"
        default:
            let dir = direction.rawValue
            return "\(dir)-\(targetLanguage)-\(register.rawValue)"
        }
    }
}
