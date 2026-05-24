# v0.9.0 Discovery — Roadmap Candidate Report

**Date**: 2026-05-24
**Status**: Done. Synthesised from VN-workflows research agent (full return) + direct codebase survey + Apple platform API knowledge. 5 of 6 parallel research agents hit session limits (reset 7am Asia/Saigon) — synthesis fills the gap; deeper sourcing those agents would have produced is not in this report.
**Phase**: 1/4 of OCTO Double Diamond.

---

## 1. Executive Summary

**v0.9.0 should be "Vietnamese seller workspace": a minor-version bump justified by three interlocking primitives — App Intents/Shortcuts, on-device language detection + glossary v2 (categories + per-app), and OCR-from-screen translate.** This package directly attacks the gaps Apple Writing Tools cannot fill for VN power-users (commerce, freelance, support), exploits 4 cheap-and-shipping macOS APIs the codebase has never touched (App Intents, Vision, NaturalLanguage, ScreenCaptureKit), and is buildable in 2–3 release cycles without touching the existing 270-test contract. Defer voice input, conversation context, browser extension, and CloudKit sync to v1.0.

---

## 2. Key Themes

### Theme A — "Workspace expansion": automate the surrounding workflow, not just the rewrite

**Summary**: The app today is an excellent single-shot tool (translate / rewrite + paste). What VN sellers actually do is *chains of work*: read a CN/EN message → reply → log to spreadsheet → repeat. v0.8.5's multi-variant rewrite is the first crack at workflow density. v0.9.0 should double down with primitives that compose into chains.

**Supporting evidence**
- VN agent: TikTok Shop / 1688 / Aliwangwang sellers face a documented "browser-translate plugins blocked inside chat client" gap [Source: sourcingnova.com]. A global-hotkey translator IS the only solution today, but it's a one-shot — no chained reply.
- VN agent: Pancake/Vpage CS agents need 1-minute response under the +391% conversion correlation. Picking from 3 rewrite drafts in PreviewHUD (v0.8.5 already ships) is the right primitive; the missing piece is **invoking the same primitive from Shortcuts.app / Raycast / Alfred / a custom hotkey-runner**.
- Codebase: zero AppIntent usage. App Intents (macOS 13+) is a 1-protocol, ~100-LOC addition that unlocks Shortcuts.app, Spotlight actions, and Siri.
- Competitor pressure: Raycast translate extension is the gravity well for power-users *because* it integrates with the launcher. Without an App Intent surface, we lose that audience by default. [Source: raycast/extensions repo on GitHub.]

### Theme B — "Register intelligence": double down on what Apple/DeepL/Grammarly *cannot* do

**Summary**: VN agent confirmed the central gap competitors can't close — kinship-pronoun pairing (anh/chị/em), particle politeness (ạ/dạ/nhé/nha/nhen), Bắc/Nam dialect awareness, and supplier-register CN↔VN translation. v0.7's per-binding tones + v0.8's picker already started this; v0.9.0 should make it the moat.

**Supporting evidence**
- VN agent: "DeepL added VN in mid-2025 with formal/informal tone, but has no dialect (Bắc/Nam) awareness and no particle-aware politeness ladder" [Source: deepl.com VN launch blog].
- VN agent: Apple Translate has no rewrite/tone presets, zero kinship-pronoun pairing awareness.
- Codebase: `PromptBuilder.rewriteSystemPrompt` already encodes the right examples for VN, but the surface is invisible — buried in a global text blob. A **"register card"** UI (pick dialect, formality, kinship-target) would expose what's already there.
- Codebase: glossary is a single Keychain string today (`SettingsStore.glossary`, used at `PromptBuilder:78,98`). Splitting it into typed entries (don't-translate, force-translate, per-language, per-app context) is a small-medium refactor.

### Theme C — "Capture surface expansion": OCR-from-screen as the cheapest new input modality

**Summary**: The app today captures via clipboard (cmd-C automation) or current-line keyboard simulation. The next obvious modality is **selected screen region → OCR → translate/rewrite pipe**. macOS has shipped Vision text-recognition with Vietnamese support for years, and ScreenCaptureKit makes the capture trivial. This is the highest-value-per-LOC feature on the candidate list.

**Supporting evidence**
- VN agent: TikTok-Shop / 1688 sellers see Aliwangwang and similar chat clients that block browser-level translation. OCR-from-region routes around this entirely.
- Apple platform: `VNRecognizeTextRequest` supports Vietnamese on-device (macOS 13+), zero LLM cost. `ScreenCaptureKit` (macOS 12.3+) handles the crosshair-and-capture UX cleanly.
- Codebase: zero existing screen-capture or vision code. Greenfield, no architectural risk.
- Competitor pressure: TextSniper, Easydict, Mate Translate all offer OCR-translate. It's table-stakes in 2026 for a translator app.

### Theme D — "Local-LLM compliance angle"

**Summary**: VN Personal Data Protection Law 2025 ("PDPL 2025") + Law on Data 2024 imposes 60-day impact-assessment dossiers on cross-border PII transfers and fines up to 5% of revenue. The app already supports Ollama; v0.9.0 should *promote it from afterthought to first-class*. Marketing copy that lands ("không gửi dữ liệu khách ra nước ngoài") is real, not paranoid.

**Supporting evidence**
- VN agent: PDPL 2025 enacted, cross-border PII triggers impact-assessment [Source: Kaamel.com VN PDPL summary, cms-lawnow.com].
- Codebase: Ollama provider exists (`Sources/ContextualMacTranslator/Providers/OllamaDirectProvider.swift`) but onboarding doesn't surface it. The "rewriteAvailable" gate at `SettingsStore.swift:555` lists Ollama as eligible.
- Marketing angle: a "Local-only mode" badge in Settings + an onboarding step that helps the user install Ollama + pull a model (e.g. qwen2.5-coder for VN/CN) is a 1-day chore with outsized brand value.

### Theme E — "Onboarding + visibility": new APIs that surface what's already shipped

**Summary**: The app has 30+ features users discover by accident. The Sparkle release-notes mechanism is the only "what's new" channel today. macOS 15+ TipKit + a What's-New flow are cheap; both should ride along with any v0.9.0 release.

**Supporting evidence**
- Codebase: 844-line `SettingsWindowController.swift` (approaching 800-line guideline) — feature surface is already overwhelming. New features need self-introduction.
- Apple platform: TipKit (iOS 17 / macOS 15+) requires `TipsCenter.shared.load()` + one `Tip` struct per feature. Trivial integration.
- Multi-variant rewrite (v0.8.5) shipped with no in-app introduction — users have to find the toggle. v0.9.0 should land with a What's-New sheet that highlights it and the new v0.9 features.

---

## 3. Key Takeaways

### Top-5 features to ship in v0.9.0 (ranked by leverage)

1. **App Intents + Shortcuts integration** *(S, low-risk)* — Expose `TranslateSelection`, `RewriteSelection(tone:)`, `RewriteSelection(prompt:)` as App Intents. Unlocks Shortcuts.app, Raycast/Alfred wrappers, Spotlight actions, Siri voice. ~200 LOC, one entitlement, zero new permissions. **Lead with this.**

2. **OCR-from-screen translate** *(M, low-risk)* — `⌘⌥G` (mnemonic: "grab") opens screen-region crosshair via ScreenCaptureKit → Vision OCR → translate via the active provider → result in PreviewHUD (which already handles editable text + paste). ~400 LOC, one new permission prompt (Screen Recording). Bolts onto every existing provider for free.

3. **Glossary v2 — typed entries with categories** *(M, medium-risk)* — Migrate `SettingsStore.glossary: String` → `[GlossaryEntry]` where each entry has type (`.dontTranslate | .alwaysTranslate(to:) | .alias`), scope (`.global | .language(String) | .app(bundleID)`), and the term. Build the migration with `decodeIfPresent` like `RewriteBinding.showInPicker` did. ~500 LOC + migration tests.

4. **Register Card UI for VN tones** *(S, low-risk)* — A small panel on the rewrite Settings page exposing dialect (Bắc/Nam), kinship target (anh/chị/em/bạn), particle level (none/nhé/ạ). Outputs are injected into the `customStyleInstruction` of the binding being edited. Doubles down on the v0.7 moat. ~250 LOC.

5. **Local-LLM "Privacy mode" pivot** *(S, low-risk)* — Onboarding card promoting Ollama + a curated model list (qwen2.5-7b-instruct for VN, gemma3 for EN). Settings badge: "Local only — không gửi dữ liệu". One-click "Test connection" button. Mostly UI + copy; the provider already exists. ~150 LOC.

**Total estimated v0.9.0 work**: ~1500 LOC + tests + 1 entitlement (Screen Recording) + 1 release-cycle build/notarize/ship pipeline. Each item independently testable + ship-able.

### Deferred to v1.0 (do not start in v0.9.0)

- **Voice input (SpeechRecognizer)** — Apple's VN dictation accuracy is weaker than EN; users who care already use MacWhisper. High effort, medium uncertainty. *Wait for WhisperKit maturity.*
- **Conversation context (prior-message memory)** — Requires persistent storage, privacy choices, history search UI. Major undertaking. *Earns a v1.0 minor.*
- **Browser extension** — Different security model + WebExtensions build pipeline + Safari/Chrome split. *Different product.*
- **CloudKit sync of glossary/settings** — Enables multi-Mac, but locks in iCloud-account assumption + requires CloudKit container provisioning. *Defer until there's demand.*
- **Document translate (PDF/Word)** — Large feature, niche audience for this product shape. *Easydict already does it; let users pick that for batch.*
- **Per-binding multi-variant override** *(deferred from v0.8.5)* — Real but low-urgency. Slot into v0.9.1 patch.
- **VoiceOver + reduce-motion deep polish** *(carried from v0.8.4)* — Continuous improvement, doesn't justify a minor bump on its own.

### Theme to lead with

**Theme A (App Intents/Shortcuts) is the highest-leverage one to land first** because:
- It's pure additive surface (no risk to 270 existing tests)
- Unlocks ALL other ecosystem integrations users currently can't do
- Differentiates from Apple Writing Tools (which can't be triggered from Shortcuts.app at all)
- Vietnamese power-user evidence (Theme B/C VN findings) all funnel into "I want to chain this into my workflow"

### Anti-features — refuse these in v0.9.0

- ❌ **"AI Agent" framing** — VN agent's evidence is concrete user tasks, not autonomous LLM loops. Resist the temptation.
- ❌ **Subscription billing / paywall** — MIT-licensed OSS positioning is the moat against DeepL/Grammarly subscriptions. Don't break it.
- ❌ **Telemetry / analytics beyond crash reports** — VN PDPL findings make data export a brand risk, not just a privacy preference.
- ❌ **Auto-rewriting without preview** — every existing flow shows PreviewHUD before paste. Don't ship an "instant rewrite" mode that bypasses confirmation.
- ❌ **Default-on multi-variant** — keep v0.8.5's opt-in. The single-draft path is faster + cheaper and most flows don't need 3 options.
- ❌ **Cloud-stored history** — even encrypted. Local-only or CloudKit-only-on-explicit-opt-in.

---

## 4. Sources & Attribution

### VN-workflows research (full agent return)
- [Pancake — TikTok Livestream AIO docs](https://docs.pancake.biz/pancake/st-f1/st-p6/st-s4/st-ss3?lang=vi)
- [Sourcing Nova — 1688 guide / Aliwangwang gap](https://sourcingnova.com/blog/1688-com-sourcing-guide/)
- [DeepL Vietnamese launch](https://www.deepl.com/en/blog/vietnamese-thai-hebrew-launch)
- [Vpage CS reply templates](https://vpage.nhanh.vn/blog/ky-nang-tra-loi-tin-nhan-khach-hang-chuyen-nghiep-nang-cao-hieu-qua-chot-don-a62.html)
- [VietnameseLab — modal particles](https://vietnameselab.com/blog/vietnamese-particles)
- [Vietnam PDPL 2025 (Kaamel)](https://www.kaamel.com/blog/article/25a1a80e-ccb9-80af-b88b-fda2e619a3a7)
- [CMS Law-Now — VN new data laws](https://cms-lawnow.com/en/ealerts/2025/09/demystifying-vietnam-s-new-laws-regulating-data-and-navigating-key-compliance-for-businesses)

### Codebase survey (this session)
- `SettingsStore.swift:155-158, 314, 422` — glossary as single Keychain string
- `SettingsStore.swift:555` — only real "deferred" comment (backend rewrite gating)
- `Models.swift:78,97` — variantCount infra, clamped [1,5], only used in rewrite path
- `TranslationWorkflow.swift:398,411,422` — performRewriteVariants extension point
- `Providers/PromptBuilder.swift:18,38,78` — glossary injection points (3 sites)
- `FocusGuard.swift:17` — only existing per-app awareness (frontmost PID for clipboard guard)
- File-size: `SettingsWindowController.swift` 844 lines (approaching 800 limit)
- Verified absences: zero AppIntent / SFSpeechRecognizer / ScreenCaptureKit / VNRecognizeText / NLLanguageRecognizer / CloudKit / TipKit / Telemetry / conversation-history code

### Apple platform APIs (developer.apple.com / training knowledge)
- App Intents framework, macOS 13+: `developer.apple.com/documentation/appintents` — 1 protocol, ~100 LOC integration, unlocks Shortcuts + Spotlight + Siri.
- Vision text recognition (Vietnamese support): macOS 13+, `VNRecognizeTextRequest` with `recognitionLanguages = ["vi-VN", "en-US", "zh-Hans"]`.
- ScreenCaptureKit, macOS 12.3+: `developer.apple.com/documentation/screencapturekit` — region capture with permission prompt.
- TipKit, macOS 15+: lightweight tip presentation. *[Inference: not yet verified for SwiftUI menu-bar contexts — needs spike before commit.]*
- NaturalLanguage `NLLanguageRecognizer`: macOS 10.14+, on-device language detection — cheap free auto-detect.

### Competitor evidence
- Apple Writing Tools coverage gaps (no Shortcuts entry point, no kinship-pronoun awareness, no custom-provider injection) — [Inference] from Apple Intelligence docs + the VN-workflows agent's register analysis.
- DeepL VN launch with formal/informal but no dialect — verified from VN agent's sources.
- Easydict OSS pattern (https://github.com/tisfeng/Easydict) for OCR-translate workflow — [Inference: known popular OSS reference, not directly inspected this session]

### Gaps / unverified
- **5 research agents (code-explorer, competitor matrix, Apple-API deep-dive, OSS inspirations, HN/Reddit power-user)** hit session limits at agent infrastructure level (reset 7am Asia/Saigon, agent IDs preserved for resume). Their findings are SYNTHESIZED HERE from direct grep/Read + my knowledge — but the deeper sourcing those agents would have produced is missing. Specifically not deeply verified:
  - Exact Maccy/KeyboardShortcuts/Easydict file:line patterns for forking
  - Current App Store review themes for DeepL/Mate/Grammarly
  - HN/Reddit specific feature-request frequency
  - macOS 26 (Liquid Glass era) API delta confirmations
- **VN agent flagged 2 inferences honestly**: freelancer/remote-dev persona size; PDPL → local-LLM appetite link. Both retained but tagged.

---

## 5. Methodology

- **6 parallel agents launched** for Deep intensity research per `/octo:discover` workflow.
- **1 agent completed**: VN power-user workflows (full quality, 15 sources, 2 honest inference flags).
- **5 agents hit session limit** before producing output (resets 7am Asia/Saigon, agent IDs `a786c12896d7c6a78`, `abb8932d24fed7a45`, `a3b79e8840596b99b`, `ae1f8ae2c15d7e207`, `a2c15eec36bcf7d55` — can be resumed via SendMessage if user wants deeper verification later).
- **Direct synthesis substitute**: codebase grep/Read for the code-explorer agent's coverage; training-knowledge + Apple docs URLs for the API agent's coverage; training-knowledge for competitor matrix.
- **Not covered this session** (recommend re-running after session reset if Theme A/B selected): Maccy/KeyboardShortcuts code patterns for App Intents integration; Easydict OCR-flow specifics; current HN/Reddit signal on Apple Writing Tools complaints; App Store review themes for DeepL/Mate Translate post-VN launch.
