import Foundation

/// v0.10.0 — typed glossary entry (Theme B Lite).
///
/// Three kinds cover the high-value cases the v0.9.x free-text blob
/// can't express cleanly: brand names that must survive translation
/// (`dontTranslate`), casing/spelling normalisations (`alias`), and
/// jargon that must be translated even when the model would otherwise
/// pass it through (`alwaysTranslate`).
///
/// Scoped entries (per-language, per-app) are deliberately deferred to
/// v0.11+ per `docs/v0.10.0/define.md` §2. The tagged-enum Codable
/// shape below is forward-compatible: a future `.scoped(...)` kind
/// can be added as a new `KindTag` raw value and old builds will
/// fail-closed on decode (`SettingsStore.glossaryEntries` falls back
/// to `[]` rather than crashing — see `SettingsStore.init`).
struct GlossaryEntry: Equatable, Hashable, Identifiable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        /// Brand names, code identifiers, product names — the model
        /// should leave the term intact in every output language.
        case dontTranslate(term: String)
        /// Casing / spelling normalisation: when the input contains
        /// `from`, replace with `to` in the output. Useful for
        /// "shopee" → "Shopee", "tiktok shop" → "TikTok Shop".
        case alias(from: String, to: String)
        /// Domain jargon: when the input contains `term`, the model
        /// MUST translate it to `to`. Useful when the model would
        /// otherwise leave a borrowed loanword in the source language.
        case alwaysTranslate(term: String, to: String)
    }

    let id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

// MARK: - Codable (tagged-enum shape)

extension GlossaryEntry: Codable {
    /// Stable strings on disk. New kinds in v0.10.x add new cases here;
    /// old builds that don't recognise the raw value throw
    /// `DecodingError` from `KindTag.init(rawValue:)`, which the
    /// SettingsStore load catches by falling back to `[]` for the whole
    /// list. Strict fail-closed beats silent data loss.
    enum KindTag: String, Codable {
        case dontTranslate
        case alias
        case alwaysTranslate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        // Payload fields. Not every kind uses all of them; absent
        // fields decode as missing-key errors which we surface to the
        // outer fail-closed.
        case term
        case from
        case to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        let tag = try c.decode(KindTag.self, forKey: .kind)
        switch tag {
        case .dontTranslate:
            self.kind = .dontTranslate(
                term: try c.decode(String.self, forKey: .term)
            )
        case .alias:
            self.kind = .alias(
                from: try c.decode(String.self, forKey: .from),
                to: try c.decode(String.self, forKey: .to)
            )
        case .alwaysTranslate:
            self.kind = .alwaysTranslate(
                term: try c.decode(String.self, forKey: .term),
                to: try c.decode(String.self, forKey: .to)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch kind {
        case .dontTranslate(let term):
            try c.encode(KindTag.dontTranslate, forKey: .kind)
            try c.encode(term, forKey: .term)
        case .alias(let from, let to):
            try c.encode(KindTag.alias, forKey: .kind)
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
        case .alwaysTranslate(let term, let to):
            try c.encode(KindTag.alwaysTranslate, forKey: .kind)
            try c.encode(term, forKey: .term)
            try c.encode(to, forKey: .to)
        }
    }
}

// MARK: - Display

extension GlossaryEntry {
    /// Short label for the editor row's type pill.
    var kindLabel: String {
        switch kind {
        case .dontTranslate:    return "Don't translate"
        case .alias:            return "Alias"
        case .alwaysTranslate:  return "Always translate"
        }
    }

    /// Primary term shown in the row's main TextField (the term the
    /// user is configuring a rule for).
    var primaryTerm: String {
        switch kind {
        case .dontTranslate(let term):       return term
        case .alias(let from, _):             return from
        case .alwaysTranslate(let term, _):   return term
        }
    }

    /// Secondary value shown in the second TextField. Empty for
    /// `.dontTranslate` which only carries one field.
    var secondaryValue: String {
        switch kind {
        case .dontTranslate:                  return ""
        case .alias(_, let to):                return to
        case .alwaysTranslate(_, let to):      return to
        }
    }
}
