import Foundation

/// Best-effort extractor for the wide variety of stdout shapes the
/// `gemini` and `codex` CLIs emit. Mirrors Python `extract_cli_text`.
///
/// Strategy:
/// 1. If stdout parses as JSON, look for known text-bearing keys.
/// 2. If JSON has `candidates[].content.parts[].text` (Gemini shape),
///    concatenate.
/// 3. Otherwise return the raw stdout (some CLIs emit plain text).
enum CLIOutputExtractor {
    private static let textKeys = ["response", "text", "content", "output", "result"]

    static func extractText(from stdout: String) -> String? {
        let raw = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else {
            return raw
        }

        if let dict = parsed as? [String: Any] {
            for key in textKeys {
                if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    return value
                }
            }
            if let candidates = dict["candidates"] as? [[String: Any]] {
                for candidate in candidates {
                    if let content = candidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        let combined = parts.compactMap { $0["text"] as? String }.joined()
                        if !combined.trimmingCharacters(in: .whitespaces).isEmpty {
                            return combined
                        }
                    }
                }
            }
        } else if let array = parsed as? [Any] {
            for item in array.reversed() {
                if let dict = item as? [String: Any],
                   let serialized = try? JSONSerialization.data(withJSONObject: dict),
                   let asString = String(data: serialized, encoding: .utf8),
                   let text = extractText(from: asString) {
                    return text
                }
            }
        }
        return nil
    }
}
