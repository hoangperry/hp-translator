# v0.10.0 MVP Definition — "Cultural Precision & Privacy"

**Date**: 2026-05-25
**Status**: Locked. Ready for develop phase.
**Phase**: 2/4 of OCTO Double Diamond (Research → Define → Develop → Deliver).
**Precedent**: [docs/v0.10.0/research.md](./research.md) for the anchor analysis; [docs/v0.9.0/define.md](../v0.9.0/define.md) for the spec template.

---

## 0. Theme Lock

**SHIP** — Theme D anchor (VN Social Register Card) + Theme E lite (Local-LLM Privacy mode) + Theme B lite (Glossary v2: `.dontTranslate` + `.alias` + `.alwaysTranslate`).

**DEFER** — full Theme B with scoped entries (per-language / per-app), voice input (WhisperKit), browser extension, CloudKit sync, document translate, dictionary lookup, per-binding register-override toggle, AI-Agent framing.

### Why anchor on Theme D

| Alternative anchor | Why not |
|---|---|
| **Theme B (full Glossary v2)** | Internal refactor; muddies the cultural-precision narrative |
| **Theme E (full Local-LLM pivot only)** | Mostly marketing; doesn't earn a minor-version bump on its own |
| **Voice input (WhisperKit)** | Mature tech but dilutes cultural-precision story + adds permission + model-download UX. Defer to v0.11 |
| **Conversation context (history)** | Major undertaking with privacy/storage choices. v1.0 |

**Anchor narrative for release notes**: *"v0.10.0 hiểu xưng hô — anh/chị/em, Bắc/Nam, formal/chat. Và không gửi dữ liệu khách ra nước ngoài khi dùng local mode."*

---

## 1. MVP Scope IN

### A — Register Card (P0, anchor)

**A.1 — Data shape:**

```swift
struct RegisterCard: Codable, Equatable, Hashable, Sendable {
    enum Dialect: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified, northern, southern
        var id: String { rawValue }
    }
    enum Kinship: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified  // model picks based on context
        case anh          // speaker addresses younger / equal male
        case chi          // speaker addresses younger / equal female
        case em           // speaker is younger; addressing older
        case chau         // speaker is much younger (kid → adult)
        case ban          // peer-to-peer neutral
        var id: String { rawValue }
    }
    enum Formality: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified, formal, neutral, casual
        var id: String { rawValue }
    }
    var dialect: Dialect = .unspecified
    var kinship: Kinship = .unspecified
    var formality: Formality = .unspecified
    /// Optional one-liner — e.g. "TikTok Shop seller addressing
    /// customer", "freelancer to JP client". Free-text; max 80 chars.
    var roleHint: String = ""
}
```

`SettingsStore.registerCard: RegisterCard?` — `nil` = disabled (existing behaviour preserved). Persisted as JSON in UserDefaults under `translator.registerCard`. **Codable migration**: not needed — new field, default `nil`, `decodeIfPresent`-style read.

**A.2 — Composition into prompts (Q1 → COMPOSE):**

Register Card is **prepended** to `customStyleInstruction` for every rewrite + outbound-translate call. The existing per-binding tone instruction stays unchanged. Composition lives in a new `RegisterCard.prompted(prefix:)` helper that renders a tight `vi`-language directive block. Empty/all-unspecified card → no-op (returns the original instruction unchanged).

**Example composed block** (when dialect=northern, kinship=chi, formality=formal, roleHint="seller → customer"):

```
[Register]
- Vietnamese register: Northern (Bắc) dialect; speaker addresses listener as "chị"; formality: formal.
- Context: seller → customer.
- Apply consistent kinship pronouns throughout. Match dialect-appropriate particles (Bắc preferred: "nhé"/"ạ"; avoid "nha"/"nhen").

[Tone]
<existing customStyleInstruction>
```

**A.3 — Injection sites** (3 places in `Providers/PromptBuilder.swift`):
1. `translateUserPrompt` (line 78ish) — outbound translate
2. `rewriteUserPrompt` single-variant (line 98ish)
3. `rewriteUserPrompt` multi-variant branch (line 129ish — v0.8.5)

Inbound `translateSelection` (.inbound direction) does NOT apply register — translation INTO user's language is a read flow.

**A.4 — Settings UI:**
- New subsection inside `SettingsWindowController.rewriteSection` titled "Vietnamese register card"
- Three `Picker` (`.menu` style) for dialect / kinship / formality
- One `TextField` for roleHint (placeholder: "e.g. seller → customer")
- "Reset" button → set to `nil` (disabled state)
- One-line composed-prompt preview using `.font(.caption)` for transparency

**A.5 — Edge cases:**
- All axes unspecified + empty roleHint → `prompted(prefix:)` returns the prefix unchanged (no register block emitted)
- Bắc + cháu → block renders "speaker is a kid addressing an adult"; tests pin this string
- Nam + em + formal → block emits Southern formality particles ("dạ" preferred over "ạ")
- roleHint truncated to 80 chars before injection

---

### B — Local-LLM Privacy mode (P0, sub-feature)

**B.1 — Provider classification:**

```swift
enum ProviderPrivacyClass: String, Sendable {
    case local      // text never leaves device
    case cloud      // direct user→3rd-party API
    case hosted     // user→1st-party backend (configurable; could be self-host)
}
```

| Provider | Class |
|---|---|
| Ollama | `.local` |
| Gemini CLI / Codex CLI (when configured against local model) | `.local` |
| Gemini direct, OpenAI-compatible, DeepL, Google Translate, LibreTranslate (default endpoint) | `.cloud` |
| Backend (translator-server proxy), Supabase-OTP SaaS | `.hosted` |

Computed via a new `TranslationProvider.privacyClass: ProviderPrivacyClass` protocol requirement (default `.cloud` for back-compat; each provider overrides).

**B.2 — Provider disclosure badge in HUD (Q3 → TYPE):**
- New label on `PreviewHUDView` next to the persona badge: `🛡 Local` / `☁ Cloud` / `🏢 Hosted` — text + colour-tinted background
- Full provider name (e.g. "Gemini Direct") via SwiftUI `.help()` tooltip
- Resolved eagerly into `TranslationStyle` / `Persona` at construction (R4 mitigation)

**B.3 — Settings "Privacy" section** (new section after Glossary):
- Status badge for the currently-active provider (large pill)
- When `.local`: ribbon "🛡 Local only — không gửi dữ liệu khách ra nước ngoài"
- When `.cloud`: ribbon "☁ Text is sent to <provider name>"
- When `.hosted`: ribbon "🏢 Text is sent to your configured backend"

**B.4 — Ollama onboarding card:**
- Collapsed-by-default disclosure group at the bottom of the Privacy section
- Expanded content: link to `https://ollama.com/download` + curated `ollama pull` commands as monospaced rows, each with a one-click "Copy command" button:
  ```
  ollama pull qwen2.5:7b-instruct      [Copy]
  ollama pull gemma3:4b-it             [Copy]
  ```
- Link to `https://ollama.com/library` ("Browse more models")
- One-click "Test Ollama connection" button → pings `SettingsStore.ollamaBaseURL` with a 2s timeout, shows ✅ or ❌ result inline

---

### C — Glossary v2-Lite (P0, sub-feature)

**C.1 — Data shape (Q2 → YES include `.alwaysTranslate`):**

```swift
struct GlossaryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: Sendable {
        case dontTranslate(term: String)
        case alias(from: String, to: String)
        case alwaysTranslate(term: String, to: String)
    }
    var id: UUID
    var kind: Kind
}
```

Codable persistence: encode as a tagged-enum JSON shape so adding `.scoped(...)` in v0.10.x is back-compat. Use `enum CodingKeys` + `decodeIfPresent` defaults.

`SettingsStore.glossaryEntries: [GlossaryEntry]` persisted in Keychain (same security posture as the existing `glossary: String` blob; new account name `glossary-entries-v2`).

**C.2 — Migration safety (R3 mitigation):**
- Existing `glossary: String` blob STAYS. Not auto-migrated, not modified.
- New `glossaryEntries` defaults to `[]` on fresh v0.10.0 launch (decode-or-default).
- Users who never open the new editor keep the legacy blob behaviour byte-identical to v0.9.x.

**C.3 — PromptBuilder integration:**
- Add `var structuredGlossary: String` accessor on `TranslationJob` that renders entries → text block. Empty entries → empty string.
- Compose in 3 sites: prepend structured block, then existing free-text blob.
- Cap at 50 entries (R6 + prompt-budget) — UI enforces, persistence allows more for future scoping but truncates at 50 during render.

**Example rendered block** (when entries are `dontTranslate("React") + alias("shopee" → "Shopee") + alwaysTranslate("freeship" → "free shipping")`):

```
Glossary rules (apply exactly):
- Don't translate: React
- Always rewrite: "shopee" → "Shopee"
- Always translate: "freeship" → "free shipping"

[Free-text glossary]
<existing glossary string blob, if non-empty>
```

**C.4 — Settings UI:**
- New row-based editor inside the existing `glossarySection`
- "Add entry" button → menu with 3 options (Don't translate / Alias / Always translate)
- Each row: type pill (read-only) + 1 or 2 TextFields + delete button
- Drag-to-reorder via SwiftUI `.onMove` (cosmetic; rendering order doesn't affect LLM behaviour but matches user mental model)
- Below the editor: collapsible "Legacy free-text glossary" disclosure with the existing TextEditor (so users can still see what's there)

**C.5 — File-size handling**: `SettingsWindowController` is at 779 LOC. Adding ~150 LOC for Register Card + ~200 for Glossary v2 + ~120 for Privacy section ≈ 1250 LOC. **Extract during P3/P5/P7**:
- `SettingsRegisterCardSection.swift` (new)
- `SettingsGlossarySection.swift` (new — moves the entire glossary section out, including the new editor)
- `SettingsPrivacySection.swift` (new)

Target: `SettingsWindowController.swift` returns to ≤ 600 LOC after extractions.

---

## 2. Out of Scope (explicit DEFER list)

| Item | Defer to | Reason |
|---|---|---|
| Per-binding register-card override toggle | v0.10.1 | Edge case; ship the compose default first, see if users ask |
| Glossary v2 scoped entries (`.language`, `.app`) | v0.11+ | Independent refactor; muddies cultural-precision narrative |
| Voice input (WhisperKit / Moonshine) | v0.11 | Dilutes anchor; needs its own permission + model-download UX budget |
| Conversation context (prior-message memory) | v1.0 | Needs storage + privacy model + history UI |
| Browser extension (Safari) | Never | Different security model; partially redundant with menu-bar AX path |
| CloudKit sync of glossary / settings | Never | Locks in iCloud assumption; undermines Privacy story |
| Document translate (PDF / Word) | Never | Wrong product shape; Easydict serves this |
| Dictionary lookup | Never | Easydict already won |
| OCR-rewrite flow | Never | Conceptually incoherent (rewrite implies authorship) |
| Auto-install Ollama or auto-pull models | Never | Subprocess + sandboxing minefield; user runs commands themselves |
| AI-Agent framing | Never | Concrete user-task primitives only |

---

## 3. Acceptance Criteria

### P0 — must-have, blocks ship

**Register Card:**
- **AC1** — `RegisterCard` model persists across launches (round-trips through UserDefaults JSON). Existing v0.9.x users see `nil` on first v0.10.0 launch (preserves current behaviour).
- **AC2** — When `registerCard != nil` and at least one axis is non-`.unspecified`, the composed prompt prepends a `[Register]` block to the existing instruction. When all axes are `.unspecified` AND `roleHint` is empty, no register block is emitted.
- **AC3** — Register injection fires for: outbound translate (`translateAndSend`), per-binding rewrite (`rewriteAndSend`), picker rewrite (`rewriteWithPickerAndSend`), App Intents rewrites (`RewriteWithToneIntent`, `RewriteWithPromptIntent`). Does NOT fire for inbound translate (`translateSelection`).
- **AC4** — Settings → Contextual rewrite shows a "Vietnamese register card" subsection with 3 dropdowns + roleHint TextField + Reset button. State syncs to `SettingsStore.registerCard` in real time.
- **AC5** — `RegisterCard.prompted(prefix:)` is pure (no side effects). Test pins rendered block for 4 representative axis combinations (Bắc/chị/formal, Nam/em/casual, all-unspecified+roleHint, mixed-unspecified).

**Local-LLM Privacy:**
- **AC6** — `TranslationProvider.privacyClass` protocol member added with default `.cloud`; Ollama returns `.local`, Backend / Supabase return `.hosted`. Every existing provider declares its class explicitly (no implicit fall-through).
- **AC7** — PreviewHUD shows a `🛡 Local` / `☁ Cloud` / `🏢 Hosted` badge next to the persona badge. Switching the active provider in Settings (Gemini → Ollama → Backend) and triggering a new translation reflects the new class on the next HUD render.
- **AC8** — Settings → Privacy section shows the current-provider class badge + ribbon copy. Updates reactively when `SettingsStore.directProvider` or `translationSource` changes.
- **AC9** — Ollama onboarding card renders the `ollama pull` commands as monospaced rows. Each row has a "Copy command" button that writes the exact string to `NSPasteboard.general`.
- **AC10** — "Test Ollama connection" button pings `ollamaBaseURL` with a 2s timeout; shows ✅ on 2xx, ❌ + reason on error. No app crash on timeout/refused-connection.

**Glossary v2-Lite:**
- **AC11** — `GlossaryEntry` Codable round-trip preserves every entry kind (`.dontTranslate`, `.alias`, `.alwaysTranslate`). `decodeIfPresent` handles missing fields; unknown future kinds decoded as `nil` (forward-compat skip rather than crash).
- **AC12** — Existing `glossary: String` blob unchanged for any user who doesn't open the new editor. Adding/removing entries via the editor does NOT touch the blob.
- **AC13** — PromptBuilder renders the structured `Glossary rules:` block BEFORE the legacy free-text blob in all 3 injection sites. Empty entries → only the legacy blob is rendered (current v0.9.x behaviour preserved).
- **AC14** — Glossary v2 entries are passed to every LLM-class provider (Gemini direct/CLI, OpenAI-compat, Ollama, Codex CLI, Backend, Supabase-hosted). NOT passed to DeepL / Google Translate / LibreTranslate (those providers ignore `TranslationJob.glossary` today — verify and document).
- **AC15** — Settings → Glossary section shows an editor for the new entries (row-based, "Add entry" menu, type pill, 1-2 TextFields per row, delete button). Legacy free-text editor remains in a collapsed disclosure below.

**Backward-compat:**
- **AC16** — All 319 existing tests pass unchanged.
- **AC17** — Codable contracts preserved: `RewriteBinding` / `HotkeyConfig` / `TranslationStyle` / `SaaSConfig` / existing `glossary: String` storage all decode v0.9.x JSON without migration prompts.
- **AC18** — Sparkle OTA from v0.6.1+ upgrades to v0.10.0 with no manual user action.

### P1 — should-have, can patch in v0.10.1 if blocked

- **AC19** — Register Card has a "Reset" button that clears all axes to `.unspecified` and empties `roleHint`.
- **AC20** — Settings shows a one-line composed-prompt preview ("Sample prompt: '[Register] Northern dialect, address as chị, formal…' ") so users see what the LLM will receive.
- **AC21** — Ollama onboarding card has "Copy command" button per row + a "Browse more models" link to `https://ollama.com/library`.
- **AC22** — Glossary v2 entries support drag-to-reorder via SwiftUI `.onMove`.
- **AC23** — `RegisterCard.prompted(...)` test suite covers ≥ 8 axis combinations (4 P0 + 4 P1 edge cases incl. roleHint-only, all-unspecified, dialect-only, kinship-only).
- **AC24** — At least 15 new tests across v0.10.0 (RegisterCard composition, GlossaryEntry Codable migration, GlossaryEntry → prompt rendering, provider privacyClass classification).
- **AC25** — What's-New window adds v0.10.0 highlights (3 cards: Register Card, Privacy badge, Glossary v2).

### P2 — stretch, defer freely

- **AC26** — Register Card per-axis "ignore" toggle (so user can pick dialect but explicitly leave kinship unspecified vs. unspecified-by-default).
- **AC27** — Settings Privacy section "What does this mean?" expandable explainer for each class with PDPL 2025 reference.
- **AC28** — Composed-prompt preview updates live as the user changes axes.

---

## 4. Constraints

### Hard constraints (cannot violate)

- **Swift 6 strict concurrency** — all new types `Sendable` or `@MainActor`. `RegisterCard` + `GlossaryEntry` are value types, naturally `Sendable`.
- **macOS 14 minimum** preserved.
- **LSUIElement = true** preserved.
- **Zero break** to: Sparkle OTA channel, `RewriteBinding` / `HotkeyConfig` / `TranslationStyle` / `SaaSConfig` Codable contracts, 7+1 RewriteTone cases, expressive-tones toggle, multi-variant toggle, captureHotkey, existing `glossary: String` blob.
- **No new SPM dependencies** — model is data, UI is SwiftUI, prompt-injection is string composition.
- **No file > 800 LOC** — triggers `SettingsWindowController` extraction during P3 / P5 / P7 into 3 new section files.
- **Test contract: 319 → 335+ tests stay GREEN** through every commit.

### Reuse mandates (don't reinvent)

- `PromptBuilder` for prompt composition (don't bypass)
- `RewriteService` (v0.9.1) for headless paths — Register Card / Glossary v2 must apply via the same code path
- `RewriteResultProcessor.clean` + refusal-retry chain unchanged
- `SettingsBindingRows` pattern for extracted Settings sections
- `KeychainCredentialStore` for glossary v2 entries (mirror existing glossary blob path)
- `HotkeyRecorderSheet` pattern NOT applicable (no new hotkeys in v0.10.0)
- `ClipboardService.writeString` for the "Copy command" buttons

### Test mandates

- Pure-function tests for `RegisterCard.prompted(prefix:)` — no AppKit, no SwiftUI.
- Pure-function tests for `GlossaryEntry` Codable round-trip + future-compat decode.
- Pure-function tests for `TranslationJob.structuredGlossary` rendering.
- `ProviderPrivacyClass` classification test parameterised over every concrete provider.
- Integration smoke: spawn a real Ollama request through the workflow with a registerCard set + verify the prompt body contains the [Register] block (use the existing URLSession test infrastructure).

---

## 5. Phased Build Plan

Each phase is independently shippable (build green, tests green, smoke-launches). Phase order optimised so the most-risky probes (R1 register-prompt verbosity, R2 refusal-rate) land early.

| Phase | Scope | Acceptance | LOC est. |
|---|---|---|---|
| **P1 — RegisterCard data model + Codable tests** | `RegisterCard.swift` (new) with the 3 enums + struct + `prompted(prefix:)` helper. SettingsStore.registerCard: RegisterCard? + JSON persist. 8+ pure tests covering axis combos + roleHint truncation. | AC1, AC5, AC23. 327+ tests GREEN. | ~250 |
| **P2 — Register injection into PromptBuilder + R1/R2 spike** | Update PromptBuilder 3 sites to compose register block before existing instruction. Manual smoke: 5 sample inputs against Gemini + Ollama with register-on vs register-off, compare outputs for verbosity + refusal-rate. Decision gate — if refusal rate >10pp higher, bail back to register-on-rewrite-only (not outbound translate). | AC2, AC3 manual. R1+R2 verdict recorded. | ~80 |
| **P3 — Register Card Settings UI + extract section** | `SettingsRegisterCardSection.swift` (new file). 3 Pickers + roleHint TextField + Reset button + 1-line preview. Wire into `rewriteSection`. SettingsWindowController stays <800 LOC via the extraction. | AC4, AC19, AC20. | ~200 (net: −0 SettingsWindowController due to extraction) |
| **P4 — GlossaryEntry data model + Codable migration + tests** | `GlossaryEntry.swift` (new) with tagged-enum Codable. SettingsStore.glossaryEntries: [GlossaryEntry] in Keychain. Verify existing `glossary: String` blob untouched. 6+ tests for round-trip + legacy decode + unknown-kind future-compat skip. | AC11, AC12. 333+ tests GREEN. | ~250 |
| **P5 — Glossary v2 Settings UI editor + extract section** | `SettingsGlossarySection.swift` (new file) — moves the whole Glossary section out of SettingsWindowController. Row-based editor + Add menu + collapsed legacy disclosure. `.onMove` reordering (P1). | AC15, AC22. SettingsWindowController shrinks. | ~250 (net: ~+100 in new file, ~-150 out of SettingsWindowController) |
| **P6 — GlossaryEntry PromptBuilder integration + tests** | `TranslationJob.structuredGlossary` accessor + injection in 3 PromptBuilder sites. 50-entry cap. 4 tests for rendering each entry kind + cap behaviour + empty-entries no-op. | AC13, AC14. 339+ tests GREEN. | ~150 |
| **P7 — Local-LLM Privacy badges + Ollama onboarding + extract Privacy section** | `TranslationProvider.privacyClass` protocol member + 10 provider overrides. PreviewHUD badge + tooltip. `SettingsPrivacySection.swift` (new) — provider class ribbon + Ollama onboarding card + test-connection button. Persona / TranslationStyle eagerly carries the class. | AC6, AC7, AC8, AC9, AC10, AC21, AC24. 345+ tests GREEN. | ~350 (net incl. extraction) |
| **P8 — Ship pipeline** | Bump 0.9.2 → 0.10.0 (build 29) in 3 scripts. CHANGELOG [0.10.0] section. What's-New highlights catalogue (AC25). DMG signed+notarized+stapled. Sparkle zip signed+notarized+stapled. Appcast entry. Commit + tag v0.10.0 + push + `gh release create v0.10.0 --latest`. Verify Pages serve. | AC18 verified. | N/A |

**Total estimated work**: ~1530 LOC + tests + ship pipeline. ~30% larger than v0.9.0 (which was ~1230 LOC); largest single release this year.

---

## 6. Risk Register

| # | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| **R1** | Register Card prompt block makes the LLM verbose / breaks existing tone outputs | HIGH | MED | P2 manual smoke — 5 inputs × every tone, register-on vs register-off, compare. If degradation visible, gate register block by tone (e.g. don't apply to Concise). Decision recorded in P2 commit message. |
| **R2** | Extra register instructions raise refusal rate in `RewriteResultProcessor.isLikelyRefusal` | HIGH | LOW | P2 spike logs refusal rate on dev build. If >10pp higher than baseline, scope register-injection to rewrite paths only (skip outbound translate). |
| **R3** | Glossary v2 migration accidentally drops user's existing string blob | MED | MED | Keep blob alongside entries (never auto-migrate). AC12 test pins blob preservation. Settings UI shows the legacy editor in a collapsed disclosure so users see it's still there. |
| **R4** | Provider disclosure badge reads `providerFactory()` synchronously on every HUD render | MED | LOW | Resolve `ProviderPrivacyClass` eagerly into `TranslationStyle.privacyClass` (new field) at construction time. HUD reads from style, no closure capture, no per-render provider resolution. |
| **R5** | Curated Ollama model names (`qwen2.5:7b-instruct`, `gemma3:4b-it`) might be renamed in the Ollama registry | LOW | MED | Card text: "These are suggestions — browse all models at ollama.com/library". Test-connection ping doesn't care about model name. |
| **R6** | Register Card axis combinatorial explosion paralyses users | LOW | LOW | Ship with exactly 3 axes + 1 free-text. Each defaults to `.unspecified`. Resist any v0.10.x asks to add more axes until v0.10.2+ feedback. |
| **R7** | `SettingsWindowController` accidentally crosses 800 LOC if extractions are skipped | MED | MED | Run `wc -l` after every commit on P3, P5, P7. If approaching 800, force the extraction inline. |
| **R8** | What's-New v0.10.0 highlights catalogue gets out-of-sync with shipped features | LOW | MED | P8 explicitly checks the highlights list against AC1-AC15 surface. Single-source-of-truth catalogue in `WhatsNewWindowController.swift`. |
| **R9** | DeepL / Google Translate / LibreTranslate IGNORE the structured glossary block — user sets entries thinking they're applied everywhere | MED | HIGH | AC14 documents this explicitly. UI: when active provider is one of these 3, show a small "These providers don't apply glossary rules" note in the Glossary section. |
| **R10** | Sparkle channel break — adding `RegisterCard` UserDefaults key + `glossaryEntries` Keychain account might surprise old users | LOW | LOW | Default `nil` / `[]` for new fields; existing keys untouched. Verified via the Codable migration tests in P1 + P4. |

---

## 7. Definition of Done

- [ ] All P0 ACs (AC1–AC18) pass manual + automated verification
- [ ] At least 5 of 7 P1 ACs (AC19–AC25) ship; documented carry-over for any deferred
- [ ] **335+ Swift tests / 71+ suites GREEN** (319 existing + ~16 new from P1/P4/P6/P7)
- [ ] Build clean (`swift build`, zero warnings, Swift 6 strict concurrency)
- [ ] App launches; Settings → Contextual Rewrite shows Register Card panel; Settings → Glossary shows v2 entry editor; Settings → Privacy shows class ribbon; HUD shows Privacy badge in real-time as user switches providers
- [ ] R1 + R2 spike results recorded in P2 commit (no qualitative degradation observed; refusal rate within 10pp of baseline)
- [ ] `SettingsWindowController.swift` ≤ 600 LOC after P3/P5/P7 extractions
- [ ] DMG signed (Developer ID) + notarized + stapled; Sparkle zip signed + notarized + stapled
- [ ] Appcast updated with v0.10.0 entry (EdDSA signature, length, sparkle:version=29)
- [ ] CHANGELOG [0.10.0] section written
- [ ] `git tag v0.10.0` + push + `gh release create v0.10.0 --latest` published
- [ ] Sparkle OTA upgrade v0.9.2 → v0.10.0 succeeds (manual smoke or documented as deferred)
- [ ] What's-New window pops on first v0.10.0 launch with 3 highlight cards

---

## 8. Open questions — settled in this define

| Q | Decision | Rationale |
|---|---|---|
| Q1 — Register Card override binding instruction, or compose? | **Compose** | Safer for users who already tuned bindings; per-binding override defers to v0.10.1 |
| Q2 — Include `.alwaysTranslate` as 3rd glossary entry type? | **Yes** | Cheap (~30 LOC), completes the table conceptually, no test debt |
| Q3 — Provider disclosure badge: name or type? | **Type by default, name on hover** | Less leaky in screen-share; name still accessible via `.help()` tooltip |
| Q4 — What's-New copy? | *"v0.10.0 hiểu xưng hô — anh/chị/em, Bắc/Nam, formal/chat. Và không gửi dữ liệu khách ra nước ngoài khi dùng local mode."* | Settled; lock into `WhatsNewWindowController.v0_10_0Highlights` |

---

## TL;DR

Anchor **v0.10.0 = Cultural Precision & Privacy** = Register Card + Local-LLM Privacy badges + Glossary v2-Lite. ~1530 LOC across 8 phases, R1/R2 spike gate at P2. Defer voice / browser ext / CloudKit / per-binding override / scoped glossary. 28 ACs (18 P0 + 7 P1 + 3 P2). Sparkle OTA upgrade path preserved; 319-test contract preserved.
