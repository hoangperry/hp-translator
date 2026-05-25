import Foundation

/// Vietnamese social-register configuration (v0.10.0). The card is
/// composed into rewrite + outbound-translate prompts as a tight
/// [Register] block before the existing per-binding tone instruction.
/// `nil` (or all-axes-unspecified + empty roleHint) → no-op; the prompt
/// flows through unchanged so v0.9.x behaviour is byte-identical for
/// users who never open the new Settings panel.
///
/// Axes deliberately limited to 3 + one free-text hint. The v0.10.0
/// research (`docs/v0.10.0/research.md`) flagged combinatorial-axis
/// paralysis as R6 — resist any v0.10.x asks to add more dimensions
/// until v0.10.2+ user feedback. Apple Intelligence cannot replicate
/// these locale-aware nuances; that gap is the anchor moat.
struct RegisterCard: Codable, Equatable, Hashable, Sendable {

    /// Northern (Hanoi-region) vs Southern (Saigon-region) Vietnamese.
    /// Affects particle preference (Bắc: "nhé"/"ạ"; Nam: "nha"/"nhen")
    /// and minor vocabulary differences. `.unspecified` lets the model
    /// pick whatever fits the input.
    enum Dialect: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified
        case northern
        case southern

        var id: String { rawValue }

        /// Display label for the Settings Picker UI.
        var displayName: String {
            switch self {
            case .unspecified: return "Không chỉ định"
            case .northern:    return "Bắc (Hà Nội)"
            case .southern:    return "Nam (Sài Gòn)"
            }
        }

        /// Phrase injected into the prompt block. Empty for
        /// `.unspecified` so no instruction noise is added.
        var promptPhrase: String {
            switch self {
            case .unspecified: return ""
            case .northern:    return "Northern (Bắc) dialect; prefer particles such as \"nhé\", \"ạ\"; avoid \"nha\"/\"nhen\""
            case .southern:    return "Southern (Nam) dialect; prefer particles such as \"nha\", \"nhen\", \"dạ\"; \"ạ\" is acceptable but secondary"
            }
        }
    }

    /// Kinship-pronoun pairing the speaker uses to address the listener.
    /// Vietnamese pronouns encode the relative-age + relative-status
    /// relationship — getting this wrong is the #1 way a rewrite
    /// sounds insulting even when the words are technically correct.
    enum Kinship: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified
        case anh    // listener is younger / equal male
        case chi    // listener is younger / equal female
        case em     // speaker is younger; addressing older (or same gen)
        case chau   // speaker is much younger (kid → adult, junior → senior)
        case ban    // peer-to-peer neutral (no age hierarchy)

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .unspecified: return "Không chỉ định"
            case .anh:         return "Anh (gọi nam ngang/nhỏ tuổi)"
            case .chi:         return "Chị (gọi nữ ngang/nhỏ tuổi)"
            case .em:          return "Em (người nói nhỏ hơn người nghe)"
            case .chau:        return "Cháu (người nói rất nhỏ — trẻ con / nhân viên mới)"
            case .ban:         return "Bạn (ngang hàng, trung tính)"
            }
        }

        var promptPhrase: String {
            switch self {
            case .unspecified: return ""
            case .anh:
                return "speaker addresses the listener as \"anh\" (listener is a younger/equal male)"
            case .chi:
                return "speaker addresses the listener as \"chị\" (listener is a younger/equal female)"
            case .em:
                return "speaker is younger; address the listener using older-tier pronouns (\"anh\"/\"chị\"); refer to self as \"em\""
            case .chau:
                return "speaker is much younger than the listener (kid-to-adult or junior-to-senior context); refer to self as \"cháu\""
            case .ban:
                return "peer-to-peer neutral; use \"bạn\" with no age hierarchy; avoid \"anh\"/\"chị\"/\"em\""
            }
        }
    }

    /// Register formality level. Modulates particle frequency,
    /// abbreviation tolerance, and sentence shape.
    enum Formality: String, Codable, CaseIterable, Identifiable, Sendable {
        case unspecified
        case formal     // business / customer-service / superior context
        case neutral    // professional peer
        case casual     // friend / informal chat

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .unspecified: return "Không chỉ định"
            case .formal:      return "Formal (khách hàng / sếp)"
            case .neutral:     return "Neutral (đồng nghiệp)"
            case .casual:      return "Casual (bạn bè / chat thường)"
            }
        }

        var promptPhrase: String {
            switch self {
            case .unspecified: return ""
            case .formal:
                return "formality: formal — full politeness particles, no slang, complete sentences"
            case .neutral:
                return "formality: neutral — professional peer register, concise but courteous"
            case .casual:
                return "formality: casual — relaxed, abbreviations acceptable, friendly particles welcome"
            }
        }
    }

    /// Max length of `roleHint` injected into the prompt. Longer hints
    /// are truncated at this boundary before injection — keeps prompt
    /// budget bounded and prevents accidental long-form instructions
    /// from leaking into the register block.
    static let roleHintMaxLength = 80

    var dialect: Dialect
    var kinship: Kinship
    var formality: Formality
    /// Optional one-liner context — e.g. "TikTok Shop seller addressing
    /// customer", "freelancer to JP client". Free-text. Truncated to
    /// `roleHintMaxLength` characters before prompt injection.
    var roleHint: String

    init(
        dialect: Dialect = .unspecified,
        kinship: Kinship = .unspecified,
        formality: Formality = .unspecified,
        roleHint: String = ""
    ) {
        self.dialect = dialect
        self.kinship = kinship
        self.formality = formality
        self.roleHint = roleHint
    }

    /// `true` when at least one axis carries a non-`.unspecified` value
    /// OR roleHint is non-empty. Drives the prompt-composition no-op
    /// gate: a fully-blank card returns the prefix unchanged.
    var isActive: Bool {
        dialect != .unspecified
            || kinship != .unspecified
            || formality != .unspecified
            || !roleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Render the register block + prepend it to `prefix` (the existing
    /// `customStyleInstruction`). When the card is inactive, returns
    /// `prefix` unchanged.
    ///
    /// Output shape:
    /// ```
    /// [Register]
    /// - Vietnamese register: <dialect>; <kinship>; <formality>.
    /// - Context: <roleHint>.
    /// - Apply consistent kinship pronouns throughout. Match dialect-
    ///   appropriate particles.
    ///
    /// [Tone]
    /// <prefix>
    /// ```
    func prompted(prefix: String) -> String {
        guard isActive else { return prefix }

        var fragments: [String] = []
        let dialectPhrase = dialect.promptPhrase
        let kinshipPhrase = kinship.promptPhrase
        let formalityPhrase = formality.promptPhrase
        let trimmedHint = roleHint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.roleHintMaxLength)

        if !dialectPhrase.isEmpty { fragments.append(dialectPhrase) }
        if !kinshipPhrase.isEmpty { fragments.append(kinshipPhrase) }
        if !formalityPhrase.isEmpty { fragments.append(formalityPhrase) }

        var lines: [String] = ["[Register]"]
        if !fragments.isEmpty {
            lines.append("- Vietnamese register: " + fragments.joined(separator: "; ") + ".")
        }
        if !trimmedHint.isEmpty {
            lines.append("- Context: \(trimmedHint).")
        }
        lines.append(
            "- Apply consistent kinship pronouns throughout. Match dialect-appropriate particles."
        )
        lines.append("")
        lines.append("[Tone]")

        // Don't append an empty prefix on its own line — keeps the
        // composed prompt tight when the caller's instruction is "".
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrefix.isEmpty {
            lines.append(prefix)
        }

        return lines.joined(separator: "\n")
    }
}
