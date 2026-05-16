import SwiftUI
import Charts

struct DashboardView: View {
    @State private var service = HermesDataService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statCardGrid
                HStack(alignment: .top, spacing: 14) {
                    dailyChartSection
                        .frame(maxWidth: .infinity)
                    platformSection
                        .frame(maxWidth: 260)
                }
                HStack(alignment: .top, spacing: 14) {
                    modelUsageSection
                        .frame(maxWidth: .infinity)
                    quickInfoSection
                        .frame(maxWidth: 280)
                }
            }
            .padding(24)
        }
        .background(Color.wxBase)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Text("Hermes Agent overview and analytics")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let gw = service.gateway, gw.isRunning {
                Label("Gateway Running", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.wxAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.wxAccent.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Label("Gateway Offline", systemImage: "power")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Stat Cards

    private var statCardGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 130), spacing: 10)
        ], spacing: 10) {
            StatCard(
                title: "Sessions",
                value: "\(service.overview.totalSessions)",
                icon: "bubble.left.and.bubble.right.fill",
                color: Color.wxAccent
            )
            StatCard(
                title: "Tokens",
                value: service.overview.totalTokens > 0 ? formatNumber(service.overview.totalTokens) : "—",
                icon: "cpu.fill",
                color: .blue
            )
            StatCard(
                title: "Usage",
                value: {
                    let used = Double(service.overview.totalTokens)
                    let pct = used / 200_000_000 * 100
                    return "\(String(format: "%.1f", pct))%"
                }(),
                icon: "chart.pie",
                color: .purple
            )
            StatCard(
                title: "Active 24h",
                value: "\(service.overview.active24h)",
                icon: "bolt.fill",
                color: .orange
            )
            StatCard(
                title: "Models",
                value: "\(service.overview.models.count)",
                icon: "brain",
                color: .cyan
            )
        }
    }

    // MARK: - Daily Chart

    private var dailyChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Activity Trend", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if service.dailyStats.isEmpty {
                ContentUnavailableView("No Data Yet",
                    systemImage: "chart.bar",
                    description: Text("Activity will appear here once sessions are recorded"))
                    .frame(height: 200)
                    .padding(20)
            } else {
                Chart(service.dailyStats) { day in
                    BarMark(
                        x: .value("Date", day.dateObj ?? Date(), unit: .day),
                        y: .value("Tokens", day.total)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.wxAccent.opacity(0.7), Color.wxAccent.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, service.dailyStats.count / 5))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                            .foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatChartValue(Int(v)))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Platform Distribution

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Platforms", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if service.overview.platforms.isEmpty {
                ContentUnavailableView("No Data", systemImage: "network.slash")
                    .frame(height: 200)
                    .padding(16)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(service.overview.platforms.enumerated()), id: \.offset) { _, platform in
                        let count = service.sessions.filter { $0.platform == platform }.count
                        let fraction = Double(count) / Double(max(service.sessions.count, 1))
                        HStack {
                            Image(systemName: platformIcon(platform))
                                .foregroundStyle(platformColor(platform))
                                .frame(width: 20)
                            Text(platformLabel(platform))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: geo.size.width)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(platformColor(platform).opacity(0.45))
                                .frame(width: geo.size.width * fraction)
                        }
                        .frame(height: 5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Model Usage

    private var modelUsageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Model Usage", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if service.overview.models.isEmpty {
                ContentUnavailableView("No Data", systemImage: "cpu")
                    .frame(height: 160)
                    .padding(16)
            } else {
                Chart {
                    ForEach(Array(modelDistribution.enumerated()), id: \.element.name) { index, item in
                        SectorMark(
                            angle: .value("Sessions", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(modelColors[index % modelColors.count])
                        .cornerRadius(3)
                    }
                }
                .chartLegend(position: .bottom, spacing: 10) {
                    HStack(spacing: 16) {
                        ForEach(Array(modelDistribution.prefix(5).enumerated()), id: \.element.name) { index, item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(modelColors[index % modelColors.count])
                                    .frame(width: 6, height: 6)
                                Text(shortModel(item.name))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Quick Info

    private var quickInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Quick Info", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(spacing: 12) {
                infoRow(icon: "keyboard", title: "Input Tokens",
                        value: service.overview.inputTokens > 0 ? formatNumber(service.overview.inputTokens) : "—")
                infoRow(icon: "text.alignleft", title: "Output Tokens",
                        value: service.overview.outputTokens > 0 ? formatNumber(service.overview.outputTokens) : "—")
                Divider().foregroundStyle(.quaternary)
                infoRow(icon: "cpu", title: "Models Used",
                        value: "\(service.overview.models.count)")
                infoRow(icon: "network", title: "Platforms",
                        value: "\(service.overview.platforms.count)")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Helpers

    private let modelColors: [Color] = [
        Color.wxAccent,
        Color(red: 0.55, green: 0.55, blue: 0.78),
        Color(red: 0.78, green: 0.55, blue: 0.42),
        Color(red: 0.42, green: 0.65, blue: 0.78),
        Color(red: 0.78, green: 0.42, blue: 0.55),
        Color(red: 0.65, green: 0.65, blue: 0.42),
    ]

    private var modelDistribution: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for sess in service.sessions {
            let m = service.model(for: sess.sessionId)
            if !m.isEmpty && m != "—" { counts[m, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private func shortModel(_ m: String) -> String {
        if m.contains("/") { return String(m.split(separator: "/").last ?? Substring(m)) }
        return m.count > 20 ? String(m.prefix(18)) + "…" : m
    }

    private func platformIcon(_ p: String) -> String {
        switch p {
        case "cli": return "terminal"
        case "weixin": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        default: return "globe"
        }
    }

    private func platformLabel(_ p: String) -> String {
        switch p {
        case "cli": return "CLI"
        case "weixin": return "WeChat"
        case "telegram": return "Telegram"
        case "discord": return "Discord"
        default: return p.capitalized
        }
    }

    private func platformColor(_ p: String) -> Color {
        switch p {
        case "cli": return .blue
        case "weixin": return Color.wxAccent
        case "telegram": return .cyan
        case "discord": return .purple
        case "webui": return .orange
        default: return .secondary
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        else if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatChartValue(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.0fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
