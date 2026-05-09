import Foundation

/// Update emitted by a streaming translation. Mirrors server SSE frames
/// (`{"chunk": "..."}` and `{"done": true, "translation": "..."}`).
enum StreamingTranslationUpdate: Sendable {
    /// Partial translation chunk. The cumulative translation is the
    /// concatenation of all `chunk` updates received so far.
    case chunk(String)

    /// Terminal frame — provider finished. `translation` is the assembled
    /// final text (matches the join of all preceding chunks, but providers
    /// may post-process so prefer this value for the final HUD update).
    case done(translation: String, provider: String)
}

/// Optional capability for providers that can stream partial chunks of
/// the translation. Inbound workflow uses this when available so the HUD
/// can show progressive text.
@MainActor
protocol StreamingTranslationProvider: TranslationProvider {
    /// Emit `StreamingTranslationUpdate`s in order. Throws on error
    /// before any chunk has been read; mid-stream errors propagate via
    /// the AsyncStream's continuation `finish(throwing:)`.
    func translateStreaming(_ job: TranslationJob) -> AsyncThrowingStream<StreamingTranslationUpdate, Error>
}
