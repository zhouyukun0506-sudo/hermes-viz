import SwiftUI

struct SessionsView: View {
    @State private var service = HermesDataService.shared
    @State private var searchText = ""
    @State private var selectedDetail: SessionDetail?
    @State private var selectedPlatform: String = "All"
    private var platforms: [String] {
        ["All"] + service.overview.platforms
    }

    private var filtered: [SessionIndexEntry] {
        let result = service.sessions.filter { sess in
            let matchSearch = searchText.isEmpty ||
                sess.sessionId.localizedCaseInsensitiveContains(searchText) ||
                (sess.displayName ?? "").localizedCaseInsensitiveContains(searchText) ||
                service.model(for: sess.sessionId).localizedCaseInsensitiveContains(searchText)
            let matchPlatform = selectedPlatform == "All" || sess.platform == selectedPlatform
            return matchSearch && matchPlatform
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search sessions...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Platform filter
                Picker("", selection: $selectedPlatform) {
                    ForEach(platforms, id: \.self) { p in
                        Text(p == "All" ? "All Platforms" : p).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                Text("\(filtered.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Table
            Table(filtered) {
                TableColumn("Date") { sess in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(sess))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(formatDateShort(sess.createdDate))
                                .font(.caption)
                            Text(formatTimeShort(sess.createdDate))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .width(120)

                TableColumn("Session") { sess in
                    Text(sess.shortId)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .width(100)

                TableColumn("Platform") { sess in
                    Label(sess.platformLabel, systemImage: platformIcon(sess.platform))
                        .font(.caption)
                        .foregroundStyle(platformColor(sess.platform))
                }
                .width(90)

                TableColumn("Model") { sess in
                    let m = service.model(for: sess.sessionId)
                    Text(shortModel(m))
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
                .width(140)

                TableColumn("Tokens") { sess in
                    HStack(spacing: 4) {
                        if sess.totalTokens > 0 {
                            Text(formatTokens(sess.totalTokens))
                                .font(.caption.monospacedDigit())
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .width(70)

                TableColumn("Cost") { sess in
                    if sess.estimatedCostUsd > 0 {
                        Text("¥\(String(format: "%.2f", sess.estimatedCostUsd))")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(75)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let sid = ids.first {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sid, forType: .string)
                    } label: {
                        Label("Copy Session ID", systemImage: "doc.on.doc")
                    }
                    Button {
                        if let url = URL(string: "https://hermes.nousresearch.com/sessions/\(sid)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open in Hermes", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
        .background(Color.wxBase)
    }

    private func statusColor(_ sess: SessionIndexEntry) -> Color {
        if let d = sess.createdDate {
            if d.timeIntervalSinceNow > -3600 { return .green }
            if d.timeIntervalSinceNow > -86400 { return .yellow }
        }
        return .secondary
    }

    private func formatDateShort(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func formatTimeShort(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func platformIcon(_ p: String) -> String {
        switch p {
        case "cli": return "terminal"
        case "weixin": return "message.fill"
        default: return "globe"
        }
    }

    private func platformColor(_ p: String) -> Color {
        switch p {
        case "cli": return .blue
        case "weixin": return .green
        default: return .secondary
        }
    }

    private func shortModel(_ m: String) -> String {
        if m.count <= 20 { return m }
        return String(m.prefix(18)) + "…"
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
