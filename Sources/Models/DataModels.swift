import Foundation

// MARK: - Session Index Entry

struct SessionIndexEntry: Codable, Identifiable {
    let sessionKey: String
    let sessionId: String
    let createdAt: String
    let updatedAt: String
    let displayName: String?
    let platform: String
    let chatType: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalTokens: Int
    let lastPromptTokens: Int
    let estimatedCostUsd: Double
    let costStatus: String

    var id: String { sessionId }
    var shortId: String { String(sessionId.prefix(12)) }

    var createdDate: Date? {
        // ISO8601DateFormatter can't handle 6-digit microseconds, use DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        if let d = formatter.date(from: createdAt) { return d }
        // Fallback: try standard ISO format
        let fmt = ISO8601DateFormatter()
        return fmt.date(from: createdAt)
    }

    var platformLabel: String {
        switch platform {
        case "cli": return "终端"
        case "weixin": return "微信"
        default: return platform
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case sessionId = "session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case displayName = "display_name"
        case platform, chatType = "chat_type"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case totalTokens = "total_tokens"
        case lastPromptTokens = "last_prompt_tokens"
        case estimatedCostUsd = "estimated_cost_usd"
        case costStatus = "cost_status"
    }
}

// MARK: - Session Detail

struct SessionDetail: Codable, Identifiable {
    let sessionId: String
    let model: String?
    let baseUrl: String?
    let platform: String?
    let sessionStart: String?
    let lastUpdated: String?
    let systemPrompt: String?
    let tools: [ToolDef]?
    let messages: [Message]?

    var id: String { sessionId }
    var modelDisplay: String { model ?? "—" }
    var msgCount: Int { messages?.count ?? 0 }
    var toolCount: Int { tools?.count ?? 0 }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case model, baseUrl = "base_url", platform
        case sessionStart = "session_start"
        case lastUpdated = "last_updated"
        case systemPrompt = "system_prompt"
        case tools, messages
    }
}

struct ToolDef: Codable {
    let type: String?
    let function: ToolFunc?
}

struct ToolFunc: Codable {
    let name: String?
    let description: String?
}

struct Message: Codable {
    let role: String?
    let content: ContentUnion?
}

enum ContentUnion: Codable {
    case string(String)
    case array([ContentItem])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([ContentItem].self) { self = .array(a) }
        else { self = .string("") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        }
    }
}

struct ContentItem: Codable {
    let type: String?
    let text: String?
}

// MARK: - Gateway

struct GatewayState: Codable {
    let pid: Int?
    let gatewayState: String?
    let activeAgents: Int?
    let platforms: [String: PlatformInfo]?
    let updatedAt: String?

    var isRunning: Bool { gatewayState == "running" }

    enum CodingKeys: String, CodingKey {
        case pid
        case gatewayState = "gateway_state"
        case activeAgents = "active_agents"
        case platforms
        case updatedAt = "updated_at"
    }
}

struct PlatformInfo: Codable {
    let state: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case state, updatedAt = "updated_at"
    }
}

// MARK: - Aggregated

struct OverviewStats {
    var totalSessions = 0
    var totalTokens = 0
    var inputTokens = 0
    var outputTokens = 0
    var costUsd = 0.0
    var active24h = 0
    var gatewayRunning = false
    var models: [String] = []
    var platforms: [String] = []
}

struct DailyStat: Identifiable {
    let date: String
    var id: String { date }
    var sessions = 0
    var input = 0
    var output = 0
    var total = 0
    var cost = 0.0

    var dateObj: Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }
}

struct SkillItem: Identifiable {
    let name: String
    let desc: String
    let path: String
    var id: String { name }
}

struct CronItem: Identifiable {
    let name: String
    let schedule: String
    let enabled: Bool
    let status: String
    var id: String { name }
}
