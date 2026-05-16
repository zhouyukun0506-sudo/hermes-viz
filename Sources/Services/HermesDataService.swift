import Foundation
import Yams

@Observable
final class HermesDataService {
    static let shared = HermesDataService()

    private let home: URL
    private let sessionsDir: URL
    private let indexFile: URL
    private let gatewayFile: URL
    private let configFile: URL
    private let skillsDir: URL
    private let cronDir: URL

    private(set) var sessions: [SessionIndexEntry] = []
    private(set) var overview: OverviewStats = .init()
    private(set) var dailyStats: [DailyStat] = []
    private(set) var gateway: GatewayState?
    private(set) var skills: [SkillItem] = []
    private(set) var crons: [CronItem] = []
    private(set) var isLoading = false

    private var modelCache: [String: String] = [:]

    // MARK: - Init

    private init() {
        let hermesEnv = ProcessInfo.processInfo.environment["HERMES_HOME"]
        if let env = hermesEnv {
            home = URL(fileURLWithPath: env)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hermes")
        }

        sessionsDir = home.appendingPathComponent("sessions")
        indexFile = sessionsDir.appendingPathComponent("sessions.json")
        gatewayFile = home.appendingPathComponent("gateway_state.json")
        configFile = home.appendingPathComponent("config.yaml")
        skillsDir = home.appendingPathComponent("skills")
        cronDir = home.appendingPathComponent("cron")
    }

    // MARK: - Refresh

    func refresh() {
        isLoading = true
        defer { isLoading = false }
        loadSessions()
        loadGateway()
        loadSkills()
        loadCron()
        computeOverview()
        computeDailyStats()
    }

    // MARK: - Sessions (index + directory scan)

    private func loadSessions() {
        let fm = FileManager.default
        var indexed: [String: SessionIndexEntry] = [:]

        // 1. Read sessions.json index (accurate token counts)
        if let data = try? Data(contentsOf: indexFile),
           let raw = try? JSONDecoder().decode([String: SessionIndexEntry].self, from: data) {
            for (_, entry) in raw {
                indexed[entry.sessionId] = entry
            }
        }

        // 2. Scan all session_*.json files
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey])
        else { sessions = []; return }

        var discovered: [SessionIndexEntry] = []

        for url in files {
            let name = url.lastPathComponent
            guard name.hasPrefix("session_"),
                  name.hasSuffix(".json"),
                  name != "sessions.json"
            else { continue }

            guard let sdata = try? Data(contentsOf: url),
                  let detail = try? JSONDecoder().decode(SessionDetail.self, from: sdata)
            else { continue }

            let sid = detail.sessionId
            modelCache[sid] = detail.model ?? "—"

            if let entry = indexed[sid] {
                discovered.append(entry)
                indexed.removeValue(forKey: sid)
            } else {
                let created = detail.sessionStart ?? ""
                // Estimate tokens from message content (~3 chars/token)
                let est = Self.estimateTokens(from: detail.messages ?? [])
                let model = detail.model ?? "unknown"
                let cost = Self.estimateCost(model: model, inputTokens: est.input, outputTokens: est.output)
                discovered.append(SessionIndexEntry(
                    sessionKey: "file:\(sid)",
                    sessionId: sid,
                    createdAt: created,
                    updatedAt: detail.lastUpdated ?? created,
                    displayName: nil,
                    platform: detail.platform ?? "unknown",
                    chatType: "dm",
                    inputTokens: est.input,
                    outputTokens: est.output,
                    cacheReadTokens: 0, cacheWriteTokens: 0,
                    totalTokens: est.input + est.output, lastPromptTokens: 0,
                    estimatedCostUsd: cost,
                    costStatus: "estimated"
                ))
            }
        }

        // Remaining index entries
        for (_, entry) in indexed { discovered.append(entry) }

        discovered.sort { ($0.createdAt) > ($1.createdAt) }
        self.sessions = discovered
    }

    func detail(for sessionId: String) -> SessionDetail? {
        for url in [
            sessionsDir.appendingPathComponent("session_\(sessionId).json"),
            sessionsDir.appendingPathComponent("\(sessionId).json")
        ] {
            if let data = try? Data(contentsOf: url),
               let detail = try? JSONDecoder().decode(SessionDetail.self, from: data) {
                return detail
            }
        }
        return nil
    }

    func model(for sessionId: String) -> String {
        modelCache[sessionId] ?? "—"
    }

    // MARK: - Token Estimation

    private static func estimateTokens(from messages: [Message]) -> (input: Int, output: Int) {
        var inputChars = 0
        var outputChars = 0
        for msg in messages {
            var text = ""
            switch msg.content {
            case .string(let s): text = s
            case .array(let items): text = items.compactMap { $0.text }.joined(separator: "\n")
            case .none: break
            }
            let chars = text.count
            // user, tool, system = input (context the model reads)
            // assistant = output (what the model generates)
            if msg.role == "assistant" {
                outputChars += chars
            } else {
                inputChars += chars
            }
        }
        // Rough estimate: 1 token ≈ 3 chars (mix of English + Chinese)
        let inputTokens = max(1, inputChars / 3)
        let outputTokens = max(1, outputChars / 3)
        return (inputTokens, outputTokens)
    }

    // MARK: - Cost Estimation (MiMo Token Plan ¥99/month, 200M tokens)

    private static let monthlyPlanPrice: Double = 99.0      // ¥99/月
    private static let monthlyPlanTokens: Double = 200_000_000  // 200M tokens

    private static func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        // Fixed monthly subscription cost
        return monthlyPlanPrice
    }

    // MARK: - Gateway

    private func loadGateway() {
        guard let data = try? Data(contentsOf: gatewayFile),
              let gw = try? JSONDecoder().decode(GatewayState.self, from: data)
        else { return }
        self.gateway = gw
    }

    // MARK: - Skills

    private func loadSkills() {
        var result: [SkillItem] = []
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil)
        else { skills = result; return }

        for url in contents {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let skillMd = url.appendingPathComponent("SKILL.md")
            var desc = ""
            if let text = try? String(contentsOf: skillMd, encoding: .utf8) {
                desc = text.components(separatedBy: "\n").first?
                    .replacingOccurrences(of: "# ", with: "")
                    .trimmingCharacters(in: .whitespaces) ?? ""
            }
            result.append(SkillItem(name: url.lastPathComponent, desc: desc, path: url.path))
        }
        skills = result
    }

    // MARK: - Cron

    private func loadCron() {
        var result: [CronItem] = []
        if let contents = try? FileManager.default
            .contentsOfDirectory(at: cronDir, includingPropertiesForKeys: nil) {
            for url in contents where ["yaml", "yml", "json"].contains(url.pathExtension) {
                result.append(CronItem(name: url.deletingPathExtension().lastPathComponent,
                    schedule: "", enabled: true, status: "configured"))
            }
        }
        let crontab = home.appendingPathComponent("crontab.json")
        if let data = try? Data(contentsOf: crontab),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in list {
                result.append(CronItem(
                    name: entry["name"] as? String ?? entry["id"] as? String ?? "—",
                    schedule: entry["schedule"] as? String ?? entry["cron"] as? String ?? "",
                    enabled: entry["enabled"] as? Bool ?? true,
                    status: entry["status"] as? String ?? "unknown"))
            }
        }
        crons = result
    }

    // MARK: - Stats

    private func computeOverview() {
        var s = OverviewStats()
        s.totalSessions = sessions.count
        s.gatewayRunning = gateway?.isRunning ?? false
        var models = Set<String>()
        var platforms = Set<String>()
        let now = Date()
        let cutoff = now.addingTimeInterval(-86400)

        for sess in sessions {
            s.inputTokens += sess.inputTokens
            s.outputTokens += sess.outputTokens
            s.totalTokens += sess.totalTokens
            s.costUsd += sess.estimatedCostUsd
            if let m = modelCache[sess.sessionId] { models.insert(m) }
            platforms.insert(sess.platform)
            if let d = sess.createdDate, d > cutoff { s.active24h += 1 }
        }
        s.models = models.sorted()
        s.platforms = platforms.sorted()
        overview = s
    }

    private func computeDailyStats() {
        var daily: [String: DailyStat] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for sess in sessions {
            guard let date = sess.createdDate else { continue }
            let key = fmt.string(from: date)
            var ds = daily[key] ?? DailyStat(date: key)
            ds.sessions += 1
            ds.input += sess.inputTokens
            ds.output += sess.outputTokens
            ds.total += sess.totalTokens
            ds.cost += sess.estimatedCostUsd
            daily[key] = ds
        }
        dailyStats = daily.values.sorted { $0.date < $1.date }
    }
}
