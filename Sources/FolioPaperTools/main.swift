import Foundation
import FolioCore

// Private MCP subprocess. The sole file is chosen by Folio before the provider starts.
func serve() throws {
    guard CommandLine.arguments.count == 2 else { throw PaperLookup.LookupError.invalid }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: PaperLookup.maximumBytes + 200_000) ?? Data()
    guard data.count < PaperLookup.maximumBytes + 200_000 else { throw PaperLookup.LookupError.invalid }
    let decoded = try JSONDecoder().decode(PaperLookup.self, from: data)
    let paper = try PaperLookup(pages: decoded.pages, truncated: decoded.truncated)
    var buffer = Data(), received = 0, calls = 0
    func reply(_ object: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: object) else { return }
        FileHandle.standardOutput.write(bytes)
        FileHandle.standardOutput.write(Data([10]))
    }
    while true {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { break }
        received += chunk.count
        guard received <= 128_000 else { return }
        buffer.append(chunk)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end)
            buffer.removeSubrange(...end)
            guard !line.isEmpty else { continue }
            guard let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                reply(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON"]]); continue
            }
            guard let id = request["id"] else { continue }
            let method = request["method"] as? String ?? ""
            var result: [String: Any]
            switch method {
            case "initialize": result = ["protocolVersion": "2024-11-05", "capabilities": ["tools": [:]], "serverInfo": ["name": "folio_paper", "version": "1.0.0"]]
            case "ping": result = [:]
            case "tools/list": result = ["tools": PaperLookup.tools.map { tool -> [String: Any] in
                var annotated = tool
                annotated["annotations"] = ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]
                return annotated
            }]
            case "tools/call":
                calls += 1
                let params = request["params"] as? [String: Any] ?? [:]
                let value = calls > 12 ? ["error": "Paper lookup limit reached. Answer from evidence already retrieved."] : paper.call(params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])
                let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                result = ["content": [["type": "text", "text": String(decoding: encoded, as: UTF8.self)]]]
                if value["error"] != nil { result["isError"] = true }
            default:
                reply(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not supported"]]); continue
            }
            reply(["jsonrpc": "2.0", "id": id, "result": result])
        }
    }
}

do { try serve() } catch { exit(1) }
