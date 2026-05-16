import SwiftUI
import Markdown
import UniformTypeIdentifiers
import AppKit

// Unified dark palette — 3 muted tones
extension Color {
    static let wxBase    = Color(red: 0.102, green: 0.102, blue: 0.118)  // #1A1A1E
    static let wxSurface = Color(red: 0.145, green: 0.145, blue: 0.165)  // #25252A
    static let wxAccent  = Color(red: 0.42,  green: 0.58,  blue: 0.48)   // #6B947A
    // Text: .primary = white@0.9, .secondary = white@0.55, .tertiary = white@0.35
}

struct ChatView: View {
    private let agentDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hermes/hermes-agent").path
    private let sessionsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hermes/sessions").path
    @State private var isActive = false
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isRunning = false
    @State private var errorText: String?
    @State private var gatewayError: String?
    @State private var service = HermesDataService.shared
    private var gatewayRunning: Bool { service.gateway?.isRunning ?? false }
    @State private var showHistory = false
    @State private var historySessions: [HistorySession] = []
    @State private var resumeSessionId: String?
    @State private var attachedFiles: [URL] = []
    @State private var dropTargeted = false
    @FocusState private var isFocused: Bool
    @State private var chatStream = ChatStreamService()
    @State private var streamingMessageId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if isActive { activeView } else { inactiveView }
        }
        .task { service.refresh(); loadHistory() }
        .onChange(of: chatStream.currentSessionId) { _, new in
            if let new = new, resumeSessionId == nil {
                resumeSessionId = new
                loadHistory()
            }
        }
        .onChange(of: chatStream.isStreaming) { _, new in
            if !new {
                loadHistory()
            }
        }
    }

    // MARK: - Inactive View (WeChat-style landing)

    private var inactiveView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Simple green circle with bolt
            Circle()
                .fill(Color.wxAccent)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 6) {
                Text("Hermes Chat")
                    .font(.system(size: 18, weight: .semibold))
                Text(gatewayRunning ? "Online" : "Offline")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    isActive = true
                    messages = []
                    errorText = nil
                    showHistory = false
                    resumeSessionId = nil
                    isFocused = true
                } label: {
                    Text("New Chat")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 160, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.wxAccent)
                .controlSize(.regular)
                .keyboardShortcut(.return)
                .disabled(!gatewayRunning)

                if !gatewayRunning {
                    Button {
                        toggleGateway(up: true)
                    } label: {
                        Text("Start Agent")
                            .font(.system(size: 13))
                            .frame(width: 160, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if gatewayRunning {
                    Button(role: .destructive) {
                        toggleGateway(up: false)
                    } label: {
                        Text("Stop Agent")
                            .font(.system(size: 12))
                            .frame(width: 160, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let err = gatewayError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.7, green: 0.35, blue: 0.35))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.6, green: 0.25, blue: 0.25).opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wxBase)
    }

    // MARK: - Active View

    private var activeView: some View {
        HStack(spacing: 0) {
            if showHistory { historySidebar }
            VStack(spacing: 0) { header; bodyView; inputBar }
        }
        .background(Color.wxBase)
    }

    // MARK: - History Sidebar

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showHistory = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.wxBase)

            List {
                Section {
                    Button {
                        resumeSessionId = nil
                        messages = []
                        isFocused = true
                    } label: {
                        Label("New Chat", systemImage: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }

                if historySessions.isEmpty {
                    Text("No history yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(historySessions) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.display)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(s.date)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(s.platform)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isRunning else { return }
                            resumeSessionId = s.id
                            messages = loadMessages(s.id)
                            isActive = true
                            isFocused = true
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 200)
        .background(Color.wxBase)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if !showHistory {
                Button { showHistory = true } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            Circle()
                .fill(gatewayRunning ? Color.wxAccent : Color(red: 0.55, green: 0.35, blue: 0.25))
                .frame(width: 6, height: 6)

            Text(gatewayRunning ? "Active" : "Offline")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let rid = resumeSessionId {
                Text("#\(rid.prefix(8))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.wxAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.wxAccent.opacity(0.08))
                    .clipShape(Capsule())
            }

            Spacer()

            Button("End") {
                isActive = false
                showHistory = false
                resumeSessionId = nil
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.wxBase)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Message Body

    private var bodyView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.title2)
                                .foregroundStyle(.quaternary)
                            Text("Send a message to start")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    ForEach(messages) { msg in
                        MessageBubble(msg: msg)
                            .id(msg.id)
                    }

                    if isRunning {
                        HStack(spacing: 8) {
                            if let status = chatStream.thinkingStatus, !status.isEmpty {
                                // Real thinking status from agent
                                ThinkingDots()
                                Text(status)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.wxAccent)
                            } else if let toolName = chatStream.currentToolName {
                                // Tool execution
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                                Image(systemName: "hammer")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(toolName)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let input = chatStream.currentToolInput, !input.isEmpty {
                                    Text(input)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            } else {
                                ThinkingDots()
                                Text("Processing...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 36)
                        .padding(.top, 4)
                        .id("loading")
                    }

                    if let err = errorText {
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.7, green: 0.35, blue: 0.35))
                            .padding(8)
                            .background(Color(red: 0.6, green: 0.25, blue: 0.25).opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(.horizontal, 12)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: isRunning) {
                proxy.scrollTo("loading", anchor: .bottom)
            }
            // Scroll on streaming content updates
            .onChange(of: chatStream.streamingContent) {
                if let sid = streamingMessageId {
                    proxy.scrollTo(sid, anchor: .bottom)
                }
            }
            .onChange(of: chatStream.reasoningText) {
                if let sid = streamingMessageId {
                    proxy.scrollTo(sid, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar (WeChat-style)

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Attached files
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles, id: \.self) { url in
                            HStack(spacing: 4) {
                                Image(systemName: docIcon(url))
                                    .font(.caption2)
                                Text(url.lastPathComponent)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button {
                                    attachedFiles.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.wxSurface)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            // Input area
            HStack(spacing: 8) {
                Button { pickFiles() } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach files")

                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit { send() }
                    .disabled(isRunning)

                if isRunning {
                    // Abort button
                    Button {
                        chatStream.abort()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.3))
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating")
                } else {
                    Button(action: send) {
                        Text("Send")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 30)
                            .background(
                                (inputText.isEmpty && attachedFiles.isEmpty)
                                    ? Color.white.opacity(0.25)
                                    : Color.wxAccent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .disabled(inputText.isEmpty && attachedFiles.isEmpty)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.wxBase)
        .overlay(alignment: .top) {
            Divider()
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async {
                            if !attachedFiles.contains(url) { attachedFiles.append(url) }
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Send (streaming)

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !attachedFiles.isEmpty), !isRunning, gatewayRunning else { return }
        var full = text
        for url in attachedFiles { full = "@\(url.path)\n" + full }
        messages.append(ChatMessage(role: .user, content: full))
        inputText = ""
        attachedFiles = []
        errorText = nil
        isRunning = true

        // Create a streaming assistant message placeholder
        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let msgIdx = messages.count - 1
        streamingMessageId = assistantMsg.id

        // Start streaming
        chatStream.send(prompt: full, resumeSessionId: resumeSessionId)

        // Poll for updates from ChatStreamService
        pollStreamUpdates(messageIndex: msgIdx)
    }

    private func pollStreamUpdates(messageIndex idx: Int) {
        // Use a timer to poll the ChatStreamService state and update the message
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard idx < messages.count else { timer.invalidate(); return }

            // Update the streaming message with latest content
            messages[idx].content = chatStream.streamingContent
            messages[idx].reasoningContent = chatStream.reasoningText
            messages[idx].thinkingStatus = chatStream.thinkingStatus ?? ""
            messages[idx].toolCalls = chatStream.toolCalls
            messages[idx].promptTokens = chatStream.promptTokens
            messages[idx].completionTokens = chatStream.completionTokens

            // Check for errors
            if let err = chatStream.lastError {
                errorText = err
            }

            // Check if streaming is done
            if !chatStream.isStreaming {
                timer.invalidate()
                messages[idx].isStreaming = false
                isRunning = false
                streamingMessageId = nil

                // Remove empty assistant messages
                if messages[idx].content.isEmpty && chatStream.lastError != nil {
                    messages.remove(at: idx)
                }
            }
        }
    }

    // MARK: - Helpers

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls where !attachedFiles.contains(url) {
                attachedFiles.append(url)
            }
        }
    }

    private func docIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "swift": return "swift"
        case "json": return "doc.text"
        case "md": return "doc.richtext"
        case "txt": return "doc.plaintext"
        default: return "doc"
        }
    }

    private func toggleGateway(up: Bool) {
        gatewayError = nil
        let launchdLabel = "ai.hermes.gateway"
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/\(launchdLabel).plist"
        let userId = String(getuid())
        let stateFile = NSHomeDirectory() + "/.hermes/gateway_state.json"

        if up {
            DispatchQueue.global(qos: .userInitiated).async {
                // If already running, just confirm and return
                if let d = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   (j["gateway_state"] as? String) == "running" {
                    DispatchQueue.main.async {
                        service.refresh()
                        gatewayError = nil
                    }
                    return
                }

                // Try kickstart first (restarts an already-loaded service),
                // then bootstrap (loads a not-yet-loaded service). Both
                // suppress errors — the polling loop below handles the result.
                _ = runShell("launchctl kickstart gui/\(userId)/\(launchdLabel) 2>/dev/null")
                _ = runShell("launchctl bootstrap gui/\(userId) '\(plistPath)' 2>/dev/null")

                // Poll for the gateway state file to say "running" (up to 8 seconds)
                var ready = false
                for _ in 0..<16 {
                    Thread.sleep(forTimeInterval: 0.5)
                    if let d = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       (j["gateway_state"] as? String) == "running" {
                        ready = true
                        break
                    }
                }

                DispatchQueue.main.async {
                    service.refresh()
                    if ready || service.gateway?.isRunning == true {
                        gatewayError = nil
                    } else {
                        gatewayError = "Start failed: gateway did not become ready"
                    }
                }
            }
        } else {
            // 1. Kickstart -k kills the running service, then bootout removes it
            DispatchQueue.global(qos: .userInitiated).async {
                _ = runShell("launchctl kickstart -k gui/\(userId)/\(launchdLabel) 2>/dev/null")
                Thread.sleep(forTimeInterval: 0.5)
                _ = runShell("launchctl bootout gui/\(userId)/\(launchdLabel) 2>/dev/null")
                // 2. Update the state file
                if let d = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
                   var j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    j["gateway_state"] = "stopped"
                    j["pid"] = NSNull()
                    if let u = try? JSONSerialization.data(withJSONObject: j) {
                        try? u.write(to: URL(fileURLWithPath: stateFile))
                    }
                }
                DispatchQueue.main.async { service.refresh(); gatewayError = nil }
            }
        }
    }

    private func loadHistory() {
        var list = [HistorySession]()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) {
            for n in files where n.hasPrefix("session_") && n.hasSuffix(".json") {
                let p = "\(sessionsDir)/\(n)"
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let sid = j["session_id"] as? String
                else { continue }

                let title: String = {
                    if let dn = j["display_name"] as? String, !dn.isEmpty { return dn }
                    if let msgs = j["messages"] as? [[String: Any]] {
                        for m in msgs where (m["role"] as? String) == "user" {
                            let text = Self.extractText(from: m["content"])
                            if !text.isEmpty {
                                let cleaned = text
                                    .replacingOccurrences(of: #"(?s)I've uploaded \d+ file\(s\): [^\n]*"#, with: "📎 File upload", options: .regularExpression)
                                    .replacingOccurrences(of: #"(?s)\[Attached files: [^\]]*\]"#, with: "📎 File upload", options: .regularExpression)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if cleaned.count > 2 { return String(cleaned.prefix(50)) }
                            }
                        }
                    }
                    let platform = (j["platform"] as? String ?? "unknown")
                    let platformLabel: String = {
                        switch platform {
                        case "cli": return "CLI Session"
                        case "weixin": return "WeChat Session"
                        case "webui": return "Web Session"
                        default: return platform.capitalized + " Session"
                        }
                    }()
                    return platformLabel
                }()

                list.append(HistorySession(
                    id: sid,
                    date: String((j["session_start"] as? String ?? "").prefix(10)),
                    display: title,
                    platform: j["platform"] as? String ?? "",
                    fullTimestamp: j["session_start"] as? String ?? ""
                ))
            }
        }
        list.sort { $0.fullTimestamp > $1.fullTimestamp }
        historySessions = list
    }

    private static func extractText(from content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private func loadMessages(_ sid: String) -> [ChatMessage] {
        for name in ["session_\(sid).json", "\(sid).json"] {
            let p = "\(sessionsDir)/\(name)"
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let msgs = j["messages"] as? [[String: Any]]
            else { continue }
            return msgs.compactMap { m in
                let r: ChatRole = (m["role"] as? String) == "user" ? .user : .assistant
                let c: String = {
                    if let s = m["content"] as? String { return s }
                    if let a = m["content"] as? [[String: Any]] {
                        return a.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    return ""
                }()
                return c.isEmpty ? nil : ChatMessage(role: r, content: c)
            }
        }
        return []
    }
}

// MARK: - Thinking Indicator (simple dots)

struct ThinkingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == Double(i) ? 1.2 : 0.7)
                    .opacity(phase == Double(i) ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 3.0
            }
        }
    }
}

// MARK: - Models

struct HistorySession: Identifiable { let id, date, display, platform, fullTimestamp: String }
enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    var thinkingStatus: String = ""
    var reasoningContent: String = ""
    var toolCalls: [ToolCallEvent] = []
    var isStreaming: Bool = false
    var promptTokens: Int = 0
    var completionTokens: Int = 0
}

// MARK: - Message Bubble (WeChat-style)

struct MessageBubble: View {
    let msg: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .user {
                Spacer(minLength: 60)
            }

            if msg.role == .assistant {
                // Bot avatar
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                // Bot bubble with markdown rendering
                VStack(alignment: .leading, spacing: 6) {
                    // Thinking/reasoning panel
                    if !msg.reasoningContent.isEmpty {
                        ReasoningPanel(text: msg.reasoningContent)
                    }
                    // Tool calls
                    ForEach(msg.toolCalls) { tc in
                        ToolCallRow(event: tc)
                    }
                    // Markdown-rendered content
                    if !msg.content.isEmpty {
                        AssistantBubble(msg: msg)
                    }
                    // Streaming cursor
                    if msg.isStreaming && msg.content.isEmpty {
                        StreamingCursor()
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.wxSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer(minLength: 60)
            } else {
                // User bubble
                Text(msg.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.wxAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Circle()
                    .fill(Color.wxAccent)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - Reasoning Panel (collapsible thinking)

struct ReasoningPanel: View {
    let text: String
    @State private var expanded = false

    /// Clean raw reasoning text: strip line-number prefixes, thinking tags, etc.
    private var cleanedText: String {
        var lines = text.components(separatedBy: "\n")

        // Strip common line-number prefixes like "     1| " or "  42: "
        let lineNumPattern = try? NSRegularExpression(pattern: #"^\s*\d+\s*[|:]\s?"#)
        lines = lines.map { line in
            if let pat = lineNumPattern,
               let m = pat.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                return String(line[Range(m.range, in: line)!.upperBound...])
            }
            return line
        }

        var result = lines.joined(separator: "\n")

        // Strip <think>...</think> and <thinking>...</thinking> wrapper tags
        let tagPatterns = [
            #"<think>\s*"#, #"\s*</think>"#,
            #"<thinking>\s*"#, #"\s*</thinking>"#,
            #"<reasoning>\s*"#, #"\s*</reasoning>"#,
        ]
        for pat in tagPatterns {
            result = result.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Brief preview for collapsed state
    private var preview: String {
        let clean = cleanedText
        let firstLine = clean.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let trimmed = firstLine
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(60)) + (trimmed.count > 60 ? "..." : "")
    }

    private var charCount: String {
        let count = cleanedText.count
        if count > 1000 { return "\(count / 1000)k chars" }
        return "\(count) chars"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(Color.wxAccent)
                    Text("Thinking")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !expanded && !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(charCount)
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        MarkdownView(md: cleanedText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 4)
                            .id("reasoning-bottom")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: cleanedText) { _, _ in
                        proxy.scrollTo("reasoning-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.wxBase.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Tool Call Row

struct ToolCallRow: View {
    let event: ToolCallEvent

    var body: some View {
        HStack(spacing: 6) {
            if event.isComplete {
                Image(systemName: event.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(event.success ? Color.wxAccent : Color(red: 0.7, green: 0.35, blue: 0.35))
                    .font(.caption)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
            Text(event.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if !event.input.isEmpty {
                Text(event.input)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.wxSurface.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(Color.wxAccent)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible.toggle() }
            }
    }
}

struct AssistantBubble: View {
    let msg: ChatMessage
    @State private var copied = false

    var body: some View {
        let blocks = parseMixedContent(msg.content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .text(let t): MarkdownView(md: t)
                case .toolResult(let r): ToolResultCard(result: r)
                case .toolUse(let u): ToolUseCard(use: u)
                }
            }

            if !msg.isStreaming {
                HStack(spacing: 12) {
                    if msg.promptTokens > 0 || msg.completionTokens > 0 {
                        Text("\(msg.promptTokens + msg.completionTokens) tokens")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(msg.content, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Tool Cards

enum ContentBlock { case text(String); case toolUse(ToolUseBlock); case toolResult(ToolResultBlock) }
struct ToolUseBlock { let id: String; let name: String; let input: String }
struct ToolResultBlock { let success: Bool; let output: String; let files: [String] }

struct ToolResultCard: View {
    let result: ToolResultBlock
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? Color.wxAccent : Color(red: 0.7, green: 0.35, blue: 0.35))
                        .font(.caption)
                    Text(result.success ? "Tool succeeded" : "Tool failed")
                        .font(.system(size: 11, weight: .medium))
                    if !result.files.isEmpty {
                        Text("· \(result.files.count) files")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color.wxSurface.opacity(0.5))

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !result.files.isEmpty {
                        ForEach(result.files, id: \.self) { f in
                            Label(f.components(separatedBy: "/").last ?? f, systemImage: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !result.output.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(result.output.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                                    Text(l)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(
                                            l.hasPrefix("+") ? Color(red: 0.45, green: 0.65, blue: 0.45) :
                                            l.hasPrefix("-") ? Color(red: 0.7, green: 0.35, blue: 0.35) :
                                            l.hasPrefix("@@") ? Color.wxAccent : .primary
                                        )
                                        .padding(.horizontal, 4)
                                }
                            }
                            .padding(6)
                        }
                        .background(Color.wxBase)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct ToolUseCard: View {
    let use: ToolUseBlock

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(use.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if !use.input.isEmpty {
                Text(use.input)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            ProgressView()
                .scaleEffect(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.wxSurface.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Markdown Rendering

struct MarkdownView: View {
    let md: String

    var body: some View {
        let doc = Document(parsing: md)
        let children = Array(doc.blockChildren)
        if children.isEmpty {
            ManualMarkdown(md: md)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, b in
                    BlockView(block: b)
                }
            }
        }
    }
}

struct ManualMarkdown: View {
    let md: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(md.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("### ") {
                    Text(String(t.dropFirst(4)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if t.hasPrefix("## ") {
                    Text(String(t.dropFirst(3)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if t.hasPrefix("# ") {
                    Text(String(t.dropFirst(2)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if t == "##" || t == "###" || t == "#" {
                    Spacer().frame(height: 2)
                } else if isRuler(t) {
                    Divider().padding(.vertical, 4)
                } else if t.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    renderInline(t).textSelection(.enabled)
                }
            }
        }
    }

    private func isRuler(_ s: String) -> Bool {
        s.count > 2 && s.allSatisfy({ c in c == "=" || c == "-" || c == "*" || c == "#" || c == "~" })
    }
}

struct BlockView: View {
    let block: BlockMarkup

    var body: some View {
        switch block {
        case let c as CodeBlock:
            let src = c.code.trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 0) {
                if let lang = c.language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(src)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.wxAccent)
                        .padding(8)
                }
            }
            .background(Color.wxBase)
            .clipShape(RoundedRectangle(cornerRadius: 4))

        case let h as Heading:
            renderInline(blockText(h))
                .font(h.level <= 2 ? .system(size: 14, weight: .semibold) : .system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

        case let ul as UnorderedList:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(ul.listItems.enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(.secondary).frame(width: 3, height: 3).padding(.top, 6)
                        renderInline(blockText(c)).font(.system(size: 13))
                    }
                }
            }

        case let ol as OrderedList:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(ol.listItems.enumerated()), id: \.offset) { i, c in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                        renderInline(blockText(c)).font(.system(size: 13))
                    }
                }
            }

        case let q as BlockQuote:
            renderInline(blockText(q))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.wxAccent)
                        .frame(width: 3)
                        .clipShape(Capsule())
                }

        case let t as Markdown.Table:
            ScrollView(.horizontal, showsIndicators: false) {
                let h = t.head.cells.map { blockText($0) }
                let b = t.body.rows.map { $0.cells.map { blockText($0) } }
                let a = [h] + b
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(a.enumerated()), id: \.offset) { ri, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                                Text(c)
                                    .font(.system(size: 11))
                                    .padding(6)
                                    .frame(minWidth: 60, alignment: .leading)
                                    .background(ri == 0 ? Color.wxSurface : .clear)
                                    .overlay(
                                        Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

        case let para as Paragraph:
            let pt = blockText(para)
            if isRulerLine(pt) {
                Divider().padding(.vertical, 2)
            } else {
                renderInline(blockText(para)).textSelection(.enabled)
            }

        case is ThematicBreak:
            Divider()

        default:
            renderInline(blockText(block)).textSelection(.enabled)
        }
    }

    private func blockText(_ m: Markup) -> String {
        var r = ""
        for c in m.children {
            if let t = c as? Markdown.Text { r += t.string }
            else if let ic = c as? InlineCode { r += ic.code }
            else if let s = c as? Strong { r += "**\(blockText(s))**" }
            else if let e = c as? Emphasis { r += "*\(blockText(e))*" }
            else if let ln = c as? Markdown.Link { r += "[\(blockText(ln))] (\(ln.destination ?? ""))" }
            else { r += blockText(c) }
        }
        return r
    }
}

// MARK: - Inline Rendering (robust regex-based parser)

private func renderInline(_ s: String) -> SwiftUI.Text {
    // Tokenize inline markdown using regex patterns
    // Order matters: bold before italic, code before all
    struct Token {
        enum Kind { case plain, bold, italic, boldItalic, code, strikethrough }
        let text: String
        let kind: Kind
    }

    var tokens: [Token] = []
    var remaining = s

    while !remaining.isEmpty {
        // Find the earliest match among all patterns
        var bestRange: Range<String.Index>? = nil
        var bestKind: Token.Kind = .plain
        var bestInner = ""

        // Code: `...`
        if let m = remaining.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .code
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst().dropLast())
            }
        }
        // Bold+Italic: ***...*** or ___...___
        if let m = remaining.range(of: #"\*{3}(.+?)\*{3}"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .boldItalic
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst(3).dropLast(3))
            }
        }
        // Bold: **...** or __...__
        if let m = remaining.range(of: #"\*{2}(.+?)\*{2}"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .bold
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst(2).dropLast(2))
            }
        }
        if let m = remaining.range(of: #"__(.+?)__"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .bold
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst(2).dropLast(2))
            }
        }
        // Italic: *...* or _..._  (single, not preceded/followed by same)
        if let m = remaining.range(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .italic
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst().dropLast())
            }
        }
        // Strikethrough: ~~...~~
        if let m = remaining.range(of: #"~~(.+?)~~"#, options: .regularExpression) {
            if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
                bestRange = m
                bestKind = .strikethrough
                let matched = String(remaining[m])
                bestInner = String(matched.dropFirst(2).dropLast(2))
            }
        }

        guard let range = bestRange else {
            // No more matches — rest is plain text
            tokens.append(Token(text: remaining, kind: .plain))
            break
        }

        // Text before the match
        let before = String(remaining[remaining.startIndex..<range.lowerBound])
        if !before.isEmpty {
            tokens.append(Token(text: before, kind: .plain))
        }
        tokens.append(Token(text: bestInner, kind: bestKind))
        remaining = String(remaining[range.upperBound...])
    }

    // Build SwiftUI.Text from tokens
    var result = SwiftUI.Text("")
    for token in tokens {
        switch token.kind {
        case .plain:
            result = result + SwiftUI.Text(token.text)
        case .bold:
            result = result + SwiftUI.Text(token.text).bold()
        case .italic:
            result = result + SwiftUI.Text(token.text).italic()
        case .boldItalic:
            result = result + SwiftUI.Text(token.text).bold().italic()
        case .code:
            result = result + SwiftUI.Text(token.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(Color.wxAccent)
        case .strikethrough:
            result = result + SwiftUI.Text(token.text).strikethrough()
        }
    }
    return result
}

private func isRulerLine(_ s: String) -> Bool {
    s.count > 2 && s.allSatisfy({ c in c == "=" || c == "-" || c == "*" || c == "#" || c == "~" })
}

func parseMixedContent(_ raw: String) -> [ContentBlock] {
    var blocks = [ContentBlock]()
    var remaining = raw
    while !remaining.isEmpty {
        guard let jsonStart = remaining.firstIndex(of: "{") else {
            let t = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { blocks.append(.text(t)) }
            break
        }
        let textBefore = String(remaining[remaining.startIndex..<jsonStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !textBefore.isEmpty { blocks.append(.text(textBefore)) }
        if let jsonEnd = findMatchingBrace(in: remaining, from: jsonStart) {
            let jsonStr = String(remaining[jsonStart...jsonEnd])
            if let block = parseJSONBlock(jsonStr) { blocks.append(block) }
            remaining = String(remaining[remaining.index(after: jsonEnd)...])
        } else {
            let t = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { blocks.append(.text(t)) }
            break
        }
    }
    return blocks.flatMap { splitToolWarnings($0) }
}

private func findMatchingBrace(in s: String, from start: String.Index) -> String.Index? {
    var depth = 0, inString = false, escaped = false, i = start
    while i < s.endIndex {
        let c = s[i]
        if escaped { escaped = false }
        else if c == "\\" && inString { escaped = true }
        else if c == "\"" { inString.toggle() }
        else if !inString {
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return i } }
        }
        i = s.index(after: i)
    }
    return nil
}

private func parseJSONBlock(_ jsonStr: String) -> ContentBlock? {
    guard let d = jsonStr.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    else { return .text(jsonStr) }
    if let ok = j["success"] as? Bool {
        let out = ((j["diff"] as? String) ?? (j["output"] as? String) ?? "")
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let files = j["files_modified"] as? [String] ?? []
        guard !out.isEmpty || !files.isEmpty else { return nil }
        return .toolResult(ToolResultBlock(success: ok, output: out, files: files))
    }
    if let output = j["output"] as? String {
        let out = output.replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return nil }
        return .toolResult(ToolResultBlock(success: true, output: out, files: []))
    }
    if let analysis = j["analysis"] as? String {
        return .text(analysis.replacingOccurrences(of: "\\n", with: "\n"))
    }
    if j["total_count"] != nil { return nil }
    if let tn = j["tool"] as? String {
        return .toolUse(ToolUseBlock(id: UUID().uuidString, name: tn, input: j["input"] as? String ?? ""))
    }
    return nil
}

private func splitToolWarnings(_ block: ContentBlock) -> [ContentBlock] {
    guard case .text(let t) = block, t.contains("[Tool loop warning") else { return [block] }
    return [.toolResult(ToolResultBlock(
        success: false,
        output: t.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
        files: []
    ))]
}

// MARK: - Shell Utility

func runShell(_ c: String) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-l", "-c", c]
    let o = Pipe(), e = Pipe()
    p.standardOutput = o
    p.standardError = e
    do {
        try p.run()
        p.waitUntilExit()
        return ShellResult(
            o: String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            e: String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            x: p.terminationStatus
        )
    } catch {
        return ShellResult(o: "", e: error.localizedDescription, x: -1)
    }
}

struct ShellResult {
    let o, e: String
    let x: Int32
    var output: String { o }
    var error: String { e }
    var exitCode: Int32 { x }
}
