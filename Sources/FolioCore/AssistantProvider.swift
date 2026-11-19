import Foundation
import Darwin

public struct AssistantRequest {
    public let system: String
    public let messages: [AssistantTurn]
    public let paper: AssistantPaper
    public let structured: Bool
    public let research: Bool
    public init(system: String, messages: [AssistantTurn], paper: AssistantPaper, structured: Bool = false, research: Bool = false) {
        self.system = system; self.messages = messages; self.paper = paper; self.structured = structured; self.research = research
    }
}

public protocol AssistantTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int)
    /// Server-sent-event lines of a streaming response, after the HTTP status is known.
    func stream(_ request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>)
}
public extension AssistantTransport {
    /// Fallback for transports without native streaming: replays the buffered body line by line.
    func stream(_ request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>) {
        let (data, status) = try await send(request)
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        return (status, AsyncThrowingStream { continuation in lines.forEach { continuation.yield($0) }; continuation.finish() })
    }
}
public struct AssistantHTTPTransport: AssistantTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180; configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4_000_000 else { throw AssistantError.message("The provider response exceeded the local size limit.") }
            data.append(byte)
        }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    public func stream(_ request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180; configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        let bytes: URLSession.AsyncBytes; let response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) } catch { session.invalidateAndCancel(); throw error }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, AsyncThrowingStream { continuation in
            let task = Task {
                defer { session.invalidateAndCancel() }
                var total = 0
                do {
                    for try await line in bytes.lines {
                        total += line.utf8.count
                        guard total < 4_000_000 else { throw AssistantError.message("The provider response exceeded the local size limit.") }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        })
    }
}

public protocol AssistantProcessRunning {
    func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data, allowResearch: Bool) async throws -> Data
}

/// Each invocation owns its process, pipes and cancellation, with bounded output and a hard timeout.
public struct AssistantProcessRunner: AssistantProcessRunning {
    public init() {}
    public func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data, allowResearch: Bool) async throws -> Data {
        let capture = AssistantProcessCapture(allowResearch: allowResearch)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                capture.start(executable: executable, arguments: arguments, environment: environment, directory: directory, input: input, continuation: continuation)
            }
        } onCancel: { capture.cancel() }
    }
}

private final class AssistantProcessCapture: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let process = Process()
    private let output = Pipe(), errors = Pipe(), input = Pipe()
    private let allowResearch: Bool
    private var continuation: CheckedContinuation<Data, Error>?
    private var stdout = Data(), pending = Data(), stderr = Data()
    private var finished = false, started = false, ended = false, outputEOF = false, errorEOF = false, cancelled = false
    private var failure: Error?
    private var toolIDs = Set<String>()
    private var timeout: DispatchWorkItem?
    init(allowResearch: Bool) { self.allowResearch = allowResearch }

    func start(executable: URL, arguments: [String], environment: [String: String], directory: URL, input bytes: Data, continuation: CheckedContinuation<Data, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
        guard !cancelled else { finish(.failure(CancellationError())); return }
        process.executableURL = executable; process.arguments = arguments; process.environment = environment; process.currentDirectoryURL = directory
        process.standardOutput = output; process.standardError = errors; process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.read(handle, isError: false) }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.read(handle, isError: true) }
        process.terminationHandler = { [weak self] _ in self?.terminated() }
        do { try process.run(); started = true }
        catch { finish(.failure(AssistantError.message("Codex CLI could not start. Install it, run codex login, or set FOLIO_CODEX_CLI."))); return }
        let timer = DispatchWorkItem { [weak self] in self?.stop(AssistantError.message("Codex exceeded the three-minute request limit. Try again.")) }
        timeout = timer; DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timer)
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            try? self.input.fileHandleForWriting.write(contentsOf: bytes)
            try? self.input.fileHandleForWriting.close()
        }
    }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true; stop(CancellationError()) }
    private func read(_ handle: FileHandle, isError: Bool) {
        let data = handle.availableData
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if data.isEmpty {
            handle.readabilityHandler = nil
            if isError { errorEOF = true } else { outputEOF = true; validateLine(pending); pending.removeAll() }
            completeIfReady(); return
        }
        if isError { stderr.append(data); if stderr.count > 4000 { stderr = Data(stderr.suffix(4000)) }; return }
        guard stdout.count + data.count <= 4_000_000 else { stop(AssistantError.message("Codex exceeded the local response size limit.")); return }
        stdout.append(data); pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline]); pending.removeSubrange(...newline); validateLine(line)
        }
    }
    private func validateLine(_ line: Data) {
        guard !line.isEmpty else { return }
        guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = value["type"] as? String else {
            stop(AssistantError.message("Codex returned an unreadable response.")); return
        }
        guard ["item.started", "item.completed"].contains(type), let item = value["item"] as? [String: Any], let kind = item["type"] as? String,
              !["agent_message", "reasoning", "error"].contains(kind) else { return }
        let paper = kind == "mcp_tool_call" && item["server"] as? String == "folio_paper" && ["search_paper", "read_paper_page"].contains(item["tool"] as? String ?? "")
        guard allowResearch && (kind == "web_search" || paper) else { stop(AssistantError.message("Codex attempted a tool outside this request’s permissions.")); return }
        guard let id = item["id"] as? String else { stop(AssistantError.message("Codex returned an invalid tool response.")); return }
        toolIDs.insert(id)
        if toolIDs.count > 12 { stop(AssistantError.message("The research lookup limit was reached. Ask a more focused question.")) }
    }
    private func terminated() {
        lock.lock(); defer { lock.unlock() }; ended = true; completeIfReady()
        // A child must not retain our pipes indefinitely after the main process exits.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }; self.lock.lock(); defer { self.lock.unlock() }
            guard !self.finished else { return }
            // Treat an inherited pipe that never closes as an incomplete response,
            // rather than accepting an answer whose final events were not drained.
            if self.failure == nil { self.failure = AssistantError.message("Codex did not close its response stream. Try again.") }
            self.outputEOF = true; self.errorEOF = true; self.completeIfReady()
        }
    }
    private func stop(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }; if failure == nil { failure = error }
        guard started else { return }
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }; self.lock.lock(); defer { self.lock.unlock() }
            guard !self.finished else { return }
            if self.process.isRunning { kill(self.process.processIdentifier, SIGKILL) }
            if self.ended { self.finish(.failure(self.failure ?? error)) }
        }
    }
    private func completeIfReady() {
        guard ended, outputEOF, errorEOF else { return }
        if let failure { finish(.failure(failure)); return }
        guard process.terminationStatus == 0 else {
            finish(.failure(AssistantError.message(CodexFailure.message(stdout: stdout, stderr: stderr)))); return
        }
        finish(.success(stdout))
    }
    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }; finished = true; timeout?.cancel()
        output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        // Readers may have an in-flight callback. Their handles close when this capture is released.
        try? input.fileHandleForWriting.close()
        let callback = continuation; continuation = nil; callback?.resume(with: result)
    }
}

public struct AssistantClient {
    private let environment: [String: String]
    private let process: any AssistantProcessRunning
    private let transport: any AssistantTransport
    private let storedKey: @Sendable () -> String?
    public init(environment: [String: String] = ProcessInfo.processInfo.environment, process: any AssistantProcessRunning = AssistantProcessRunner(), transport: any AssistantTransport = AssistantHTTPTransport(), storedKey: @escaping @Sendable () -> String? = { ClaudeKeyStore.dotEnvKey() ?? ClaudeKeyStore.read() }) {
        self.environment = environment; self.process = process; self.transport = transport; self.storedKey = storedKey
    }
    /// `onText` receives progressive text only from providers that stream (Claude API). Codex CLI
    /// returns its answer when the run completes; there is no automatic fallback between providers.
    public func ask(_ request: AssistantRequest, provider: AssistantProvider, onText: (@Sendable (String) -> Void)? = nil) async throws -> String {
        try Task.checkCancellation()
        if provider == .codex { return try await codex(request) }
        return try await claude(request, onText: onText)
    }
    private func codex(_ request: AssistantRequest) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("folio-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = directory.appendingPathComponent("system.txt")
        try Data(request.system.utf8).write(to: system, options: .atomic)
        var config: [String: Any] = ["model_provider": "openai", "model_reasoning_effort": "medium", "model_instructions_file": system.path,
            "approval_policy": "never", "web_search": request.research ? "live" : "disabled", "project_doc_max_bytes": 0, "history.persistence": "none",
            "skills.bundled.enabled": false, "skills.include_instructions": false, "features.skip_host_skill_discovery": true,
            "analytics.enabled": false, "feedback.enabled": false, "tools.update_plan.enabled": false, "tools.experimental_request_user_input.enabled": false]
        for feature in ["shell_tool", "shell_snapshot", "search_tool", "apply_patch_freeform", "view_image", "js_repl", "multi_agent", "apps", "plugins", "hooks", "memories", "image_generation", "browser_use", "computer_use", "remote_plugin"] { config["features.\(feature)"] = false }
        if request.research {
            let paper = directory.appendingPathComponent("paper.json")
            try JSONSerialization.data(withJSONObject: ["pages": request.paper.lookupPages, "truncated": request.paper.truncatedPages]).write(to: paper, options: .atomic)
            let helper = environment["FOLIO_PAPER_TOOLS_CLI"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("FolioPaperTools")
            guard let helper, FileManager.default.isExecutableFile(atPath: helper.path) else { throw AssistantError.message("The native paper lookup helper is missing. Rebuild or reinstall Folio with FolioPaperTools.") }
            config["mcp_servers.folio_paper.command"] = helper.path; config["mcp_servers.folio_paper.args"] = [paper.path]
            config["mcp_servers.folio_paper.enabled_tools"] = ["search_paper", "read_paper_page"]
            config["mcp_servers.folio_paper.required"] = true; config["mcp_servers.folio_paper.startup_timeout_sec"] = 10
            config["mcp_servers.folio_paper.default_tools_approval_mode"] = "auto"
        }
        var arguments = ["--no-daemon", "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "--model", "gpt-6.1-terra"]
        // `-c` values are TOML; JSON's default `\/` escape is invalid TOML and corrupts every path.
        for key in config.keys.sorted() { arguments += ["-c", key + "=" + String(data: try JSONSerialization.data(withJSONObject: config[key]!, options: [.fragmentsAllowed, .withoutEscapingSlashes]), encoding: .utf8)!] }
        if request.structured {
            let schema = directory.appendingPathComponent("schema.json"); try JSONSerialization.data(withJSONObject: Self.overviewSchema).write(to: schema, options: .atomic)
            arguments += ["--output-schema", schema.path]
        }
        arguments += ["-"]
        var childEnvironment = environment
        for key in ["OPENREVIEW_TOKEN", "OPENREVIEW_USERNAME", "OPENREVIEW_PASSWORD", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "CODEX_THREAD_ID"] { childEnvironment.removeValue(forKey: key) }
        let candidates = [environment["FOLIO_CODEX_CLI"], NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/Applications/Codex.app/Contents/Resources/codex"] + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        guard let executable = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw AssistantError.message("Install Codex CLI and run codex login. Set FOLIO_CODEX_CLI when it is not on PATH.") }
        let prompt = request.messages.map { "<turn role=\"\($0.role.rawValue)\">\n\(AssistantPaper.quoted($0.content))\n</turn>" }.joined(separator: "\n")
        let data = try await process.run(executable: URL(fileURLWithPath: executable), arguments: arguments, environment: childEnvironment, directory: directory, input: Data(prompt.utf8), allowResearch: request.research)
        try Task.checkCancellation()
        var texts: [String] = []; var seen = Set<String>(); var complete = false; var failed = false
        for line in data.split(separator: 10) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { throw AssistantError.message("Codex returned an unreadable response.") }
            let type = value["type"] as? String ?? ""
            if type == "turn.completed" { complete = true }
            if ["turn.failed", "error"].contains(type) { failed = true }
            if type == "item.completed", let item = value["item"] as? [String: Any], item["type"] as? String == "agent_message", let id = item["id"] as? String, seen.insert(id).inserted, let text = item["text"] as? String { texts.append(text) }
        }
        let text = texts.joined(separator: "\n\n")
        if failed { throw AssistantError.message(CodexFailure.message(stdout: data, stderr: Data())) }
        guard complete, !text.isEmpty, text.count <= 64_000 else { throw AssistantError.message("Codex did not finish a valid answer. Try again.") }
        return text
    }
    private func claude(_ request: AssistantRequest, onText: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let envKey = environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = (envKey?.isEmpty == false ? envKey : storedKey()), !key.isEmpty, !key.hasPrefix("paste-") else { throw AssistantError.message("Claude’s key is missing or macOS has blocked access to it. Check ANTHROPIC_API_KEY in the native project’s .env or Folio’s launch environment, or the previously imported key, or choose Codex CLI. Folio will not open a Keychain password prompt.") }
        var turns: [[String: Any]] = request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        var allText: [String] = []; var calls = 0; var sources: [String: String] = [:]
        let began = Date()
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(began) < 180 else { throw AssistantError.message("Claude exceeded the three-minute request limit. Try again.") }
            var body: [String: Any] = ["model": ClaudeKeyStore.model(environment: environment), "max_tokens": request.structured ? 6000 : 12000,
                "thinking": ["type": "adaptive"], "output_config": ["effort": "high"], "system": request.system, "messages": turns]
            if request.structured { body["output_config"] = ["effort": "high", "format": ["type": "json_schema", "schema": Self.overviewSchema]] }
            if request.research { body["tools"] = Self.paperTools + [["type": "web_search_20260209", "name": "web_search", "max_uses": 3]] }
            var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            urlRequest.httpMethod = "POST"; urlRequest.timeoutInterval = max(1, 180 - Date().timeIntervalSince(began))
            urlRequest.setValue("application/json", forHTTPHeaderField: "content-type"); urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version"); urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
            if onText != nil { body["stream"] = true }
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            if let onText {
                let blocks: [[String: Any]]; let stop: String
                (blocks, stop) = try await streamedTurn(urlRequest, onText: onText, separator: allText.isEmpty ? "" : "\n\n")
                try Task.checkCancellation()
                if try await finishTurn(blocks: blocks, stop: stop, request: request, allText: &allText, calls: &calls, sources: &sources, turns: &turns) { continue }
                return Self.finalAnswer(allText, sources)
            }
            let data: Data; let status: Int
            do { (data, status) = try await transport.send(urlRequest) } catch is CancellationError { throw CancellationError() } catch { if Task.isCancelled { throw CancellationError() }; throw AssistantError.message("Could not reach Anthropic. Check your internet connection.") }
            try Task.checkCancellation()
            guard (200..<300).contains(status) else {
                let message = status == 401 ? "Anthropic rejected the Claude API key. Check the configured environment or choose Codex CLI." : status == 403 ? "This API key cannot access the assistant model." : status == 404 ? "The Claude model is unavailable for this API key." : status == 429 ? "Claude is rate limited. Try again later." : "Claude could not complete this request. Try again."
                throw AssistantError.message(message)
            }
            guard data.count <= 4_000_000, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let blocks = value["content"] as? [[String: Any]], let stop = value["stop_reason"] as? String else { throw AssistantError.message("Claude returned an unreadable response.") }
            if try finishTurn(blocks: blocks, stop: stop, request: request, allText: &allText, calls: &calls, sources: &sources, turns: &turns) { continue }
            return Self.finalAnswer(allText, sources)
        }
        throw AssistantError.message("The research lookup limit was reached. Ask a more focused question.")
    }

    /// Returns true when tool results were appended and another round is needed.
    private func finishTurn(blocks: [[String: Any]], stop: String, request: AssistantRequest, allText: inout [String], calls: inout Int, sources: inout [String: String], turns: inout [[String: Any]]) throws -> Bool {
        for block in blocks {
            if block["type"] as? String == "text", let text = block["text"] as? String { allText.append(text) }
            if block["type"] as? String == "server_tool_use" { calls += 1 }
            for citation in block["citations"] as? [[String: Any]] ?? [] {
                guard citation["type"] as? String == "web_search_result_location", let rawURL = citation["url"] as? String, let url = URL(string: rawURL),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { continue }
                let title = ((citation["title"] as? String) ?? url.host ?? "Source").replacingOccurrences(of: "[\\[\\]\\r\\n]", with: " ", options: .regularExpression)
                sources[url.absoluteString] = String(title.prefix(160))
            }
        }
        guard calls <= 12, allText.joined().count <= 64_000 else { throw AssistantError.message("The research response exceeded the local limit. Ask a more focused question.") }
        let pending = blocks.filter { $0["type"] as? String == "tool_use" }
        if stop == "tool_use", request.research, !pending.isEmpty {
            turns.append(["role": "assistant", "content": blocks])
            var results: [[String: Any]] = []
            for tool in pending {
                calls += 1; guard calls <= 12, let name = tool["name"] as? String, let id = tool["id"] as? String, let input = tool["input"] as? [String: Any] else { throw AssistantError.message("The research lookup limit was reached.") }
                let result = Self.paperLookup(name: name, input: input, paper: request.paper)
                results.append(["type": "tool_result", "tool_use_id": id, "content": String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!, "is_error": result["error"] != nil])
            }
            turns.append(["role": "user", "content": results]); return true
        }
        // Server-side web search can pause a long turn; resend the paused assistant content so Claude continues it.
        if stop == "pause_turn", request.research { turns.append(["role": "assistant", "content": blocks]); return true }
        guard stop == "end_turn", !allText.isEmpty else { throw AssistantError.message(stop == "refusal" ? "Claude declined this request." : "Claude’s answer was cut off. Try a more focused question.") }
        return false
    }
    private static func finalAnswer(_ allText: [String], _ sources: [String: String]) -> String {
        let sourceText = sources.keys.sorted().prefix(8).map { url in "[\(sources[url]!)](\(url.replacingOccurrences(of: ")", with: "%29")))" }.joined(separator: " · ")
        return allText.joined(separator: "\n\n") + (sourceText.isEmpty ? "" : "\n\nSources: " + sourceText)
    }
    private func streamedTurn(_ urlRequest: URLRequest, onText: @escaping @Sendable (String) -> Void, separator: String) async throws -> ([[String: Any]], String) {
        let status: Int; let lines: AsyncThrowingStream<String, Error>
        do { (status, lines) = try await transport.stream(urlRequest) } catch is CancellationError { throw CancellationError() } catch { if Task.isCancelled { throw CancellationError() }; throw AssistantError.message("Could not reach Anthropic. Check your internet connection.") }
        guard (200..<300).contains(status) else {
            let message = status == 401 ? "Anthropic rejected the Claude API key. Check the configured environment or choose Codex CLI." : status == 403 ? "This API key cannot access the assistant model." : status == 404 ? "The Claude model is unavailable for this API key." : status == 429 ? "Claude is rate limited. Try again later." : "Claude could not complete this request. Try again."
            throw AssistantError.message(message)
        }
        var accumulator = AssistantStreamAccumulator(onText: onText, separator: separator)
        do { for try await line in lines { try accumulator.feed(line) } } catch is CancellationError { throw CancellationError() } catch let error as AssistantError { throw error } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AssistantError.message("The connection to Anthropic was interrupted. Try again.")
        }
        guard let stop = accumulator.stopReason, !accumulator.blocks.isEmpty else { throw AssistantError.message("Claude returned an unreadable response.") }
        return (accumulator.blocks, stop)
    }

    public static var paperTools: [[String: Any]] {
        PaperLookup.tools.map { tool in ["name": tool["name"]!, "description": tool["description"]!, "input_schema": tool["inputSchema"]!] }
    }
    public static func paperLookup(name: String, input: [String: Any], paper: AssistantPaper) -> [String: Any] {
        guard let lookup = try? PaperLookup(pages: paper.lookupPages, truncated: paper.truncatedPages) else { return ["error": "The supplied paper extraction exceeds the local lookup limit."] }
        return lookup.call(name, arguments: input)
    }
    public static var overviewSchema: [String: Any] {
        let slot: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["available", "label", "explanation", "sentence_ids"], "properties": ["available": ["type": "boolean"], "label": ["type": "string"], "explanation": ["type": "string"], "sentence_ids": ["type": "array", "items": ["type": "integer"]]]]
        return ["type": "object", "additionalProperties": false, "required": ["problem", "approach", "finding"], "properties": ["problem": slot, "approach": slot, "finding": slot]]
    }
}

/// Codex `exec --json` reports account and model failures as JSON events on stdout, not stderr.
/// The reader sees Codex's own reason (usage limit with its reset time, sign-in, model access) instead of a generic failure.
enum CodexFailure {
    static func message(stdout: Data, stderr: Data) -> String {
        var reasons: [String] = []
        for line in stdout.split(separator: 10) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if value["type"] as? String == "error", let text = value["message"] as? String { reasons.append(text) }
            if value["type"] as? String == "turn.failed", let error = value["error"] as? [String: Any], let text = error["message"] as? String { reasons.append(text) }
        }
        let errorText = String(data: stderr, encoding: .utf8) ?? ""
        let reason = reasons.last ?? ""
        let all = (reason + "\n" + errorText).lowercased()
        if all.contains("usage limit") || all.contains("quota") || all.contains("rate limit") {
            let reset = reason.range(of: #"try again (at|in) [^.\n]+"#, options: [.regularExpression, .caseInsensitive]).map { String(reason[$0]) }
            return "Codex usage limit reached on your ChatGPT plan." + (reset.map { " \($0.prefix(1).uppercased() + $0.dropFirst())." } ?? " Try again later.") + " You can also choose Claude API in AI settings."
        }
        if all.contains("not logged in") || all.contains("login") || all.contains("sign in") || all.contains("unauthorized") || all.contains("401") {
            return "Codex CLI is not signed in. Run codex login in a terminal."
        }
        let detail = reason.isEmpty ? errorText.split(separator: "\n").last.map(String.init) ?? "" : reason
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Codex failed. Check its installation, model access, sign-in and usage limits." : "Codex failed: \(trimmed.prefix(300))"
    }
}
