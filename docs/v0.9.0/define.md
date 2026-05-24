# v0.9.0 MVP Definition — "Input Surface Expansion"

**Date**: 2026-05-25
**Status**: Locked. Ready for develop phase.
**Phase**: 2/4 of OCTO Double Diamond.
**Precedent**: see [discovery.md](./discovery.md) for the candidate analysis.

---

## 0. Theme Lock

**SHIP**: App Intents (Theme A) + OCR-from-screen translate (Theme C), bundled.
**DEFER**: Glossary v2 (B), Register Card (D), Local-LLM promotion (E) → v0.9.1+.

### Why A+C over alternatives

| Bundle | Verdict | Reasoning |
|---|---|---|
| **A+C (lock)** | ✅ | Both greenfield (zero existing AppIntent/Vision/ScreenCaptureKit code), share permission-prompt UX surface, narrative "from any app, from any pixel" is one sentence, no risk to 270-test contract. |
| A only | ❌ | Too thin for a minor bump. App Intents alone reads like a patch release. |
| A+B (glossary) | ❌ | Glossary v2 is medium-risk migration touching PromptBuilder × 3 sites. Mixes "new input surface" theme with internal refactor — incoherent narrative. |
| A+D (Register) | ❌ | Register Card is a tiny UI panel deepening the rewrite-tone moat. Coherent but small — defer to v0.9.1 as a polish patch. |
| A+E (Local-LLM) | ❌ | Mostly marketing copy + onboarding cards. Don't deserve a minor-version bump on its own — fold into v0.9.0 RELEASE NOTES as a sidebar (Ollama already works). |
| A+C+D | ❌ | Scope creep. Three themes muddies the story. |

**Anchor narrative for release notes**: *"v0.9.0 mở rộng cách bạn gọi app — từ bất kỳ app nào qua Shortcuts.app, hay chộp text từ bất kỳ pixel nào trên màn hình bằng OCR."*

---

## 1. MVP Scope IN

### A — App Intents (P0)

**A.1 — Intents to ship (3, no more):**
1. `TranslateSelectionIntent` — input: `selectedText: String`, `targetLanguage: String?` (optional, defaults to `SettingsStore.primaryLanguage`). Output: `IntentResult & ReturnsValue<String>` (the translation). No UI side-effect — pure data in/out.
2. `RewriteWithToneIntent` — input: `text: String`, `tone: RewriteToneAppEnum` (mirrors `RewriteTone` cases). Output: `String`. No UI.
3. `RewriteWithPromptIntent` — input: `text: String`, `instruction: String`. Output: `String`. No UI.

**Deliberately NOT shipped** (defer to v0.9.1+):
- `PickRewriteVariantIntent` (UI-bound, complicates intent shape)
- `OpenTonePickerIntent` (Shortcuts can already trigger app via URL scheme — overlap)
- Streaming output intents (Shortcuts.app doesn't render mid-stream — wasted complexity)

**A.2 — Workflow integration:**
- New entry-point method on `TranslationWorkflow`: `performTranslationHeadless(text:targetLanguage:) async throws -> String` and `performRewriteHeadless(text:style:) async throws -> String`. These bypass HUD/PreviewHUD/clipboard/keyboard simulation — pure provider call + `RewriteResultProcessor.clean()` (for rewrite). Reuse the same `providerFactory`, `glossaryProvider`, `primaryLanguageProvider`. NO new TranslationProvider abstraction.
- Existing `translateAndSend` / `rewriteAndSend` / `rewriteWithPickerAndSend` unchanged.
- Errors surface as `IntentError` (typed) with `localizedDescription` mapped from existing `TranslationError` / `RewriteError`.

**A.3 — Permission/entitlement:**
- App Intents framework, macOS 13+. ✅ Compatible with macOS 14 floor.
- LSUIElement compatibility: Apple docs confirm LSUIElement apps can host App Intents (Shortcuts.app discovers them via Info.plist + intent metadata). No Dock-icon requirement.
- No new entitlement. Just import `AppIntents` and declare `AppShortcutsProvider`.

### C — OCR-from-screen translate (P0)

**C.1 — Capture flow:**
1. User presses configurable hotkey (default unset; user opts in via Settings → Capture).
2. `ScreenCaptureService.captureRegion()` invokes `SCContentSharingPicker` (macOS 14+) → user drags crosshair → returns `CGImage`.
   - Alt fallback if SCContentSharingPicker behaves oddly: use `CGRequestScreenCaptureAccess()` for permission, `SCStream` for capture. Spike in P3 to pick.
3. Image → `VNRecognizeTextRequest(recognitionLanguages: ["vi-VN", "en-US", "zh-Hans", "ja-JP", "ko-KR"], usesLanguageCorrection: true)`. Vision auto-detects within that list.
4. OCR'd text → `NLLanguageRecognizer` to identify dominant source language (already on-device, free).
5. Build a `TranslationJob(direction: .inbound, sourceLanguage: detected, targetLanguage: primaryLanguage, register: .neutral, text: ocrText)`.
6. Route through existing `translateAndPresentInHUD()` path → PreviewHUD with the OCR'd text as `original` and translation as `translated`. User can edit, copy from HUD, or just read.

**C.2 — Hotkey:**
- New `SettingsStore.captureHotkey: HotkeyConfig?` (default `nil`). Follows the exact pattern of `pickerHotkey` from v0.8.0.
- Settings UI adds a row "OCR capture hotkey" with HotkeyRecorderSheet + conflict-check against existing bindings.
- Re-pressing the hotkey while crosshair is active cancels the capture (mirror tone-picker toggle behavior).
- Gated by: capture provider must be ready AND `availableProvider().isConfigured` — same gate as translate hotkeys.

**C.3 — Translate-only, no rewrite path:**
- OCR → translate is the only flow in v0.9.0. OCR → rewrite is incoherent (rewrite implies the user authored the text) and would invite confusion. Explicit OUT.
- Edit-in-place: PreviewHUD's existing `editableTranslation` field lets users tweak the translation. The OCR'd source text in the HUD `original` field is NOT editable (matches existing inbound translate flow).
- No paste/send behavior — OCR-translate is a *read* flow, not a *send* flow. User copies from PreviewHUD if they want the text. PreviewHUD's "Send" button becomes "Copy" when source is OCR (single-line UX delta).

---

## 2. Out of Scope (explicit DEFER list)

| Item | Defer to | Reason |
|---|---|---|
| `PickRewriteVariantIntent` | v0.9.1 | UI-bound intent; better as URL scheme handler |
| Streaming intent output | Never | Shortcuts.app doesn't render streams |
| OCR → rewrite flow | Never | Conceptually incoherent |
| OCR multi-variant translate | v0.9.1 | Translation paths don't use `variantCount > 1` yet — separate work |
| Glossary v2 typed entries (Theme B) | v0.9.1 or v0.9.2 | Independent refactor, medium-risk |
| VN Register Card UI (Theme D) | v0.9.1 | Small polish, doesn't justify version bump |
| Local-LLM Privacy mode pivot (Theme E) | v0.9.0 release-notes sidebar only | Mostly marketing |
| Voice input (SpeechRecognizer) | v1.0 | High effort, low VN accuracy |
| Conversation context | v1.0 | Storage + privacy model required |
| Browser extension | v1.0 | Different security model |
| CloudKit sync | v1.0 | Locks in iCloud assumption |
| Document translate (PDF/Word) | Never (Easydict serves this) | Wrong product shape |
| Per-binding multi-variant override | v0.9.x patch | Low urgency carry-over from v0.8.5 |
| `SettingsWindowController` split | v0.9.0 (RIDE-ALONG) | 844 LOC + OCR settings would exceed 1000; split during P6 |

---

## 3. Acceptance Criteria

### P0 — must-have, blocks ship

**App Intents:**
- **AC1**: Shortcuts.app lists three actions: "Translate Selection", "Rewrite with Tone", "Rewrite with Prompt", under "Contextual Mac Translator".
- **AC2**: Each intent runs end-to-end from a Shortcut and returns the translated/rewritten text. Result usable in subsequent Shortcut steps.
- **AC3**: Tone enum in `RewriteWithToneIntent` includes all 7 standard `RewriteTone` cases (Polite, Professional, Friendly, Firm-but-polite, De-escalate, Concise, Custom). Expressive tones (Chửi thề) are hidden unless `expressiveTonesEnabled` is ON — same gate as picker.
- **AC4**: Intent failure (no LLM provider, network error, refusal) surfaces a human-readable error to Shortcuts.app via `IntentError.localizedDescription`. No silent failures, no crashes.
- **AC5**: Each intent has a Spotlight-suggested phrase ("Translate this", "Rewrite politely", etc.) declared in `AppShortcutsProvider`. Surfaces in macOS Spotlight.

**OCR capture:**
- **AC6**: Settings → Capture section exposes "OCR capture hotkey" row with recorder UI + conflict detection (reusing v0.8.0 `HotkeyRecorderSheet`).
- **AC7**: Pressing the hotkey shows a screen-region crosshair within 200ms of keystroke. Esc cancels with no side effect.
- **AC8**: After region selection, OCR completes within 2s for a typical 800×400 region of mixed VN+EN+CN+JP+KR text. Result populates PreviewHUD as "original".
- **AC9**: Source language is auto-detected via NLLanguageRecognizer; translation uses `SettingsStore.primaryLanguage` as target. Result shown in PreviewHUD translation field.
- **AC10**: First-ever OCR invocation triggers the Screen Recording TCC prompt. Settings has an onboarding card explaining why + linking to System Settings → Privacy & Security → Screen Recording.
- **AC11**: PreviewHUD's "Send" button is relabeled to "Copy" when invoked via OCR path. Clicking it copies translation to clipboard, dismisses HUD. No keyboard-paste simulation.
- **AC12**: OCR capture is refused (with clear toast) when no translate-capable provider is configured.

**Backward compatibility:**
- **AC13**: All 270 existing tests pass unchanged.
- **AC14**: Existing user persisted state (RewriteBindings, hotkeys, expressive-tones toggle, multi-variant toggle, glossary string, Supabase auth) round-trips clean. Zero migration prompts on first v0.9.0 launch.
- **AC15**: Sparkle OTA from v0.6.1+ to v0.9.0 succeeds with no manual user intervention.

### P1 — should-have, can patch in v0.9.1 if blocked

- **AC16**: App Intents test harness — at least 5 unit tests covering intent body logic (mocked workflow, no real LLM call).
- **AC17**: OCR test coverage — at least 5 tests for OCR pipeline orchestration (mocked ScreenCaptureService + mocked Vision, fixture image → known text).
- **AC18**: Vision OCR results pre-clean: strip control characters, collapse multiple whitespace, preserve VN diacritics. Verified by unit test with VN-text fixture image.
- **AC19**: macOS What's-New sheet on first v0.9.0 launch listing the two new features. Dismissible. Persist "shown" flag.

### P2 — stretch, defer freely

- **AC20**: Capture hotkey can also be triggered from menu bar item ("Capture & Translate…").
- **AC21**: NLLanguageRecognizer falls back to `auto` (pass through to provider's own detection) if confidence below threshold.
- **AC22**: VoiceOver labels on the crosshair overlay ("Drag to select capture region. Press Escape to cancel.").

---

## 4. Constraints

### Hard constraints (cannot violate)

- **Swift 6 strict concurrency** — all new types `Sendable` or `@MainActor`. App Intents bodies likely need `@MainActor` (they touch SettingsStore.shared).
- **macOS 14 minimum** — verified. `ScreenCaptureKit` (12.3+), `VNRecognizeTextRequest` (10.15+), `AppIntents` (13+), `NLLanguageRecognizer` (10.14+). All compatible.
- **LSUIElement = true** preserved.
- **Zero break** to: Sparkle OTA, RewriteBinding/HotkeyConfig/TranslationStyle Codable contracts, 11 RewriteTone cases, expressive-tones toggle, multi-variant toggle.
- **No new dependencies** — App Intents, Vision, ScreenCaptureKit, NaturalLanguage all Apple-provided. No SPM additions.
- **No file > 800 lines** — triggers `SettingsWindowController` split during P6.

### Reuse mandates (don't reinvent)

- `PreviewPresenter.presentPreview(...)` (NOT `presentVariants` — OCR is single-result).
- `RewriteResultProcessor.clean(_:)` for rewrite intent output.
- `HotKeyManager.register(...)` for the OCR hotkey (full-set-replace pattern).
- `HotkeyRecorderSheet` for Settings recorder UI.
- `HotKeyManager` conflict-detection logic.
- `SettingsStore.persist(_:forKey:)` Codable persistence pattern.
- `ClipboardService` for final copy-to-clipboard step.
- Existing TranslationProvider abstraction — no new layer.

### Test mandates

- All new code paths have at least one test (target: maintain ~3.6 tests/100 LOC ratio per current contract).
- App Intents tests: use a `MockTranslationWorkflow` injected via the same DI pattern as existing tests.
- OCR tests: stub `ScreenCaptureService` + `OCREngine` protocols; never call real ScreenCaptureKit/Vision in tests.

---

## 5. Phased Build Plan

Each phase is independently shippable (build green, tests green, smoke-launches). Phase order optimised so the most-risky probes (App Intents discoverability, ScreenCaptureKit picker UX) land early.

| Phase | Scope | Acceptance | LOC est. |
|---|---|---|---|
| **P1 — App Intents core** | `TranslationIntents.swift` with the 3 intents + `AppShortcutsProvider` + `RewriteToneAppEnum` mirror. Headless workflow methods (`performTranslationHeadless`, `performRewriteHeadless`). | AC1, AC2, AC3, AC4 manual smoke (open Shortcuts.app, drag each action, verify result). | ~250 |
| **P2 — App Intents tests** | `TranslationIntentsTests.swift` — 5+ tests with mock workflow. Error mapping tests. | AC16. 275+ tests GREEN. | ~150 |
| **P3 — OCR scaffolding + permission spike** | `ScreenCaptureService.swift` (protocol + real impl), `OCREngine.swift` (protocol + Vision impl), `LanguageDetector.swift` (NaturalLanguage wrapper). NSScreenCaptureUsageDescription added to Info.plist. Spike: SCContentSharingPicker vs SCStream — pick one. | Real screenshot → real OCR → real text printed in unit-test debug build. | ~300 |
| **P4 — Capture hotkey + workflow** | `SettingsStore.captureHotkey: HotkeyConfig?`. New workflow entry `captureAndTranslate()` orchestrating ScreenCapture → OCR → LanguageDetect → TranslationJob → existing translate path → PreviewHUD. New AppDelegate wiring + hotkey gating. | AC6, AC7, AC8, AC9 manual. | ~200 |
| **P5 — PreviewHUD OCR adaptation** | Add `PreviewHUDViewModel.mode: PresentationMode = .send | .copy`. When `.copy`, send button becomes "Copy", paste-and-enter logic skipped. | AC11. Existing send flows unchanged. | ~80 |
| **P6 — Settings UI + split** | New "Capture" section in Settings. OCR onboarding card with link to System Settings → Screen Recording. Triggers `SettingsWindowController.swift` split into 3 files (`SettingsWindowController.swift`, `SettingsRewriteSection.swift`, `SettingsCaptureSection.swift`). | AC10, AC12. SettingsWindowController.swift <800 lines. | ~250 (net of split) |
| **P7 — OCR tests + polish** | OCR pipeline tests with fixture image. Language-detect confidence-threshold test. AC18 diacritic-preservation test with VN fixture. What's-New sheet (AC19). | AC17, AC18, AC19. 290+ tests GREEN. | ~200 |
| **P8 — Ship pipeline** | Bump 0.8.5 → 0.9.0 (build 26) in 3 scripts. CHANGELOG [0.9.0] section. DMG + Sparkle zip build, notarize, staple. appcast.xml entry. Commit + tag v0.9.0 + push + `gh release create v0.9.0 --latest`. Verify Pages serve. | AC15 verified. | N/A |

**Total estimated work**: ~1230 LOC + tests + ship pipeline. Comparable to v0.8.0 (which was 1100 LOC + tests).

---

## 6. Risk Register

| # | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | **LSUIElement + Shortcuts.app discovery** — does Shortcuts list intents from menu-bar-only apps? | HIGH | LOW | Spike in P1 first hour: build minimal intent, open Shortcuts.app, verify visibility. If broken, bail and downscope to URL-scheme handler. |
| R2 | **Screen Recording TCC prompt UX** — first OCR fails because user denies/dismisses prompt, then app silently broken. | MED | HIGH | AC10 onboarding card + `CGPreflightScreenCaptureAccess()` check on hotkey trigger; if not authorized, show actionable toast linking to System Settings. |
| R3 | **Vision VN OCR accuracy** — diacritics garbled (ạ → a, ô → o) or VN mistaken for EN. | HIGH | MED | P3 spike + P7 AC18 fixture test. Fallback: if `usesLanguageCorrection: true` underperforms, set false + post-process. If still bad, route image to Gemini Vision as fallback provider (defer to v0.9.1). |
| R4 | **SCContentSharingPicker vs SCStream choice** — picker is macOS 14+ (✅) but newer UX, less battle-tested. | MED | MED | Spike P3, pick whichever has fewer edge cases. SCContentSharingPicker preferred (lower-effort UX). |
| R5 | **App Intents test harness** — intents run in a separate XPC process, hard to integration-test in CI. | LOW | HIGH | Don't try. Unit-test the intent body (which calls injected workflow) with a mock workflow. Manual smoke test in Shortcuts.app before each release. |
| R6 | **macOS 26 (Liquid Glass) Shortcuts.app rendering** — intents might render differently. | LOW | LOW | Test on macOS 14 baseline + macOS 26 build env. Cosmetic only. |
| R7 | **SettingsWindowController split breakage** — refactor introduces bugs in existing settings rows. | MED | MED | Split is pure file-move + extract — no logic change. P6 includes a manual smoke pass of every Settings row. All 270 existing tests catch logic regressions. |
| R8 | **Conflicts with existing hotkeys** — user binds OCR hotkey to ⌘⌥G but already uses it for something. | LOW | MED | Existing HotKeyManager conflict-detection catches this. AC6 includes conflict-check. |
| R9 | **Captured image privacy** — OCR'd text sent to LLM provider in cleartext. | MED | HIGH | Document in privacy section of README. Per Theme E findings (PDPL): recommend Ollama for OCR users handling customer data. No new technical mitigation needed (same posture as text translate today). |
| R10 | **Sparkle channel break** — Info.plist changes (new permission key) might invalidate ed-signature compute. | LOW | LOW | Verified: ed-signature signs the .zip not Info.plist. No risk. |
| R11 | **Spotlight + Siri suggested phrases conflict with system** — "Translate this" overlaps Apple Translate Siri. | LOW | MED | Use unambiguous phrases: "Translate with Contextual" / "Rewrite politely with Contextual". |

---

## 7. Definition of Done

- [ ] All P0 ACs (AC1-AC15) pass manual + automated verification.
- [ ] At least AC16-AC18 of P1 pass; AC19 best-effort.
- [ ] 290+ Swift tests / 58+ suites GREEN (270 existing + ~20 new).
- [ ] Build clean: `swift build` zero warnings.
- [ ] App launches and Settings → Capture section works end-to-end.
- [ ] Shortcuts.app lists 3 actions, each tested with a 2-step Shortcut.
- [ ] DMG signed + notarized + stapled. Sparkle zip signed + notarized + stapled. Appcast updated.
- [ ] CHANGELOG [0.9.0] section written.
- [ ] git tag v0.9.0 + push + `gh release create v0.9.0 --latest` published.
- [ ] Smoke test from v0.8.5 via Sparkle OTA upgrade to v0.9.0 succeeds.
