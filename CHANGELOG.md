# Changelog

Toàn bộ thay đổi đáng chú ý của Contextual Mac Translator. Format theo
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) với semver
[MAJOR.MINOR.PATCH].

App đang ở giai đoạn alpha; mỗi release là pre-release trên GitHub.

## [Unreleased]

— (chưa có thay đổi)

## [0.3.1] — 2026-05-11

Closes follow-up backlog từ v0.3.0.

### Added

- **Hotkey recorder UI** — click "Change…" cạnh bất kỳ hotkey nào trong Settings để
  ghi lại combo mới. Built trên `NSEvent.keyDown` + Cocoa→Carbon modifier mapping.
  Esc cancels mid-record; required: ít nhất 1 modifier (⌘/⌥/⌃/⇧) + 1 phím thường.
- **Hotkey conflict detection** — recorder cảnh báo inline khi combo đã bound cho
  binding khác (inbound hoặc outbound). Save button disabled cho đến khi resolve.
- **Custom LLM style instruction per binding** — expandable TextEditor trong mỗi
  outbound binding. Override default register-aware instruction. Để trống = dùng
  derived default (back-compat).
- **Server-side DeepL + LibreTranslate providers** — backend mode giờ parity với app:
  `TRANSLATOR_PROVIDER=deepl` (Free/Pro endpoints, `formality=more/less` mapping)
  và `TRANSLATOR_PROVIDER=libretranslate` (community + self-host).

### Changed

- `TranslationStyle.customStyleInstruction` propagates từ `OutboundBinding` qua
  workflow tới providers; `styleInstruction` ưu tiên custom khi non-empty.
- Server `make_provider()` factory aliases: `libre`, `libre-translate`,
  `libre_translate` → `libretranslate`.

### Tests

- App: 150 Swift / 35 suites (no delta — UI changes use existing test paths).
- Server: 68 → **84 pytest / 17 classes** (+16 cases cho DeepL + LibreTranslate).
- Tổng: **234 GREEN**.

### Build

- Bundle 0.3.1 (build 9).

## [0.3.0] — 2026-05-10

Major UX expansion: rời khỏi VI↔JP hardcoded, hỗ trợ N target language với hotkey
tùy chỉnh.

### Added

- **Multi-language support** — `TranslationStyle(direction, targetLanguage, register)`
  thay `Persona` enum. 30 BCP47 ngôn ngữ curated trong Settings.
- **My language picker** — single user readable language; inbound luôn target
  về đây, outbound dùng làm source.
- **Unlimited outbound bindings** — mỗi (target language + register) là 1 binding
  riêng với hotkey configurable.
- **`HotKeyManager.register(_:)`** — dynamic register list thay 3 callback cứng;
  AppDelegate observe `SettingsStore` để re-register khi user đổi binding.
- **`DeepLDirectProvider`** — `api-free.deepl.com` / `api.deepl.com`, `formality=more/less`
  cho register, BCP47→DeepL code mapping (EN-US, ZH).
- **`LibreTranslateDirectProvider`** — base URL configurable (community + self-host),
  API key optional.
- **Settings UI v2** — `Languages` section với primary picker + outbound binding
  cards (add/remove, language picker, register, hotkey badge).
- **Edit menu cho LSUIElement app** — `Cmd-V`/`C`/`X`/`A`/`Z`/`⇧Cmd-Z` hoạt động
  trong Settings TextField/SecureField/TextEditor.
- **PATH augmentation cho CLI providers** — extend `/opt/homebrew/bin`,
  `/usr/local/bin`, `~/.local/bin`, `~/.cargo/bin` trong subprocess env nên
  `gemini`/`codex` tìm được khi app launched từ `/Applications`.

### Changed

- `Persona` enum → `Persona` typealias → `TranslationStyle` struct (back-compat
  static presets: `.vietnameseReader`, `.japaneseBusiness`, `.japaneseCasual`).
- `PromptBuilder` parameterized by target language name; LLM tự handle keigo/
  jondaemal/vouvoiement per language.
- `HUDController.dismiss()` — workflow gọi trước khi mở preview HUD để khỏi
  stacking double HUD ("Translating message…" + preview).

### Tests

- App: 124 → **150 Swift / 35 suites** (+26).
- Server: 68 pytest unchanged.
- Tổng: 192 → **218 GREEN**.

### Migration

Existing v0.2 users:
- `translationSource` default `.customBackend` (preserve endpoint+token).
- `primaryLanguage` default `vi`.
- `outboundBindings` seeded với 2 bindings JP (formal `⌘⏎` + casual `⌥⏎`).
- `inboundBinding` = `⌥D`.
- Tất cả hotkey cũ vẫn hoạt động không cần config lại.

## [0.2.0] — 2026-05-08

Multi-provider abstraction + Streaming SSE.

### Added

- **`TranslationProvider` protocol** + **7 direct providers**: Mock, Gemini, Ollama,
  Google Translate Basic, OpenAI-compatible, Gemini CLI, Codex CLI.
- **`TranslationProviderFactory`** — dispatch dựa vào `SettingsStore.translationSource`
  + `directProvider`.
- **Source picker UX**: Direct API / Custom backend / 1st-party backend, mỗi mode
  có credential slot riêng trong Keychain.
- **Streaming SSE** — `/translate/stream` endpoint trên server; `BackendProvider`
  conform `StreamingTranslationProvider`; inbound flow show progressive HUD chunks.
- **Server hardening** (Phase 1+2): body size cap (64 KiB → 413), log scrubbing
  qua stdlib `logging`, rate limiting per-IP (token bucket), Idempotency-Key cache
  in-memory (TTL 5 min), `validate_remote_host` từ chối non-loopback khi auth disabled.
- **RFC 7807 problem responses** với legacy `error` alias cho v1 client back-compat.
- **`Idempotency-Key` per request** từ app — chống double-paste khi network glitch.
- **`X-Forwarded-For`-aware rate limiting** — opt-in `TRANSLATOR_TRUST_FORWARDED_FOR=1`.
- **Deployment artifacts**: Dockerfile (non-root UID 10001, healthcheck), docker-compose.yml
  (read-only FS, cap_drop ALL), nginx config example, systemd service unit, `deploy.sh`.

### Changed

- `TranslatorAPI` renamed → `BackendProvider` (in `Providers/` subfolder).
- `TranslationWorkflow.translator` → `any TranslationProvider` (DI).

### Fixed

- HUD "Translating selection…" no longer disappears within 0.5s (removed `.transient`
  collection behaviour from `NSPanel`).

### Tests

- App: 25 → **122 Swift / 29 suites** (+97).
- Server: 21 → **68 pytest / 14 classes** (+47).
- Tổng: 46 → **190 GREEN**.

## [0.1.5] — 2026-05-08

M1 internal-alpha pre-release.

### Added

- **First-launch onboarding window** — gates hotkey registration until Accessibility
  granted; deep-links System Settings; polls permission state every second.
- **Tab-to-edit preview** — Tab key trong preview HUD switch sang `TextEditor` cho
  user chỉnh keigo translation trước khi gửi.
- **5s focus-loss auto-cancel** — preview HUD tự đóng nếu focus rời app gốc quá 5s.
- **Advanced toggle** — `focusGuardEnabled` cho user disable focus guard nếu false-positive.
- **Ad-hoc codesign** — `package_app.sh` ký bundle cho local distribution.
- **Local distribution scripts** — `package_installer.sh` (PKG), `package_dmg.sh` (DMG).

### Changed

- `CredentialMigration` qua `os.Logger` thay `try?` để diagnose KC write failures.
- `SettingsStore.didSet` guard `oldValue != newValue` ở mọi `@Published` để tránh
  spurious Keychain writes during `init`.
- HTTPS-only endpoint enforcement (`EndpointPolicy`) — non-loopback remote phải `https://`.

### Security findings closed

F-1 (Keychain), F-2 (bearer auth), F-3 (HTTPS-only), F-4 (clipboard race),
F-5 (focus guard), F-9 (glossary in Keychain).

## [0.1.0 – 0.1.4] — 2026-05-07/08

Early alpha iterations: bundle ID rename, sign mac app, installer/DMG packaging.
Chi tiết trong `git log v0.1.0..v0.1.4`.

[Unreleased]: https://github.com/hoangperry/hp-translator/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/hoangperry/hp-translator/releases/tag/v0.3.1
[0.3.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.3.0
[0.2.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.2.0
[0.1.5]: https://github.com/hoangperry/hp-translator/releases/tag/v0.1.5
