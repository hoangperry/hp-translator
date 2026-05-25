# Research Report: v0.10.0 Anchor Theme

**Date**: 2026-05-25
**Status**: Recommendation — not yet locked
**Phase**: Pre-Discover (lightweight `/research` skill; full OCTO Discover/Define still optional before commit)
**Precedents**: [docs/v0.9.0/discovery.md](../v0.9.0/discovery.md), [docs/v0.9.0/define.md](../v0.9.0/define.md), v0.9.2 deliver-phase review

---

## Executive Summary

**v0.10.0 should pivot from "utility" → "cultural workflow tool" by anchoring on Theme D (VN Social Register Card) bundled with Theme E (Local-LLM Privacy mode) and a scoped slice of Theme B (Glossary v2: don't-translate + alias entries only).** Apple Intelligence has commoditised generic Vietnamese rewrites by 2026; the surviving moat is **kinship-pronoun precision + dialect-aware particle placement + privacy posture** — three things Apple's globally-aligned models cannot do without per-locale fine-tuning. Carrying Theme B in full (scoped/per-app glossary entries) would muddy the cultural-precision narrative; carrying voice input (WhisperKit) would risk overscope. Refuse dictionary-lookup (Easydict already won that war), browser extension (different security model), CloudKit sync (undermines the privacy story).

## Methodology

- **Tool calls used**: 3 of 5 budget (`/research` skill cap)
- **Sources**: 1 deep gemini-3-flash-preview search (1 call) + in-session context from v0.9.0 discovery + v0.9.2 review + independent architectural pass
- **Tool calls reserved**: 2 (held for follow-up if user pushes back on the recommendation)
- **Date range**: 2024 Q4 → 2026 Q2 (per gemini's own dating; some specific event-citations are gemini-inferred, treated as plausible synthesis rather than verified)

## Key Findings

### F1 — Apple Writing Tools is now Vietnamese-stable but culturally flat

Apple Intelligence Writing Tools shipped Vietnamese support during 2025-2026 [gemini synthesis]. It does generic "Professional / Friendly / Concise" rewrites system-wide. **What it cannot do**: hierarchical kinship pairing (anh / chị / em / cháu), Northern/Southern particle ladder (nhé / ạ / nha / nhen), regional register awareness. Apple ships global safety-aligned models; local-VN fine-tuning is not on Apple's roadmap because the addressable market is too small to warrant their infrastructure.

**Implication**: Apple is the floor for v0.10.0. To justify continued existence, this app must do something Apple actively cannot. Register Card UI is that thing.

### F2 — Privacy framing is now a sale, not a nerd preference

Per the v0.9.0 VN-workflows agent: VN PDPL 2025 + Law on Data 2024 impose 60-day impact-assessment dossiers on cross-border PII transfers, fines up to 5% of revenue. Gemini's search surfaced additional 2026 signal about Zalo / VNG privacy controversy and fines [unverified specifics, plausible direction]. **"Không gửi dữ liệu khách ra nước ngoài" is now a marketable promise**, not just an opt-in toggle.

**Implication**: Theme E (Local-LLM Privacy mode) deserves first-class treatment, not just an onboarding card.

### F3 — WhisperKit / Moonshine VN voice is production-ready in 2026

Argmax Moonshine-Medium (245M) hits ~6% WER on Vietnamese on Apple Silicon, <200ms latency [gemini citation, plausible]. Voice input is no longer "wait for v1.0" technically. **BUT**: shipping voice in v0.10.0 would dilute the "Cultural Precision" narrative + add a permission surface (NSSpeechRecognitionUsageDescription) + add a model-download UX problem.

**Implication**: Note WhisperKit maturity, defer voice to v0.11+ as its own theme.

### F4 — Messenger desktop client deprecated; Zalo Mac still weird

Meta deprecated the standalone Messenger Desktop app (per gemini citation; verify before quoting in release notes); users back to the Facebook.com PWA where double-character Telex IME bugs reappear. Zalo for Mac still has the inconsistent NSText behaviour the v0.9.0 discovery flagged. **OCR-from-screen translate (v0.9.0) was the right bet** — it routes around both of these chat-client quirks.

**Implication**: A "floating voice-reply HUD" attached to capture/OCR could land in v0.11+ if Theme D ships clean.

### F5 — Easydict is the OSS dictionary-lookup winner

tisfeng/Easydict ships 15+ engine support + on-device dictionary integration (MDict). Anything resembling "dictionary lookup" in v0.10.0 = fighting a battle already lost. Reuse the architectural energy on register precision instead.

## Recommendation: v0.10.0 — "Cultural Precision & Privacy"

### Anchor: Theme D — VN Social Register Card

A small Settings panel that lets a user define:

- **Active identity**: role (seller / freelancer / student), gender (optional), dialect (Bắc / Nam), formality default
- **Target identity**: addressee role (customer / sếp / peer / supplier), age tier (older / same / younger), relationship

Output: injected into `binding.customStyleInstruction` automatically for every rewrite + translate-outbound call. Existing tones (Polite, Professional, etc.) become *modulators* on top of the register card, not replacements.

**Why this anchors**: Cannot be replicated by Apple Intelligence (no per-locale fine-tuning roadmap), cannot be replicated by DeepL (their VN launch has formal/informal but no kinship awareness), cannot be replicated by Grammarly (no VN as source language).

### Sub-feature 1: Theme E — Local-LLM Privacy mode

- Settings badge: "🛡 Local only — không gửi dữ liệu khách ra nước ngoài" when Ollama is the active provider
- Onboarding card promoting Ollama install + curated VN-suitable models (qwen2.5-7b-instruct, gemma3-4b-it)
- One-click "Test Ollama connection" button
- Provider disclosure badge in HUD (from v0.9.x review) — shows which provider handled the current translation, so users see "cloud" vs "local" at a glance

### Sub-feature 2: Theme B-Lite — Glossary v2 (don't-translate + alias only)

Migrate `SettingsStore.glossary: String` → `[GlossaryEntry]` with **just two entry types**:

- `.dontTranslate(term)` — brand names, code identifiers ("React", "JIRA-1234", "FREESHIP")
- `.alias(from:to:)` — "shopee" → "Shopee", "tiktok shop" → "TikTok Shop"

**Defer to v0.11+**: scoped entries (per-language, per-app). Today's MVP is "fix the obvious case where brand names get translated", not the full categorisation infrastructure.

### Anti-features (refuse)

- ❌ **Dictionary lookup** — Easydict won
- ❌ **Browser extension** — different security model + per-browser maintenance + duplicates the menu-bar AX path
- ❌ **CloudKit sync** — undermines the Privacy Shield narrative
- ❌ **Voice input (WhisperKit)** — defer to v0.11; adding it now dilutes the Cultural Precision story
- ❌ **Full Glossary v2 with scoped entries** — would be its own minor release
- ❌ **OCR-rewrite flow** — OCR is a READ flow; rewrite implies authorship
- ❌ **AI Agent framing** — VN evidence is concrete user tasks, not autonomous loops

## Implementation Sketch

| Sub-feature | LOC est. | Files touched | Risk | Where it lives |
|---|---|---|---|---|
| Register Card UI | ~250 | new `RegisterCard.swift` + Settings section + 1 line in PromptBuilder | LOW | new struct + Settings panel |
| Register injection into prompt | ~50 | `PromptBuilder.rewriteUserPrompt` / `translateUserPrompt` — prepend register block | LOW | inside existing prompt builder |
| Local-LLM Privacy badge in HUD | ~80 | `HUDController` + `PreviewHUDController` — read active provider, show badge | LOW | view layer only |
| Ollama onboarding card | ~120 | new section in `SettingsWindowController` + small NSWorkspace.open for `ollama.com/download` | LOW | Settings UI |
| Provider disclosure | ~40 | `Persona` extension + 1 SwiftUI label | LOW | view layer |
| Glossary v2 (.dontTranslate + .alias) | ~300 | new `GlossaryEntry` + Codable migration + `PromptBuilder.glossary` use sites | MED | model + 3 prompt sites |
| Tests (register injection + glossary migration) | ~200 | new test files | LOW | tests |

**Total est.**: ~1040 LOC + tests. Slightly under v0.9.0's ~1230 LOC. Comparable to v0.8.0.

## Phasing (if user accepts the recommendation)

- **P1** — Register Card data model + Settings UI (~250 LOC)
- **P2** — Register injection into PromptBuilder + smoke against Gemini/Ollama
- **P3** — Tests: register card → prompt round-trip
- **P4** — Glossary v2 (.dontTranslate / .alias) data model + migration
- **P5** — Glossary v2 wired into PromptBuilder + 3 call sites
- **P6** — Provider disclosure badge in HUD + Local-LLM Privacy badge in Settings
- **P7** — Ollama onboarding card + curated model picker (no auto-install — just deep link to `ollama.com/download` + paste-friendly `ollama pull` commands)
- **P8** — Ship pipeline (bump 0.9.2 → 0.10.0, build 29, notarize, appcast, release)

## Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Register Card combinatorial explosion — too many combos confuse users | HIGH | Start with a tight 3-axis card (dialect, kinship, formality); resist adding more axes until v0.10.1 user feedback |
| R2 | Register prompt block makes the LLM verbose / breaks existing tones | MED | A/B compare register-on vs register-off on each tone during P2 smoke; if outputs degrade, gate register injection by binding-level opt-in |
| R3 | Glossary v2 migration breaks v0.9.x users' single-blob glossary | LOW | Codable migration mirrors the v0.8.4 `showInPicker` pattern (`decodeIfPresent` + sensible default) |
| R4 | Ollama onboarding suggests models that no longer exist on ollama registry | LOW | Pin to ollama.com URLs that 404 cleanly if models change; user-visible error rather than silent fail |
| R5 | Provider disclosure surface area — every HUD now reads `providerFactory()` synchronously | LOW | Resolve provider name eagerly in `TranslationStyle` construction; HUD reads from style, no extra closure capture |

## Open questions (unresolved)

1. **Should the Register Card override existing per-binding `customInstruction`, or compose with it?** Compose is safer (preserves user-tuned bindings); override is cleaner. Recommend compose; let user opt into override via a per-binding toggle in v0.10.1.

2. **Should `.alwaysTranslate(to:)` entries land in v0.10.0 too?** It's the third half of Theme B's full surface. Cheap to add (~30 LOC). Likely yes; defer scoped (.language / .app) entries instead.

3. **Provider disclosure badge — show provider NAME or just PROVIDER TYPE (local / cloud)?** Type is less leaky for screen-sharing; name is more useful for debugging. Probably show type by default, name on hover.

4. **What's the v0.10.0 What's-New copy?** Easy to write once anchor + sub-features lock. Suggest: *"v0.10.0 hiểu xưng hô của bạn — anh/chị/em, Bắc/Nam, formal/chat, và không gửi dữ liệu khách ra nước ngoài."*

## Next steps

1. User decides: accept Theme D anchor as-is, swap to a different theme, or run full `/octo:discover` for broader confirmation
2. If accept: run `/octo:define` to lock scope + AC + risks; then `/octo:develop` to build
3. If unsure: run a second `/research` pass on a more focused question (2 tool calls remain)

## Resources & References

- [gemini citation, plausible] Apple Intelligence Vietnamese rollout 2025-2026 — Apple Newsroom
- [v0.9.0 internal] [Pancake — TikTok Livestream AIO docs](https://docs.pancake.biz/pancake/st-f1/st-p6/st-s4/st-ss3?lang=vi)
- [v0.9.0 internal] [Vietnam PDPL 2025 (Kaamel)](https://www.kaamel.com/blog/article/25a1a80e-ccb9-80af-b88b-fda2e619a3a7)
- [v0.9.0 internal] [VietnameseLab — modal particles](https://vietnameselab.com/blog/vietnamese-particles)
- [gemini citation] Argmax Moonshine benchmarks — argmaxinc.com
- [comparison ref] [tisfeng/Easydict](https://github.com/tisfeng/Easydict) — OSS dictionary aggregator
- [internal] `docs/v0.9.0/discovery.md` — original Theme B/D/E candidate analysis with full sourcing

## Appendix A — Why NOT each alternative anchor

| Alternative | Why not | Defer to |
|---|---|---|
| Theme B (full Glossary v2 — scoped entries) | Internal refactor, no user-facing wow; muddies cultural narrative | v0.11+ as its own minor |
| Voice input (WhisperKit/Moonshine) | Mature tech but adds permission + model-download UX; should be its own minor | v0.11 with onboarding budget |
| Conversation context (prior-message memory) | Requires persistent storage + privacy choices + history search UI; major undertaking | v1.0 |
| Browser extension | Different security model, per-browser maintenance, partially redundant with menu-bar AX path | Probably never |
| CloudKit sync | Locks in iCloud account assumption; undermines the v0.10.0 privacy story | Never (use exported JSON for power users) |
| Document translate (PDF/Word) | Wrong product shape; Easydict / DeepL already cover this | Never |

---

**TL;DR**: Anchor v0.10.0 on **Register Card (Theme D)** + bundle **Local-LLM Privacy (Theme E)** + **Glossary v2-Lite (.dontTranslate + .alias)**. ~1040 LOC, comparable to v0.9.0 effort. Refuse the 7 things listed in Appendix A. Defer voice to v0.11.
