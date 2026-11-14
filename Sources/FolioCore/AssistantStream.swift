import Foundation

/// Rebuilds Anthropic Messages content blocks from server-sent events and reports text as it arrives.
public struct AssistantStreamAccumulator {
    public private(set) var blocks: [[String: Any]] = []
    public private(set) var stopReason: String?
    private var partialJSON: [Int: String] = [:]
    private let onText: @Sendable (String) -> Void
    private let separator: String
    private var announcedText = false

    public init(onText: @escaping @Sendable (String) -> Void, separator: String = "") { self.onText = onText; self.separator = separator }

    public mutating func feed(_ line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return }
        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], let type = event["type"] as? String else {
            throw AssistantError.message("Claude returned an unreadable response.")
        }
        switch type {
        case "error":
            let kind = (event["error"] as? [String: Any])?["type"] as? String
            throw AssistantError.message(kind == "overloaded_error" ? "Claude is overloaded. Try again shortly." : kind == "rate_limit_error" ? "Claude is rate limited. Try again later." : "Claude stopped before finishing. Try again.")
        case "content_block_start":
            guard let index = event["index"] as? Int, index == blocks.count, var block = event["content_block"] as? [String: Any] else { throw AssistantError.message("Claude returned an unreadable response.") }
            if block["type"] as? String == "text" {
                let text = block["text"] as? String ?? ""; block["text"] = text
                if !text.isEmpty { emit(text) }
            }
            if block["type"] as? String == "tool_use" { block["input"] = [String: Any](); partialJSON[index] = "" }
            blocks.append(block)
        case "content_block_delta":
            guard let index = event["index"] as? Int, blocks.indices.contains(index), let delta = event["delta"] as? [String: Any], let kind = delta["type"] as? String else { return }
            switch kind {
            case "text_delta":
                let text = delta["text"] as? String ?? ""
                blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + text; emit(text)
            case "input_json_delta": partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
            case "thinking_delta": blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta": blocks[index]["signature"] = (blocks[index]["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            case "citations_delta":
                if let citation = delta["citation"] as? [String: Any] { blocks[index]["citations"] = (blocks[index]["citations"] as? [[String: Any]] ?? []) + [citation] }
            default: break
            }
        case "content_block_stop":
            if let index = event["index"] as? Int, let json = partialJSON.removeValue(forKey: index), blocks.indices.contains(index) {
                if json.isEmpty { blocks[index]["input"] = [String: Any]() }
                else if let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { blocks[index]["input"] = value }
                else { throw AssistantError.message("Claude returned an unreadable response.") }
            }
        case "message_delta":
            if let delta = event["delta"] as? [String: Any], let stop = delta["stop_reason"] as? String { stopReason = stop }
        default: break
        }
    }
    private mutating func emit(_ text: String) {
        if !announcedText { announcedText = true; if !separator.isEmpty { onText(separator) } }
        onText(text)
    }
}
