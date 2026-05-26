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

## [1.0.0] — 2026-05-27

**First stable release.** v1.0.0 is a commitment to API + UX
stability, not a re-implementation. The bundle is byte-identical in
behaviour to v0.11.1 — same code path, same backend wire format, same
prompts, same hotkey UX. The 1.0.0 number marks the boundary where:

- The feature set covers every workflow the app was built for:
  inbound translate, outbound translate (per-persona), contextual
  rewrite (per-tone), tone picker, OCR capture, App Intents
  (Shortcuts.app + Spotlight + Siri), Prompt Engineer mode.
- The translation backend is dual-mode: bring-your-own-API direct
  providers (Gemini, OpenAI-compatible, Ollama, DeepL, Google
  Translate, LibreTranslate) and the SaaS-hosted Contextual MT Cloud
  with quota / device cap / per-user encrypted cache.
- The distribution pipeline is hardened end-to-end: Apple
  Developer-ID signed, Apple-notarized, stapled, AppleDouble-clean
  ZIP + DMG, Sparkle EdDSA auto-update, GitHub Pages workflow
  deploy for the appcast.
- The Mac app reliably round-trips its persistent state (UserDefaults
  + Keychain) across upgrades, including the v0.10.2 auto-recovery
  flow when macOS TCC resets Accessibility.
- 400 tests guard the contract.

### No behaviour changes vs v0.11.1

Just the version string + this entry. v0.11.0 → v0.11.1 → v1.0.0
upgrade is the cheapest in the app's history.

### What 1.0.0 means for the project

- Feature additions land as **minor** version bumps (1.1.0, 1.2.0, …).
- Bug fixes land as **patch** bumps (1.0.1, 1.0.2, …).
- The on-disk layout (UserDefaults keys, Keychain accounts, file
  names, signing identifiers) and the backend wire format
  (`direction` field values, dual-emit body shape, snake_case +
  camelCase parity) are now considered stable surface area; any
  breaking change earns a **major** bump (2.0.0).

### Risk-free upgrade

UserDefaults + Keychain layout unchanged from v0.11.1.

## [0.11.1] — 2026-05-27

**Rewrite pronoun-preservation hotfix.** User-reported bug: a draft
addressed with "em" was coming back as "anh/chị" (or vice versa) after
a rewrite, inverting the entire social relationship between speaker
and addressee. In Vietnamese this is a major correctness failure —
pronouns ARE the relationship, not decoration around it.

Root cause: the pronoun-preservation rule was a single buried line in
a bullet list AND one of the few-shot examples in the prompt itself
silently switched "tôi" to "em", actively teaching the model the
opposite of what the rule said. The Supabase server prompt didn't
mention Vietnamese pronouns at all.

### Fixed — Mac app `PromptBuilder.rewriteSystemPrompt`

- Pronoun-preservation rule promoted from a bullet to an **ABSOLUTE**
  top-level section with explicit per-pronoun guarantees ("em" stays
  "em", "tôi" stays "tôi", "mình" stays "mình", every addressing
  pronoun preserved verbatim).
- Few-shot example #2 fixed: input "tôi" → output now keeps "tôi"
  (was wrongly outputting "em").
- Few-shot example #3 fixed: input "tôi" → output now keeps "tôi"
  (was wrongly outputting "em").
- New few-shot example #4 demonstrates "em → anh" pronoun fidelity
  across a friendly tone shift.
- Other-language formality markers ("tu"/"vous", "tú"/"usted",
  "你"/"您", etc.) added to the rule so the fix isn't VN-only.

### Fixed — Supabase `REWRITE_SYSTEM_PROMPT`

- Server-side rewrite prompt was much thinner than the Mac side and
  had no pronoun rule whatsoever. Now mirrors PromptBuilder's
  rewriteSystemPrompt verbatim so SaaS users get the same
  pronoun-preserving quality as direct-API users.
- Already deployed via `supabase functions deploy translate`.

### Tests

- `rewriteSystemPromptHasFewShot` updated to pin the new ABSOLUTE
  pronoun rule string + per-pronoun guarantees so a future prompt
  refactor cannot quietly drop the protection. 400 tests pass.

### Risk-free upgrade

UserDefaults + Keychain layout unchanged from v0.11.0.

## [0.11.0] — 2026-05-27

**Prompt Engineer mode.** Type a minimal Vietnamese keyword sketch of
a coding task, press a hotkey, and the app pastes back a complete,
well-structured English prompt for Claude Code, Codex, ChatGPT, or
Claude Desktop. The same hotkey machinery as translate/rewrite, with
a dedicated server prompt + temperature tuned for expansion.

Closes the user-reported gap documented in
`/recipes/prompt-expander` as a Path A workaround — Path B (this
release) makes the feature first-class.

### Added — `TranslationDirection.expand` + `PromptBinding`

- New `TranslationDirection.expand` enum case alongside `.inbound`,
  `.outbound`, `.rewrite`.
- New `PromptBinding` data type: `id`, `name`, `hotkey`,
  `targetLanguage` (default `"en"`), `styleInstruction` (defaults to
  shared `PromptExpansion.defaultStyleInstruction` template when
  blank — same meta-prompt documented on the marketing recipe page).
- `SettingsStore.promptBindings: [PromptBinding]` persisted under
  `translator.promptBindings`. Conflict-detection sweep
  (`bindingLabel(usingHotkey:)`) includes prompt bindings.

### Added — Settings → Prompt Engineer section

- New section parallel to "Contextual rewrite" with per-binding rows:
  rename, pick target language, optional custom expansion guidelines
  (default template hidden by default; opens via "Custom expansion
  guidelines" toggle), hotkey recorder, delete.
- `addPromptBinding()` cycles through `⌥P`, `⌥⇧P`, `⌥⌘P` skipping
  hotkeys already used by inbound / outbound / rewrite / other prompt
  bindings.
- Gated on `rewriteAvailable` — shows an orange notice when the
  active translation source cannot expand (DeepL, Google Translate,
  LibreTranslate).

### Added — `TranslationWorkflow.expandAndSend(binding:)`

- Capture selected text → build `TranslationJob` with `direction =
  .expand` + the binding's effective style instruction → translate via
  the active provider → always preview via PreviewHUD (expanded
  prompts are N× longer than the input; user must skim before paste)
  → paste on confirm.
- Reuses the focus-guard + clipboard-snapshot infrastructure from
  `translateAndSend` and `rewriteAndSend`.
- `AppDelegate.applyHotKeys()` registers all `settings.promptBindings`
  on the same gate as rewrite bindings.

### Added — Direct API parity

- `PromptBuilder.expandSystemPrompt` mirrors the Supabase
  `EXPAND_SYSTEM_PROMPT` so direct-API providers (Gemini direct,
  OpenAI direct, etc.) produce the same expansion quality as the SaaS
  backend without any backend round-trip.
- `PromptBuilder.userPrompt(for:)` switch grows an `.expand` case that
  drops Source language and adds "Target language for the expanded
  prompt:" framing.

### Server side (already deployed, see translator-platform commit `d772dcc`)

- Supabase `translate` Edge Function accepts `direction: "expand"`,
  swaps to `EXPAND_SYSTEM_PROMPT`, bumps temperature 0.3 → 0.6, and
  drops the Source language line from the user prompt.
- Cache key already included `direction` from v0.10.6, so expand /
  rewrite / translate of the same input get separate cache slots.

### Tests

- New `PromptBindingTests` suite (7 tests): Codable roundtrip,
  default-style-instruction fallback (empty / whitespace),
  custom-instruction precedence, `style()` direction pinning,
  SettingsStore persistence, hotkey-conflict detection.
- New `ExpandDirectionWireFormatTests` suite (2 tests): pins
  `TranslationDirection.expand.rawValue == "expand"` and the JSON
  encoding shape.
- Extended `BackendStreamingTests` with an end-to-end "direction=expand
  reaches the wire body" test so a regression in the dual-emit
  encoder cannot silently downgrade Prompt Engineer jobs.
- 400 tests pass (was 390, +10).

### Risk-free upgrade

UserDefaults adds one new key (`translator.promptBindings`) that
defaults to an empty array on existing installs. Users opt in by
adding a binding in Settings → Prompt Engineer.

## [0.10.6] — 2026-05-27

**Rewrite works on SaaS backend.** User-reported bug: pressing a tone
rewrite hotkey (Polite / Professional / Friendly etc.) did nothing
when the app was configured to use Contextual MT Cloud or a self-hosted
backend. The hotkey registration was silently skipped because the
historical `rewriteAvailable` gate hardcoded "only direct-API providers
can rewrite".

### Fixed — `rewriteAvailable` unblocks backend modes

- `SettingsStore.rewriteAvailable` now returns `true` for both
  `customBackend` and `firstPartyBackend` translation sources. Direct
  API providers stay gated on each provider's individual
  `supportsRewrite` flag.

### Added — Backend rewrite mode (server-side, already deployed)

- The Supabase `translate` Edge Function now accepts a
  `direction: "translate" | "rewrite"` field. When set to `"rewrite"`,
  the Gemini provider swaps to a same-language tone-rewrite system
  prompt and the user prompt drops Source/Target language lines that
  would otherwise confuse the model into translating instead of
  adjusting tone.
- Any other `direction` value (including missing) is treated as a
  regular translate — backward-compatible with v0.10.0–v0.10.5
  clients still in the wild.
- Cache key now includes `direction` so a translate-of-X never
  returns a previously-cached rewrite-of-X (or vice versa).
- The Mac app's `BackendRequestBody.encode(to:)` already emits a
  `direction` field for every request (raw value from
  `TranslationDirection`), so no client wire change beyond unblocking
  the gate.

### Tests

- `RewriteModelsTests.rewriteAvailability` updated to assert the new
  contract: backend modes return true; direct API stays per-provider.
- `PermissionManagerTests`: refactored the v0.10.4 auto-open Settings
  tests to drive the decision synchronously via a new
  `checkAutoOpenSettings()` method instead of racing the cooperative
  scheduler. The production code still schedules the grace task; the
  tests just exercise its decision body deterministically.
- 390 tests pass (was 390; no count change).

### Risk-free upgrade

UserDefaults + Keychain layout unchanged from v0.10.5. Older Mac app
builds on the SaaS backend will continue to get translate-only
behaviour (rewrite hotkeys were never registered, so they were never
calling into the backend in rewrite mode anyway).

## [0.10.5] — 2026-05-27

**Window chrome hotfix.** Three app windows (Onboarding, Settings,
What's New) were configured with
`titlebarAppearsTransparent = true` + `backgroundColor = .clear` +
`isOpaque = false` from an earlier macOS 26 "Liquid Glass" experiment.
On real macOS the combination renders the window title text directly
onto the desktop wallpaper with zero contrast — the user-visible
symptom was an overlapping unreadable title bar.

### Fixed

- **OnboardingWindowController**, **SettingsWindowController**,
  **WhatsNewWindowController** — reverted the transparent-titlebar /
  clear-background settings. Standard opaque titlebar restored on all
  three windows. The SwiftUI content's `liquidGlassBackground`
  modifier still applies its material to the content area; only the
  titlebar chrome changes.

### Tests

- Bumped two PermissionManager test sleeps 2s → 3s to absorb scheduler
  jitter and stop intermittent flakes on the auto-open-Settings
  contract added in v0.10.4. 390 tests pass.

### Risk-free upgrade

UserDefaults + Keychain layout unchanged from v0.10.4.

## [0.10.4] — 2026-05-27

**Permission UX cleanup.** Drops Input Monitoring from the onboarding
and Settings surface entirely — the app never actually needed it, and
the Request button could not recover after the first denial (macOS
silently suppresses the prompt forever once dismissed). Plus a small
quality-of-life improvement on the remaining Accessibility flow: if
the system prompt doesn't appear (because the user previously denied),
Settings opens automatically to the Accessibility pane after a short
grace period so the user is never left tapping an unresponsive button.

### Removed — Input Monitoring permission

- Carbon `RegisterEventHotKey` (the global hotkey path) and `CGEvent`
  posting (the paste path) both run on Accessibility alone. Asking
  for a permission we never call into was pure friction.
- `OnboardingView` and `SettingsWindowController.permissionsSection`
  drop the Input Monitoring row. `PermissionManager.inputMonitoringGranted`
  and `requestInputMonitoringIfNeeded` are deleted. If a future
  feature genuinely needs CGEvent tap, the probe + request closure
  pattern is easy to add back fresh.

### Improved — Accessibility request with auto-Settings fallback

- After `requestAccessibilityIfNeeded()` fires the system prompt, a
  1.5-second grace task re-checks the live grant. If the prompt was
  silently suppressed (the user denied in a prior session) and the
  grant did not arrive, `NSWorkspace` opens System Settings to the
  Accessibility pane automatically. No more "I clicked Request and
  nothing happened" dead end.

### Tests

- `PermissionManagerTests` updates: drops the 2 Input Monitoring
  assertions, adds 2 new tests pinning the auto-open Settings contract
  (fires when grant misses the grace window; skips when grant arrives
  in time). 388 → 390 total tests pass.

### Risk-free upgrade

UserDefaults + Keychain layout unchanged from v0.10.3.

## [0.10.3] — 2026-05-26

**Distribution hotfix: AppleDouble metadata files corrupted Gatekeeper
acceptance.** v0.10.0, v0.10.1, and v0.10.2 all shipped with hidden
`._*` AppleDouble metadata files inside the embedded
`Sparkle.framework` (introduced by SwiftPM's xcframework extraction
on macOS). The files were invisible to `codesign --sign`, so the
build succeeded; but post-extraction
`codesign --verify --deep --strict` treated them as foreign content
("file added") and reported the bundle as having a *"sealed resource
is missing or invalid"*. Gatekeeper refused to launch the app on the
user's machine, and Sparkle's `Installer.xpc` failed verification
mid-update — surfacing as "app chưa sign" when users tried to upgrade.

v0.10.3 carries no code changes — it is purely the v0.10.2 codebase
re-packaged with the build pipeline fixed.

### Fixed — build pipeline strips AppleDouble before signing

- `scripts/package_app.sh` now runs `find … -name "._*" -delete` and
  `dot_clean -m` against the bundle BEFORE the codesign chain starts
  AND once more after codesign completes (defense in depth). The
  final `codesign --verify --deep --strict` step is now part of the
  build itself — if a future tool combination re-introduces the
  problem the build will fail loudly instead of silently shipping a
  broken release.
- Verified end-to-end: extracting the v0.10.3 distribution ZIP yields
  a bundle that passes `codesign --verify --deep --strict` AND
  `spctl --assess --type execute` reports
  `accepted source=Notarized Developer ID`.

### How to upgrade

If Sparkle's Check for Updates fails to install v0.10.3 (it might if
the already-installed v0.10.0 → v0.10.2 update was already aborted
mid-flight), **download the v0.10.3 ZIP manually** from the GitHub
release page and drag the `.app` into `/Applications` replacing the
old copy. Future Sparkle updates from v0.10.3 onwards will install
cleanly because the v0.10.3 bundle no longer contains the offending
metadata files.

## [0.10.2] — 2026-05-26

**Permission UX & TCC stability.** A user-reported pain point: every
Sparkle upgrade felt like macOS was clearing the app's Accessibility
grant — translate hotkeys went silent until they manually re-granted,
and there was no in-app surface telling them what happened. v0.10.2
adds an auto-recovery onboarding panel that pops automatically when
the launch-time grant check finds a true→false transition, plus a
defensive codesign hardening so the designated requirement TCC keys
on cannot drift between releases.

### Added — Auto-recovery onboarding

- **Permission-loss detection on launch** — `AppDelegate` reads the
  persisted `lastKnownAccessibilityGranted` flag BEFORE calling
  `permissionManager.refresh()`, so the true→false transition that
  signals a TCC reset is detectable. When detected, the onboarding
  window pops in **`.permissionRecovery` mode** with copy that
  acknowledges the user already did this once.
- **`OnboardingMode` enum** (`.firstRun` / `.permissionRecovery`)
  threads through `OnboardingWindowController` and `OnboardingView`
  so the title and intro text adapt to the situation. Recovery mode
  reads: *"Welcome back. macOS cleared the app's Accessibility grant
  after the recent update — translate hotkeys are silent until you
  re-grant."*
- **Hotkey registration still runs** in recovery mode so any grants
  that survived (e.g. Input Monitoring) keep working — the onboarding
  pops on top so the issue cannot be missed.

### Internal — `PermissionManager` testability

- Constructor accepts injected `accessibilityProbe` /
  `inputMonitoringProbe` / `requestAccessibilityAction` /
  `requestInputMonitoringAction` closures so unit tests can exercise
  the grant-sync wiring without touching the real TCC database.
- `refresh()` writes the live grant back to
  `SettingsStore.lastKnownAccessibilityGranted` (guarded by `didSet`
  so the 1-second OnboardingView polling loop does not spam
  UserDefaults).
- `refreshLater()` post-request sleep bumped 1s → 2s — gives the TCC
  database room to settle after the user clicks "Allow" in the system
  prompt (the OnboardingView polling loop runs in parallel as
  belt-and-braces).

### Internal — Codesign stability hardening

- `scripts/package_app.sh` now passes
  `--identifier "app.lookerlab.translator"` explicitly to the main-app
  `codesign` call instead of letting it infer from
  `CFBundleIdentifier`. The value baked into the signature is now
  byte-stable across releases; v0.10.0 and v0.10.1 already had
  identical designated requirements (verified post-ship) but explicit
  is defensive against tool-version drift.

### Tests

- New `PermissionManagerTests` suite (6 tests) covers grant-sync
  behavior, init non-mutation guarantee, request-action firing, and
  nil-settings path.
- New `LaunchRecoveryDecisionTreeTests` suite (5 tests) pins the
  3-input decision tree used by AppDelegate (fresh install / steady
  state / revoked / never-granted / lost-then-regranted).
- Full suite stays GREEN at 388 tests (377 → 388; +11 new).

### Risk-free upgrade

UserDefaults adds one new key (`translator.lastKnownAccessibilityGranted`)
that defaults to `false` on existing installs — so the recovery
flow won't fire spuriously on the v0.10.1 → v0.10.2 upgrade itself.
First refresh writes the current live state forward; from v0.10.3
onwards the recovery signal is armed.

## [0.10.1] — 2026-05-26

**SaaS backend wire-format hotfix.** v0.10.0 shipped right as the
production SaaS Edge Function went live, and the request body the Mac
app sends turned out to be camelCase-only while the Supabase
`translate` function validates snake_case field names (`target_language`
is a hard requirement). Translates against `app.contextmt.dev` failed
with HTTP 400 immediately. The Mac app also assumed every backend
implements SSE on `/translate/stream`; Supabase does not, so even after
the 400 cleared the stream loop never saw a `data:`-prefixed frame and
threw "The backend response did not include a translation."

### Fixed — backend wire-format compatibility

- **`BackendRequestBody` dual-emit** — every routing field now encodes
  under both camelCase (legacy self-hosted FastAPI in
  `translator-server/server.py`) and snake_case (SaaS Supabase Edge
  Function). One payload works against both backends; each server
  ignores the unknown duplicate key. Pinned by a new
  `BackendStreamingTests` contract test so a future refactor cannot
  silently re-break one backend.
- **Streaming non-SSE fallback** — `BackendProvider.streamSSE` now
  sniffs the response `Content-Type`; if it is not
  `text/event-stream` (Supabase always returns
  `application/json` on `/translate/stream`), the body is drained and
  decoded as a one-shot `TranslationResult` and emitted as a single
  `.done(...)` update. Self-hosted SSE keeps its real streaming UX.

### Tests

- Full suite stays GREEN at 377 tests (376 → 377; +1 fallback test).
- Removed a stale `"0.10.0"` entry from
  `WhatsNewHighlightsTests.unknownVersionReturnsNil` — v0.10.0
  released its own highlight set so the value moved out of the
  catch-all bucket.

### Risk-free upgrade

UserDefaults + Keychain layout byte-identical to v0.10.0. Existing
settings, hotkey bindings, register card, and glossary entries all
round-trip clean.

## [0.10.0] — 2026-05-25

**Cultural Precision & Privacy.** The major v0.10.0 minor: three new
sub-features anchored on "Apple Intelligence can't do per-locale
precision". Pin your Vietnamese register, see the privacy class of
every translation, and replace the free-text glossary blob with typed
entries the LLM follows exactly. Storage layout byte-identical to
v0.9.x; existing settings, hotkeys, bindings, and the glossary blob
round-trip clean.

### Added — VN Social Register Card (anchor)

- **`RegisterCard`** value type with 3 axes (Dialect: Bắc/Nam;
  Kinship: anh/chị/em/cháu/bạn; Formality: formal/neutral/casual) +
  optional 80-character roleHint. `nil` = disabled (default; v0.9.x
  behaviour preserved). When set, every rewrite + outbound translate
  prepends a `[Register]` block to the per-binding tone instruction.
- **Settings → Contextual Rewrite → Vietnamese register card**
  panel with 3 Picker dropdowns, a roleHint TextField, a Reset
  button, and a live composed-prompt preview.
- Composition is **prepend** (Q1 from `docs/v0.10.0/define.md` §8):
  existing per-binding `customStyleInstruction` flows through
  unchanged below the `[Tone]` tag.

### Added — Local-LLM Privacy mode

- **`ProviderPrivacyClass` enum** (`.local` / `.cloud` / `.hosted`)
  as a new protocol member on `TranslationProvider`. All 10
  providers classify explicitly: Ollama = `.local`, BackendProvider
  = `.hosted`, everything else = `.cloud`.
- **PreviewHUD Privacy badge** — every translation surfaces the
  provider's class (🛡 Local / ☁ Cloud / 🏢 Hosted) with `.help()`
  tooltip showing the full provider name. Stamped eagerly into
  `TranslationStyle` at workflow construction so SwiftUI render
  never reaches back into `providerFactory()`.
- **Settings → Privacy** section with active-provider ribbon +
  Vietnamese headline ("🛡 Local only — không gửi dữ liệu khách ra
  nước ngoài" when Ollama) + collapsed Ollama onboarding card with
  download link, two curated `ollama pull` commands (each with a
  Copy button), Browse-more-models link, and a one-click "Test
  Ollama connection" button (2s timeout, exact-name model match
  via `/api/tags` JSON parse).

### Added — Glossary v2-Lite (typed entries)

- **`GlossaryEntry`** Codable value type with 3 kinds:
  `.dontTranslate(term:)`, `.alias(from:to:)`, `.alwaysTranslate(term:to:)`.
  Tagged-enum Codable shape; **forward-compatible partial recovery** —
  unknown KindTag from a future v0.10.x is silently dropped at the
  element level via `GlossaryEntry.decodeArray(from:)` (review H3 fix).
- **`GlossaryComposer`** pure function composes typed entries + the
  legacy free-text blob into the single `TranslationJob.glossary`
  string the LLM sees. `dontTranslate` grouped under one bullet;
  `alias` + `alwaysTranslate` render one-per-line directional pairs.
  50-entry render cap.
- **Settings → Glossary** editor — Add-menu for the 3 kinds, type
  pill (tinted per kind), 1-or-2 TextFields per row, delete button,
  drag-to-reorder via `.onMove`. Legacy free-text TextEditor moved
  to a collapsed DisclosureGroup below.

### Compatibility

- Every v0.9.x persisted state round-trips clean: `RewriteBinding`,
  `HotkeyConfig`, `TranslationStyle`, `SaaSConfig`, legacy glossary
  string blob — all unchanged in storage. `TranslationStyle` gains
  3 default-safe fields (`registerCard: nil`, `privacyClass: nil`,
  `providerDisplayName: ""`).
- Sparkle OTA from v0.6.1+ auto-updates with no manual user action.

### What's-New on first launch

- Pops once for v0.10.0 upgrades with 3 highlight cards (Register
  Card / Privacy badge / Glossary v2). Doesn't steal focus.

### Build

- Bundle 0.10.0 (build 29).

### Tests

- App: **375 Swift / 79 suites** GREEN (+56 from 319 in v0.9.2):
  +19 RegisterCard, +3 PromptBuilder integration, +15 GlossaryEntry
  (incl. partial-recovery), +9 GlossaryComposer, +10
  ProviderPrivacyClass + TranslationStyle stamping.

### Deliver-phase review

- 0 CRITICAL / 3 HIGH / 4 MED / 2 LOW from independent code-review
  agent before tag. All 3 HIGH + 3 MED fixed inline (see commit
  `285f519`). 2 LOW + M4 (`stamp()` helper duplication) tracked as
  v0.10.1 carry-over.

## [0.9.2] — 2026-05-25

**Second refactor patch.** No new user-facing features; clears the
remaining HIGH + MED + LOW items from the v0.9.0 deliver-phase review
that v0.9.1 deferred. **Risk-free upgrade** — 319/69 tests stay GREEN
with the same test bodies; storage layout (UserDefaults + Keychain)
is byte-identical so every v0.9.x setting round-trips clean.

### Changed (refactor)

- **`SettingsStore` god-object trimmed (W1, HIGH)** — extracted the
  Supabase project URL + anon key + the 4 SaaS factory helpers
  (`authConfig` / `makeSessionStore` / `translateEndpoint` /
  `deviceIdentity`) into a new `Auth/SaaSConfig.swift`. SettingsStore
  drops from 593 → 538 LOC and from owning 6 Supabase concepts down
  to 1 (just a `saaSConfig` reference). Future SaaS-only changes
  now live in one file. Call sites migrated from `settings.supabaseURL`
  → `settings.saaSConfig.supabaseURL`, etc. (4 production + 2 test
  files).
- **`ScreenCaptureService` protocol shape aligned to `OCREngine`
  (MED-4)** — dropped the unnecessary `@MainActor` + `AnyObject`
  requirements from the protocol. Production impl is still
  `@MainActor` where it needs to be; stubs in tests can now be plain
  structs. Cleans up the asymmetry that gave HIGH-2 its root cause
  (HIGH-2 itself was already fixed in v0.9.0 via `Task.detached`).

### Fixed

- **Picker + capture hotkey recorder sheets share one helper now
  (LOW-2)** — centralised the synthetic `Binding<HotkeyConfig>`
  pattern into `optionalHotkeyBinding(_:fallback:)` on `SettingsView`.
  Pre-allocated `HotkeyConfig.defaultPicker` / `.defaultCapture`
  constants replace the per-render allocations the v0.9.0 review
  flagged. New picker-style hotkeys can now ride the helper instead
  of re-inlining the boilerplate.

### Deferred to v0.9.3+

- `TranslationWorkflowClipboardRestoreTest` — still needs
  `HUDPresenting` + `Pasteboarding` protocol extractions (its own
  refactor commit).
- Hardcoded Supabase anon-key + URL move to build-time `.xcconfig`
  (now that SaaSConfig is its own file, this becomes a one-line
  init-default change + a CI secret wiring step).
- macOS What's-New highlights catalogue for future versions
  (mechanism in place since v0.9.0; just needs the next minor's
  copy).

### Build

- Bundle 0.9.2 (build 28).

### Tests

- App: **319 Swift / 69 suites** GREEN (unchanged from v0.9.1).

## [0.9.1] — 2026-05-25

**Refactor + reliability patch.** No new user-facing features; reduces
two pieces of structural debt the v0.9.0 deliver-phase review flagged
before they bite, and adds 13 high-leverage tests covering paths that
silently failed before.

### Changed (refactor)

- **`TranslationWorkflow.swift` split (876 → 630 LOC)** — back under the
  800-line file-size guideline before any new workflow path lands.
  Behaviour byte-identical; the 306-test contract stays GREEN with zero
  test modifications.
  - **New `CaptureOrchestrator.swift`** (115 LOC) — owns the v0.9.0
    OCR-translate flow end-to-end. `captureAndTranslate()` is now a
    1-line delegate.
  - **New `RewriteService.swift`** (230 LOC) — owns the rewrite
    primitives (`rewrite` + `rewriteVariants` + the 3 headless methods
    + the static `style(forPickerEntry:)` helper that was previously
    duplicated in TranslationWorkflow). All call sites updated.

### Fixed

- **No more silent Japanese fallback** in the status-bar Send-Keigo /
  Send-Casual menu items. A VN-primary user with no formal/casual
  outbound binding used to get a hardcoded `.japaneseBusiness` /
  `.japaneseCasual` translation when they triggered those items.
  v0.9.1 surfaces an actionable error toast pointing to Settings
  instead.

### Added (tests)

- **`BackendStreamingURLTests`** (9 tests) — pin every branch of
  `BackendProvider.streamingURL(for:)`, the 4-case path rewriter the
  review flagged as silent-fallback-prone. Covers the standard
  `/translate` endpoint, bare root, trailing-slash, versioned paths,
  query-string survival, non-default port survival, and the catch-all
  edge case. Required marking `streamingURL` `nonisolated static`
  (honest — it has no actor state).
- **`WhatsNewHighlightsTests`** (4 tests) — pin the per-version
  highlight catalogue introduced by v0.9.0 MED-2. Verifies v0.9.0
  returns its 3 highlights, every other version (including future
  v0.10.0) falls into the `nil` catch-all so AppDelegate marks the
  version seen without popping a stale window, and the
  lookup-vs-static-catalogue paths stay consistent.

### Deferred to v0.9.2

- `TranslationWorkflowClipboardRestoreTest` — needs `HUDPresenting` +
  `Pasteboarding` protocol extraction so tests don't clobber the
  developer's real clipboard. Worth its own refactor commit.
- W1 from the review (`SettingsStore` god-object — extract `SaaSConfig`).
- MED-4 (`OCREngine` protocol isolation alignment with `ScreenCaptureService`).
- LOW-1, LOW-2 (style nits — `ScreenCaptureService` `@MainActor` strength,
  captureHotkey synthetic-Binding consistency).

### Build

- Bundle 0.9.1 (build 27).

### Tests

- App: **319 Swift / 69 suites** GREEN (+13 from 306).

## [0.9.0] — 2026-05-25

**Input Surface Expansion.** Two new ways to invoke the translator: from
anywhere on the system via Shortcuts.app / Spotlight / Siri (App
Intents), and from any pixel on screen via an OCR capture hotkey.

### Added — App Intents (Shortcuts.app integration)

- **Three new App Intents** discoverable in Shortcuts.app under
  "Contextual Mac Translator":
  - **Translate Text** — translate any text in a Shortcut step;
    target language optional (defaults to your primary language).
  - **Rewrite with Tone** — pick from the 7 preset tones (Polite,
    Professional, Friendly, Firm-but-polite, De-escalate, Concise,
    Custom). Result usable in subsequent Shortcut steps.
  - **Rewrite with Instruction** — free-text instruction
    ("warmer reply", "shorter under 2 sentences"), mirrors the
    in-app picker's freetext row from v0.8.3.
- **Spotlight + Siri trigger phrases** for each action, prefixed with
  "Contextual" so they don't collide with Apple Translate's system Siri
  commands.
- **TranslationIntentRouter** lets the system construct intents
  outside the app's DI graph; the AppDelegate installs the running
  workflow at launch so intents resolve cleanly even if fired before
  Settings load.
- Expressive tones (Chửi thề) deliberately excluded from the
  Shortcuts enum — Shortcuts has no per-user gating mechanism; users
  who want expressive rewrites can use the Instruction intent.

### Added — OCR-from-screen translate

- **New global hotkey** (Settings → Capture) — press, drag a region
  with the system crosshair (same Cmd+Shift+4 UX), and the app reads
  the text on-device via Vision, auto-detects source language via
  NaturalLanguage, translates into your primary language, and shows
  the result in a copy-mode PreviewHUD.
- **Language coverage**: Vietnamese, English, Simplified Chinese,
  Japanese, Korean — picked for the VN-power-user / VN-seller audience
  identified in docs/v0.9.0/discovery.md (1688 / Aliwangwang /
  Messenger / Discord workflows where browser translation breaks down).
- **Privacy posture**: OCR runs entirely on-device. Only the
  recognised text travels to your active translation provider — same
  as every other translate flow. Screen pixels never leave the device.
- **Onboarding card** in Settings → Capture with a one-click link to
  System Settings → Privacy & Security → Screen Recording for users
  who denied the TCC prompt.
- **PreviewHUD copy-mode**: the Send button becomes "Copy" for OCR
  results; the workflow writes the (possibly user-edited) translation
  to the pasteboard. No keystroke simulation, no source-app focus
  monitoring.

### Added — What's-New window

- One-shot upgrade window pops the first time you launch a new
  minor/major version. Highlights the new features and points to where
  to set things up. Dismissible; the seen-version is persisted so it
  doesn't replay.

### Changed

- `SettingsWindowController.swift` (was 844 LOC, over the 800-line
  guideline) — extracted `OutboundBindingRow` and `RewriteBindingRow`
  into `SettingsBindingRows.swift`. Pure file move, no behaviour change.
- `TranslationWorkflow` gains three headless entries
  (`performTranslationHeadless` + `performRewriteHeadless` × 2) that
  bypass HUD/clipboard/keystrokes. Existing flows unchanged.
- `PreviewPresenter` protocol gains a `presentForCopy(...)` entry
  with a default extension routing to `presentPreview(...)` — existing
  stubs / tests keep working without modification.
- `Info.plist` gains `NSScreenCaptureUsageDescription` (cited only
  when the system TCC prompt fires).

### Compatibility

- All v0.8.5 persisted state round-trips clean (`RewriteBinding` /
  `HotkeyConfig` / `TranslationStyle` Codable contracts unchanged).
- Sparkle OTA from v0.6.1+ auto-updates to v0.9.0 with no manual user
  intervention.

### Build

- Bundle 0.9.0 (build 26).

### Tests

- App: **306 Swift / 67 suites** GREEN (+36 from 270):
  - +15 App Intents tests (mock-driven, error-mapping coverage)
  - +16 OCR postprocessor tests (NFC diacritic preservation, paragraph
    join, control-char strip — the core diacritic-safety guarantee)
  - +6 NaturalLanguageDetector tests (VN / EN / zh-Hans detection,
    confidence-threshold gate, BCP47 mapping)
  - +3 VisionOCREngine contract tests + 1 OCRResult equality test
- Vision integration round-trip with programmatically-rendered text
  was attempted and discarded as flaky (Vision is trained on natural
  screenshots, not freshly-rasterised glyphs). Real-screenshot OCR
  quality verified via manual smoke during deliver phase.

## [0.8.5] — 2026-05-24

**Multi-variant rewrite (3 drafts in one round-trip).** Opt-in setting
that asks the LLM for three different rewrites in a single call, then
lets the user page through them in the preview HUD before sending. One
network round-trip, ~1.5–2× tokens, dramatically wider creative range.

### Added

- **`SettingsStore.multiVariantRewriteEnabled: Bool`** *(default OFF)* —
  toggle under Settings → Contextual rewrite. When ON, every rewrite
  invocation (binding hotkey OR tone picker) generates 3 drafts.
- **`TranslationStyle.variantCount: Int`** + `.withVariantCount(_:)`
  helper. Clamped to `[1, 5]`. `1` keeps the legacy single-draft path
  byte-identical; `>1` flips PromptBuilder into multi-variant mode.
- **Multi-variant prompt** — `PromptBuilder.rewriteUserPrompt` branches
  on `variantCount > 1` and asks the model to emit N drafts separated
  by a `---VARIANT---` sentinel on its own line.
- **`RewriteResultProcessor.splitVariants(_:)`** — pure parser: splits
  on sentinel, falls back to numbered-list heuristics (`1.` / `1)` /
  `**1.**` / `Variant 1:`) when the model ignored the sentinel, drops
  empty/refusal chunks, dedupes while preserving order.
- **Multi-variant Preview HUD** — pager chip ("2 / 3") with ← / →
  buttons, ⌘1–5 quick-select, footer hint, edits captured per variant
  (paging back-and-forth preserves each draft's tweaks). Single-variant
  flow renders unchanged.
- **`PreviewPresenter.presentVariants(...)`** — protocol-level entry
  point. Default extension routes to `presentPreview(...)` for stubs
  that only know single-variant, so existing tests stay green.

### Changed

- `TranslationWorkflow.rewriteAndSend` + `.rewriteWithPickerAndSend`
  now branch on `multiVariantRewriteEnabledProvider()` and call
  `performRewriteVariants` → `presentVariants(...)`. HUD label switches
  to "Generating 3 drafts..." when multi-variant is active.
- `performRewriteVariants` (new) is variant-aware. When the model
  ignores the multi-variant prompt and parsing yields `< 2` drafts,
  it falls back to the existing `performRewrite` (with anti-refusal
  retry chain) so users still get a result.

### Compatibility

- `TranslationStyle.variantCount` default = `1`. Every existing call
  site stays single-draft — no behaviour change for users who don't
  flip the toggle.
- `PreviewHUDViewModel.init(original:translated:persona:)` is now a
  convenience init that delegates to the new variants-list designated
  init. No call-site change.

### Build

- Bundle 0.8.5 (build 25).

### Tests

- App: **270 Swift / 56 suites** GREEN (+13 net): 5 multi-variant HUD
  view-model (nav wrap, per-variant edit persistence, single-variant
  no-op, init back-compat), 5 variant-splitter (sentinel,
  numbered-list fallback, dedupe, refusal-drop, single-chunk),
  3 `TranslationStyle` variant (back-compat, clamp, `withVariantCount`).

## [0.8.4] — 2026-05-24

**Pre-warmed picker + per-binding "In picker" + VoiceOver polish.** Three
small upgrades that make the tone picker feel native: the panel is
constructed at launch (first press is instant), each saved rewrite
binding can optionally appear as its own picker row, and the picker
itself is properly labelled for VoiceOver.

### Added

- **`RewriteBinding.showInPicker: Bool`** *(default `true`)* — surface
  the binding as a row in the tone picker popup so users can pick saved
  instructions without remembering their hotkey. Each binding row in
  Settings now has an "In picker" checkbox.
- **`PickerEntry.binding(RewriteBinding)`** — third entry flavour
  alongside `.freetext` and `.preset`. The view-model surfaces filtered
  bindings below filtered presets; the workflow uses the binding's
  `effectiveInstruction` + `displayName`, so a picker-driven invocation
  produces the same output as the hotkey-driven one.
- **VoiceOver labels** on every picker row ("⌘N to choose" hint, selected
  trait flips on the highlighted row) and on the picker container itself
  ("Tone picker — Type to filter, arrow keys to navigate, Return to
  apply, Escape to cancel").

### Changed

- `TonePickerController` constructs its `NSPanel` at `init` instead of
  on first `show()`. Pre-warm cost (~30–60ms) moves off the hotkey path.
- `AppDelegate.tonePickerController` is now `let` (eager) not `lazy var`,
  to actually realize the pre-warm.

### Compatibility

- Persisted bindings from v0.8.3 and earlier decode with
  `showInPicker = true` via `decodeIfPresent` — zero migration cost,
  round-trip safe. Users who want a binding hidden from the picker
  can untick it in Settings.

### Build

- Bundle 0.8.4 (build 24).

### Tests

- App: **257 Swift / 54 suites** GREEN (+5 net: 3 new binding/picker
  view-model tests + 3 new `RewriteBinding` Codable tests for
  `showInPicker` default + legacy decode + round-trip).
- Known flaky `SupabaseAuthViewModel.sendCode-no-config` test still
  fails ~once per full suite, passes 10/10 in isolation. Pre-existing
  since v0.5.x — not v0.8.4-related.

## [0.8.3] — 2026-05-24

**Free-text custom instruction in the tone picker** (Apple Writing
Tools style). Type anything into the picker filter and a "Use: ..."
row appears at the top — picking it rewrites with your typed
instruction instead of a preset tone.

### Added

- **`PickerEntry`** sum type — `.preset(RewriteTone)` for built-in
  tones, `.freetext(String)` for user-supplied instructions. The
  view-model + controller + workflow all flow this through.
- **Freetext row** at the top of the picker whenever the query is
  non-empty. Selecting it (Return / ⌘1 / click) commits as freetext;
  the workflow uses the typed text as the rewrite instruction and
  shows "Rewrite (your prompt)" in the preview badge.
- **Field placeholder updated**: "Filter or describe…" makes the
  dual purpose discoverable.

### Changed

- `TonePickerPresenter.present(...)` now returns `PickerEntry?` instead
  of `RewriteTone?`. Internal protocol — no public API churn.

### Notes

- Freetext rewrites do NOT auto-flip `allowsExpressiveContent` on.
  Users who want expressive (`BLOCK_NONE`) routing should pick the
  Chửi thề preset explicitly.

### Build

- Bundle 0.8.3 (build 23).

### Tests

- App: **252 Swift / 53 suites** GREEN (+2 net from the picker
  test rework — old `filtered`/`returnCommitsSelection` tests
  rebuilt around `PickerEntry`, plus new freetext-specific tests).

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
