# Changelog

Toàn bộ thay đổi đáng chú ý của Contextual Mac Translator. Format theo
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) với semver
[MAJOR.MINOR.PATCH].

App đang ở giai đoạn alpha; mỗi release là pre-release trên GitHub.

## [Unreleased]

### Planned — distribution hardening

- **Bundle ID migration** *(breaking cho Keychain entries cũ)* —
  `app.lookerlab.translator` → `dev.hoangtruong.translator`. App sẽ hiện
  banner trên first launch yêu cầu nhập lại credentials.

## [0.8.2] — 2026-05-24

**New tone: "Chửi thề" (casual-raw).** Opt-in expressive rewrite tone
that matches Vietnamese close-friends chat register — uses profanity
markers like vl/vcl/đm as natural intensifiers (the "as hell" / "af"
of Vietnamese internet writing). Hidden behind a Settings toggle
default OFF; gated by a confirmation dialog when enabled. Routes
through Gemini with `safetySettings = BLOCK_NONE` so the model
doesn't refuse profanity-flavoured drafts.

### Added

- **`RewriteTone.casualRaw`** ("Chửi thề") — Vietnamese-aware tone
  instruction that emphasises **abbreviated** profanity forms (vl /
  vcl / đm) over spelled-out vulgar phrases, and carves out hard
  safety rules: never add slurs, never attack identity, never add
  personal insults not in the input.
- **`SettingsStore.expressiveTonesEnabled`** — default OFF. Persists
  under `translator.expressiveTonesEnabled`. Gates whether
  `.casualRaw` appears in the picker + binding dropdowns.
- **`RewriteTone.available(expressive:)`** — single helper used by
  both `TonePickerController` and `RewriteBindingRow` so the visibility
  gate lives in one place.
- **`TranslationStyle.allowsExpressiveContent`** — flag that rides
  through on the style. `GeminiDirectProvider` reads it and attaches
  `safetySettings = BLOCK_NONE` for the four adjustable categories
  (HARASSMENT, HATE_SPEECH, SEXUALLY_EXPLICIT, DANGEROUS_CONTENT) —
  the non-adjustable CSAM / election filters remain enforced.
- **Settings UI** — toggle "Enable expressive tones (Chửi thề)" in
  the Contextual rewrite section. Flipping OFF → ON triggers a
  SwiftUI `.alert` explaining the tone's intent (friends, not
  customers; preview always shown; some providers may refuse) with
  Continue / Cancel. Cancel reverts cleanly without persisting.
- **`RewriteBindingRow`** filters its tone Picker by the toggle —
  but always shows the row's current tone even if it became
  expressive after toggle was turned off, so users can see what's
  bound without surprise.

### Notes

- Workflow-level consent (NSAlert mid-flow) was **not** added — it
  would activate the app and break the source-app focus contract,
  causing paste to land in the wrong field. The Settings-level
  toggle is the consent point.

### Build

- Bundle 0.8.2 (build 22).

### Tests

- App: **250 Swift / 53 suites** GREEN in isolation (242 from v0.8.1
  + 8 new for casualRaw + expressive flag + Gemini permissive safety
  + Settings persistence). One pre-existing flaky test in
  `SupabaseAuthViewModel — input validation` continues to fail in
  full-suite runs but passes in isolation — same since v0.5.x.

## [0.8.1] — 2026-05-24

Code-review polish on top of v0.8.0 (LOW findings). No behaviour change.

### Changed

- `TonePickerController` now derives both the panel `contentRect` and
  the cursor-anchored origin from a single `private let panelSize`
  constant — the two can no longer drift.
- Removed `TonePickerViewModel.clampSelectionAfterFilter()` and its
  test. The view's `.onChange(of: model.query)` already resets the
  selection to 0 on every filter change (Spotlight / Raycast UX) —
  the unused clamp helper would have been a different UX
  (preserve-if-in-range) and was dead code.

### Build

- Bundle 0.8.1 (build 21).

### Tests

- App: **242 Swift / 52 suites** GREEN (−1 from the removed clamp test).

## [0.8.0] — 2026-05-24

**New feature: Tone picker hotkey.** Bind ONE global hotkey to open a
popup picker listing every tone (Polite, Professional, Friendly,
Firm-but-polite, De-escalate, Concise, Custom). Pick a tone with
arrow keys, `Return`, type-to-filter, or `⌘+1-7` quick-select; the
app rewrites the current input line in that tone and previews it
before sending. Hybrid with v0.7's per-binding model — both coexist.

### Added

- **`PickerPanel` + `TonePickerView` + `TonePickerViewModel`**
  (`TonePickerView.swift`) — non-activating `NSPanel` subclass with
  routed key handling (Esc / Return / ↑↓ / ⌘+digit); SwiftUI view with
  type-to-filter, pill rows, ⌘N badges, Liquid Glass background.
- **`TonePickerController`** (`TonePickerController.swift`) — clones
  the `PreviewHUDController` pattern: focus-loss timeout (5 s), dwell
  timeout (20 s), click-outside global event monitor, cursor-anchored
  positioning with screen-bounds clamping.
- **`SettingsStore.pickerHotkey: HotkeyConfig?`** — single global
  picker hotkey under `translator.pickerHotkey` (default `nil`).
  `bindingLabel` extended for conflict detection.
- **`FocusedElementInspector`** — AX role check via
  `AXUIElementCopyAttributeValue`. The picker workflow refuses paste
  into `AXSecureTextField` (password fields) before any keyboard
  simulation runs, so no draft snapshot leaks into LLM logs.
- **`TranslationWorkflow.rewriteWithPickerAndSend()`** — Option A
  capture flow: AX role gate → focusGuard → capture line →
  Right-Arrow collapse selection → eager clipboard restore → picker
  → rewrite → Preview HUD → paste. Cancel is a quiet exit.
- **`KeyboardSimulator.collapseSelectionToEnd()`** — Right-Arrow
  helper so a cancelled picker doesn't leave the user's draft selected.
- **Settings UI** — "Tone picker hotkey" row in Contextual rewrite
  section with recorder + clear button + conflict detection.
- **AppDelegate** wires the picker hotkey alongside rewrite bindings;
  re-press while picker is open toggles it closed instead of capturing
  a second line. `observeBindingsOnce` now tracks `pickerHotkey`.

### Notes / scope-out (deferred to v0.8.1+)

- "Chửi thề" (casual-raw) tone with provider-specific safety routing
  (Gemini `BLOCK_NONE` + Ollama abliterated fallback + one-time consent
  toast).
- Per-binding "In Picker" customization (MVP picker shows all built-in
  tones).
- Free-text "Describe the change…" input at the top of the picker.
- Pre-instantiate the picker panel at launch for <50 ms first paint.
- VoiceOver elevation + reduce-motion polish.

### Build

- Bundle 0.8.0 (build 20).

### Tests

- App: **243 Swift / 52 suites** GREEN (220 baseline + 23 new picker
  tests: `PickerPanel.map` key routing, `TonePickerViewModel` handler,
  filter behaviour, idempotent commit, `FocusedElementInspector` role
  classification, `SettingsStore.pickerHotkey` persistence + clearing
  + conflict detection).

## [0.7.1] — 2026-05-23

Polish on top of v0.7.0. Addresses the post-ship code-review findings.

### Fixed

- **Clipboard race on post-paste focus loss.** Both `translateAndSend`
  and `rewriteAndSend` now use the *delayed* `restoreClipboard(snapshot)`
  (700 ms) when the focus-guard fails *after* the paste, instead of the
  synchronous `pasteboard.restore`. A slow target app could otherwise
  read the restored snapshot before consuming the just-pasted text.
- **Rewrite hotkey gated by provider availability.** `applyHotKeys` now
  skips registering rewrite hotkeys when `SettingsStore.rewriteAvailable`
  is false (DeepL / Google Translate / LibreTranslate selected). Switching
  back to an LLM provider re-registers automatically — `observeBindingsOnce`
  now tracks `translationSource` + `directProvider` too. No more "press
  hotkey, get an error every time" when the provider can't rewrite.

### Build

- Bundle 0.7.1 (build 19).

### Tests

- App: **220 Swift / 49 suites** GREEN (unchanged from v0.7.0).

## [0.7.0] — 2026-05-23

**New feature: Contextual rewrite.** Bind a hotkey to a tone (Polite,
Professional, De-escalate, Friendly, Firm-but-polite, Concise, or a
free-text custom tone) and the app rewrites the current input line in
that tone — **same language**, intent preserved. Built for the moment
you typed something blunt or angry and need to soften it before
sending. Always shows a preview HUD before sending — never auto-paste.

### Added

- **`TranslationDirection.rewrite`** — a third direction alongside
  inbound/outbound. The `PromptBuilder.rewriteSystemPrompt` carries
  Vietnamese few-shot examples that (a) demonstrate the tone shift and
  (b) reframe the input as the user's own draft so the model doesn't
  refuse on profanity.
- **`RewriteBinding`** + **`RewriteTone`** (`RewriteModels.swift`) —
  6 preset tones + `.custom` (free-text). Per-binding optional
  override on the preset's built-in instruction.
- **`SettingsStore.rewriteBindings`** persisted under a new
  `translator.rewriteBindings` UserDefaults key (default `[]` — zero
  migration risk).
- **`TranslationWorkflow.rewriteAndSend`** — clones the
  `translateAndSend` capture/paste machinery but always opens the
  preview HUD and routes through the new rewrite prompt path.
- **`RewriteResultProcessor`** — strips code fences / leading labels /
  outer quotes from raw LLM output, and detects refusal/moralizing
  replies via first-person markers (anchored to the prefix so a
  legitimate rewrite containing "không thể" mid-sentence is not flagged).
- **Refusal handling** — one automatic retry with a stronger
  anti-refusal prompt; if the model still declines, the workflow throws
  `RewriteError.refused`, restores the clipboard, and shows an error.
  The user's original text is never overwritten by a refusal.
- **Settings UI** — a new "Contextual rewrite" section with
  `RewriteBindingRow` (tone picker + custom instruction editor +
  hotkey recorder + delete) and an inline warning when the active
  provider can't rewrite.

### Changed

- **`PromptBuilder.systemPrompt(for: job)`** routes between the
  translation system prompt and the rewrite system prompt. All five
  LLM providers (Gemini, OpenAI-compatible, Ollama, Gemini-CLI,
  Codex-CLI) updated; non-LLM providers (DeepL, Google Translate,
  LibreTranslate) gated out via `DirectProviderKind.supportsRewrite`
  and `SettingsStore.rewriteAvailable`.
- **`AppDelegate.applyHotKeys`** registers rewrite-binding hotkeys
  alongside outbound bindings; `observeBindingsOnce` now tracks
  `rewriteBindings` so changes re-register immediately.
- **`TranslationStyle.displayLabelOverride`** — optional label
  override so the HUD surfaces the tone name ("De-escalate rewrite")
  for `.rewrite` jobs instead of a language-derived label.

### Build

- Bundle 0.7.0 (build 18).

### Tests

- App: **218 Swift / 49 suites** GREEN (190 pre-existing + 28 new).
  Coverage: tone display, instructions, codable round-trips,
  `supportsRewrite`, settings persistence, `rewriteAvailable` gate,
  `systemPrompt(for:)` routing, rewrite user-prompt shape, few-shot
  presence, refusal detection (EN + VN + empty), anti-false-positive
  (rewrite containing "không thể"), label/fence/quote stripping.

## [0.6.3] — 2026-05-22

Fixes the Liquid Glass adoption. v0.6.1/v0.6.2 made the onboarding and
Settings windows translucent with `.ultraThinMaterial` — but that is the
*legacy* vibrancy material (the pre-Tahoe fallback), not Liquid Glass. On
macOS 26 those windows were rendering the old material, not glass.

### Fixed

- **Onboarding + Settings windows now use real Liquid Glass** — swapped the
  unconditional `.ultraThinMaterial` for `liquidGlassBackground(in:)`, which
  resolves to `.glassEffect()` on macOS 26 Tahoe and falls back to
  `.regularMaterial` only on macOS 14/15.
- **No more glass-on-glass** — the onboarding permission rows were glass
  cards sitting on what is now a glass window. Glass cannot sample other
  glass, so the rows are now plain `.quaternary` content cards.

### Changed

- Internal `View.panelBackground(in:)` helper renamed to
  `liquidGlassBackground(in:)` with documentation clarifying that
  `.material` is the fallback, not Liquid Glass.

### Note

- The app has always been built against the macOS 26.1 SDK, so standard
  controls, the window chrome, sheets and menus already adopt Liquid Glass
  automatically. This release only corrects the two custom window backings.

### Build

- Bundle 0.6.3 (build 17).

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.6.2] — 2026-05-22

Completes the Liquid Glass pass and serves as the first end-to-end
verification of the Sparkle auto-update path (v0.6.1 → v0.6.2).

### Changed

- **Settings window adopts Liquid Glass** — translucent window with the
  grouped `Form`'s opaque scroll backing hidden (`scrollContentBackground(.hidden)`)
  over an `ultraThinMaterial` layer, matching the onboarding window. The
  macOS 26 System Settings look.

### Build

- Bundle 0.6.2 (build 16).

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.6.1] — 2026-05-22

Hotfix — v0.6.0 crashed on launch. **Anyone on v0.6.0 must download
v0.6.1 manually** (the crash happens before Sparkle starts, so auto
update can't reach them). Every release after this updates silently.

### Fixed

- **Crash on launch (dyld: Library not loaded `@rpath/Sparkle.framework`)**
  — `swift build` only bakes rpaths for the `.build/` layout. Once the
  binary moved into `Contents/MacOS/` and Sparkle into
  `Contents/Frameworks/`, dyld had no rpath that resolved there.
  `package_app.sh` now adds `@executable_path/../Frameworks` to the
  binary's rpath list before signing.

### Changed

- **HUD + preview popups are now draggable and resizable** — drag from
  any non-control area to reposition; drag any edge to resize (works on
  the borderless panels via the `.resizable` style mask). The HUD keeps
  its position/size while a translation streams in.
- **Onboarding window adopts Liquid Glass** — translucent window with
  an `.ultraThinMaterial` backing; the Accessibility / Input Monitoring
  permission rows are now glass cards on macOS 26 Tahoe.

### Build

- Bundle 0.6.1 (build 15).

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.6.0] — 2026-05-20

OTA auto-updates! Sparkle 2 integrated — once users install v0.6.0 they
never have to manually download a DMG again. The app checks for updates
in the background daily, and a "Check for Updates…" menu item provides
an on-demand option.

### Added

- **Sparkle 2 auto-update framework** — embedded `Sparkle.framework`
  (XPC services, Updater.app, Autoupdate helper) inside the app bundle.
  Background scheduler ticks once every 86400s (24h); `SPUStandardUpdaterController`
  drives the standard "Update Available" dialog and install flow.
- **EdDSA-signed update feed** — `SUPublicEDKey` baked into `Info.plist`,
  private signing key in macOS Keychain. Every update zip carries an
  EdDSA signature generated by `sign_update`; Sparkle refuses any
  unsigned or tampered download.
- **GitHub Pages appcast** — `docs/appcast.xml` served at
  `https://hoangperry.github.io/hp-translator/appcast.xml`. Each new
  release appends an `<item>` with `enclosure url` pointing to the
  GitHub Release zip asset.
- **"Check for Updates…" menu item** — manual on-demand check from the
  status bar menu. Sparkle handles all UX (progress dialog,
  release notes preview, restart prompt).

### Changed

- **Release pipeline** — `scripts/package_dmg.sh` now produces both a
  signed/notarized DMG (for first install) and a notarized + stapled
  `.zip` (for Sparkle updates). The script prints a ready-to-paste
  `<item>` block for `docs/appcast.xml`.
- **Code-signing order** — `scripts/package_app.sh` signs Sparkle's
  XPC services + Updater.app + Autoupdate first, then the framework,
  then the app last. Required because hardened runtime + nested code.

### Build

- Bundle 0.6.0 (build 14).
- Sparkle 2.9.2 via SPM binary target.

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.5.1] — 2026-05-20

### Planned for M2.1 — quota + cache (target 2026-08)

- Token-based quota enforcement (3K Solo / 15K Pro per FR-QUOTA-001) with HUD upgrade CTA at limit.
- Per-user encrypted server cache (libsodium per-user-key derivation, FR-CACHE-001).
- Conversation memory (3-turn Solo / 5-turn Pro) — server keeps thread context for coherent multi-turn translations.
- Smart provider routing (Pro only, FR-ROUTE-005).
- Multi-device sync for glossaries + personas.
- BYOK mode for Pro users (API keys stay in macOS Keychain, never sent to our server).

> See [`../docs/PRD-saas-m2.md`](../docs/PRD-saas-m2.md) for full M2 specification and the adversarial review findings that shaped it.

## [0.5.1] — 2026-05-20

Liquid Glass (macOS 26 Tahoe) adoption for the HUD + Preview panels, plus
explicit dismissal controls so the result HUD no longer feels stuck on
screen. Display stability preserved — the panels never disappear from
focus changes alone.

### Added

- **Liquid Glass background** — HUD and Preview panels now use
  `.glassEffect(in:)` on macOS 26+, falling back to `.regularMaterial` on
  older systems. Corner radius bumped (12pt HUD, 14pt Preview) so the
  glass refracts the bezel cleanly; borders softened to 0.5pt at 60%
  opacity to let the glass do the visual work.
- **Close button on the result HUD** — `xmark.circle.fill` in the top
  trailing corner of the loading / result / error panels. Hierarchical
  symbol rendering, secondary tint, `.plain` button style; accessible
  via VoiceOver as "Dismiss".
- **Click-outside dismiss** — `NSEvent.addGlobalMonitorForEvents`
  registers a global mouse-down listener while the HUD is up. Any click
  outside the panel (in another app) hides it instantly. Esc was
  considered but rejected — a global Esc monitor would intercept the
  key in every other app while the HUD is visible.

### Changed

- **Stability over aggression** — the auto-hide timer (6s error, 8s
  result) remains the safety net. Combined with the X button and
  click-outside, every dismissal path is explicit; no automatic
  focus-loss dismissal that could surprise the user mid-read.

### Build

- Bundle 0.5.1 (build 13).

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.5.0] — 2026-05-20

SwiftUI App architecture: `@main App` with `MenuBarExtra` replaces the
manual `NSApplication.shared` + `NSStatusItem` setup. Swift 6 language
mode enabled across the whole package — the codebase was already
concurrency-correct, so no warnings to fix.

### Changed

- **MenuBarExtra refactor** — `main.swift` (top-level `NSApplication`
  setup + manual `AppDelegate` wiring) gone; replaced by
  `ContextualMacTranslatorApp.swift` with `@main App`, declarative
  `MenuBarExtra` scene, and `@NSApplicationDelegateAdaptor` keeping the
  existing `AppDelegate` alive for hotkeys, workflow, HUDs, and the
  Settings + Onboarding windows. Dead code (`buildStatusItem` and the
  `statusItem` property) removed from `AppDelegate`.
- **Swift 6 language mode** enabled on both the executable and test
  targets (`swiftSettings: [.swiftLanguageMode(.v6)]`). The codebase
  was already correctly annotated with `@MainActor`, `Sendable` value
  types, and `@Observable` reference types, so the upgrade was a
  zero-diff for source files.

### Build

- Bundle 0.5.0 (build 12).

### Tests

- App: **190 Swift / 45 suites** GREEN.

## [0.4.1] — 2026-05-20

UI modernization pass plus the missing app icon. Foundational bump to
macOS 14 to unlock the modern SwiftUI surface; `@Observable` migration
replaces the older `ObservableObject` + `@Published` pattern; SF Symbol
effects pepper the existing surfaces with the macOS-native feel.

Apple Developer ID signing + notarization (planned for 0.4.0) shipped
in v0.4.0 — moved out of the distribution-hardening backlog.

### Added

- **App icon** — hanko-stamp 訳 squircle (cream character, hanko-red
  background) matches the brand mark used across the marketing site.
  Finder, Dock, Spotlight, and Command-Tab all show the icon now.
  Generated by `scripts/build-icon.swift` (Hiragino Mincho ProN W6 → 10
  iconset PNGs → `iconutil`).
- **Symbol effects** — HUD result icon bounces on new translation,
  error icon pulses, permission checkmarks bounce on grant; all status
  icons use `.symbolRenderingMode(.hierarchical)` for the layered look.

### Changed

- **macOS minimum bumped to 14** (was 13). Unlocks `@Observable`,
  `.symbolEffect`, modern `onChange` two-parameter form, MenuBarExtra
  (used later), and the rest of the macOS-14 SwiftUI surface.
- **State management → `@Observable`** — all four observable classes
  (`SettingsStore`, `PermissionManager`, `PreviewHUDViewModel`,
  `SupabaseAuthViewModel`) now use the Observation macro instead of
  `ObservableObject` + `@Published`. `AppDelegate` binding observation
  switched from Combine `.sink` to `withObservationTracking` in a
  re-arming pattern; the Combine import is gone.
- **Onboarding polish** — bigger Continue button (`.borderedProminent`
  + `.controlSize(.large)`), hierarchical info icons.
- **Preview HUD** — edit pencil hierarchical + `.controlSize(.large)`;
  deprecated `onChange(of:perform:)` updated to the macOS-14 closure form.

### Tests

- App: **190 Swift / 45 suites** GREEN (unchanged from v0.4.0).

### Build

- Bundle 0.4.1 (build 11).

## [0.4.0] — 2026-05-19

First step onto the SaaS path: the app can now sign in to Contextual MT
Cloud. Self-hosted và custom-backend modes giữ nguyên hành vi.

### Added

- **Contextual MT Cloud sign-in (opt-in)** — Settings → Translation Source →
  "Contextual MT backend" thêm chế độ "Contextual MT Cloud · email sign-in"
  cạnh chế độ self-hosted token. Sign-in dùng Supabase email OTP (mã 6 số,
  không mật khẩu). (M2.1-a)
- **Device registration** — mỗi Mac sinh device identity và gửi `X-Device-*`
  headers theo request cloud để backend enforce giới hạn thiết bị theo
  plan. (M2.1-c)
- **Keigo-specialized style instruction** — outbound business Japanese dùng
  instruction tinh chỉnh riêng cho 敬語, output keigo ổn định hơn.
- **IT glossary starter pack** — preset thuật ngữ IT EN/VI → JP cho bridge
  engineer, sẵn sàng dán vào glossary.

### Changed

- **Settings window** dựng lại bằng grouped `Form` (`.formStyle(.grouped)`)
  — giao diện đúng chuẩn System Settings macOS.
- Viền HUD và preview panel chuyển sang màu adaptive `.separator` thay vì
  stroke trắng hardcode (sửa lỗi viền vô hình ở light mode).

### Notes

- Build này **ad-hoc signed**, chưa Developer ID signed/notarized. Việc ký
  Developer ID + notarization, migration bundle ID, và Sparkle auto-update
  vẫn nằm trong kế hoạch cho release sau.

### Tests

- App: **190 Swift / 45 suites** GREEN.

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

[Unreleased]: https://github.com/hoangperry/hp-translator/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.5.0
[0.4.1]: https://github.com/hoangperry/hp-translator/releases/tag/v0.4.1
[0.4.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.4.0
[0.3.1]: https://github.com/hoangperry/hp-translator/releases/tag/v0.3.1
[0.3.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.3.0
[0.2.0]: https://github.com/hoangperry/hp-translator/releases/tag/v0.2.0
[0.1.5]: https://github.com/hoangperry/hp-translator/releases/tag/v0.1.5
