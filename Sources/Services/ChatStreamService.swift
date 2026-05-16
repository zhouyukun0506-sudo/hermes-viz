import Foundation

/// Events emitted by the Hermes chat bridge (JSON-lines protocol).
enum ChatStreamEvent {
    case thinking(String)       // Agent thinking status changed
    case reasoning(String)      // Reasoning/thinking token delta
    case delta(String)          // Content token delta
    case toolStart(id: String, name: String, input: String)
    case toolEnd(id: String, name: String, success: Bool, output: String)
    case toolProgress(name: String, preview: String)
    case done(content: String)  // Full response received
    case aborted(content: String)
    case error(message: String)
}

/// Drives a Hermes agent session via the Python bridge script,
/// streaming events back to the UI in real time.
@Observable
final class ChatStreamService {

    // MARK: - Published state for UI binding

    private(set) var streamingContent = ""
    private(set) var thinkingStatus: String?
    private(set) var reasoningText = ""
    private(set) var isStreaming = false
    private(set) var currentToolName: String?
    private(set) var currentToolInput: String?
    private(set) var lastError: String?
    private(set) var toolCalls: [ToolCallEvent] = []
    private(set) var currentSessionId: String?
    private(set) var promptTokens: Int = 0
    private(set) var completionTokens: Int = 0

    // MARK: - Internal

    private var process: Process?
    private var stdinPipe: Pipe?
    private var readBuffer = ""
    
    private let bridgeScriptPath: String = {
        // Try bundled resource first (Swift Package Manager)
        if let bundled = Bundle.module.path(forResource: "hermes_chat_bridge", ofType: "py") {
            return bundled
        }
        // Dev: in-source location
        let srcPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("hermes_chat_bridge.py")
            .path
        if FileManager.default.fileExists(atPath: srcPath) { return srcPath }
        // Fallback
        return NSHomeDirectory() + "/.hermes/hermes-viz/Sources/Services/hermes_chat_bridge.py"
    }()

    private let hermesAgentDir: String = {
        let env = ProcessInfo.processInfo.environment["HERMES_AGENT_DIR"]
        return env ?? NSHomeDirectory() + "/.hermes/hermes-agent"
    }()

    private let pythonPath: String = {
        // Use hermes-agent's venv python if available
        let venvPython = NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python3"
        if FileManager.default.fileExists(atPath: venvPython) { return venvPython }
        return "/usr/bin/python3"
    }()

    // MARK: - Public API

    /// Send a prompt to the agent and start streaming the response.
    func send(prompt: String, resumeSessionId: String? = nil) {
        // Reset per-turn state
        streamingContent = ""
        thinkingStatus = nil
        reasoningText = ""
        currentToolName = nil
        currentToolInput = nil
        lastError = nil
        toolCalls = []
        promptTokens = 0
        completionTokens = 0
        isStreaming = true
        readBuffer = ""

        // If session changed, kill old process
        if currentSessionId != resumeSessionId {
            terminateProcess()
            currentSessionId = resumeSessionId
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.ensureProcessStarted(resumeSessionId: resumeSessionId)
            self.sendPromptToBridge(prompt: prompt)
        }
    }

    func terminateProcess() {
        process?.terminate()
        process = nil
        stdinPipe = nil
    }

    private func ensureProcessStarted(resumeSessionId: String?) {
        if process != nil && process?.isRunning == true { return }
        
        process = Process()
        stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        
        process?.executableURL = URL(fileURLWithPath: pythonPath)
        var args = [bridgeScriptPath, "--server"]
        if let sid = resumeSessionId {
            args.append("--resume")
            args.append(sid)
        }
        process?.arguments = args
        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe
        process?.standardError = FileHandle.nullDevice
        
        // Inherit environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = hermesAgentDir
        env["HERMES_AGENT_DIR"] = hermesAgentDir
        env["HOME"] = NSHomeDirectory()
        env["USER"] = NSUserName()
        process?.environment = env
        
        do {
            try process?.run()
            
            // Background thread to read stdout
            let outHandle = stdoutPipe.fileHandleForReading
            Thread.detachNewThread { [weak self] in
                while let self = self, let proc = self.process, proc.isRunning {
                    let data = outHandle.availableData
                    if data.isEmpty { break }
                    if let str = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { self.handleBridgeOutput(str) }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { 
                self.lastError = "Bridge start failed: \(error)"
                self.isStreaming = false
            }
        }
    }

    private func sendPromptToBridge(prompt: String) {
        guard let pipe = stdinPipe else { return }
        let cmd: [String: Any] = ["type": "chat", "prompt": prompt]
        if let data = try? JSONSerialization.data(withJSONObject: cmd),
           var str = String(data: data, encoding: .utf8) {
            str += "\n"
            if let finalData = str.data(using: .utf8) {
                pipe.fileHandleForWriting.write(finalData)
            }
        }
    }

    private func handleBridgeOutput(_ text: String) {
        readBuffer += text
        let lines = readBuffer.components(separatedBy: "\n")
        if lines.count > 1 {
            for i in 0..<lines.count-1 {
                let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    parseEvent(line)
                }
            }
            readBuffer = lines.last ?? ""
        }
    }

    /// Abort the current generation.
    func abort() {
        guard isStreaming, let pipe = stdinPipe else { return }
        let cmd = "{\"type\":\"abort\"}\n"
        if let data = cmd.data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
        // Also send SIGINT to the process for immediate interrupt
        if let p = process, p.isRunning {
            p.interrupt()  // sends SIGINT
        }
    }

    // MARK: - JSON-lines parsing

    private func parseEvent(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case "session_id":
                let id = json["id"] as? String ?? ""
                self.currentSessionId = id

            case "usage":
                self.promptTokens = json["prompt_tokens"] as? Int ?? 0
                self.completionTokens = json["completion_tokens"] as? Int ?? 0

            case "thinking":
                let text = json["text"] as? String ?? ""
                self.thinkingStatus = text.isEmpty ? nil : text
                if !text.isEmpty {
                    self.currentToolName = nil
                    self.currentToolInput = nil
                }

            case "reasoning":
                let text = json["text"] as? String ?? ""
                self.reasoningText += text

            case "delta":
                let text = json["text"] as? String ?? ""
                self.streamingContent += text
                self.thinkingStatus = nil

            case "tool_start":
                let name = json["name"] as? String ?? ""
                let id = json["id"] as? String ?? ""
                let input = json["input"] as? String ?? ""
                self.currentToolName = name
                self.currentToolInput = input
                self.thinkingStatus = nil
                self.toolCalls.append(ToolCallEvent(
                    id: id, name: name, input: input,
                    isComplete: false, success: true, output: ""
                ))

            case "tool_end":
                let id = json["id"] as? String ?? ""
                let success = json["success"] as? Bool ?? true
                if let idx = self.toolCalls.lastIndex(where: { $0.id == id }) {
                    self.toolCalls[idx].isComplete = true
                    self.toolCalls[idx].success = success
                    self.toolCalls[idx].output = json["output"] as? String ?? ""
                }
                self.currentToolName = nil
                self.currentToolInput = nil

            case "tool_progress":
                let name = json["name"] as? String ?? ""
                let preview = json["preview"] as? String ?? ""
                self.currentToolName = name
                self.currentToolInput = preview

            case "done":
                let content = json["content"] as? String ?? ""
                if !content.isEmpty && self.streamingContent.isEmpty {
                    self.streamingContent = content
                }
                self.thinkingStatus = nil
                self.currentToolName = nil
                self.isStreaming = false

            case "aborted":
                self.thinkingStatus = nil
                self.currentToolName = nil
                self.isStreaming = false

            case "error":
                self.lastError = json["message"] as? String ?? "Unknown error"
                self.thinkingStatus = nil
                self.isStreaming = false

            default:
                break
            }
        }
    }
}

struct ToolCallEvent: Identifiable {
    let id: String
    let name: String
    let input: String
    var isComplete: Bool
    var success: Bool
    var output: String
}
