import SwiftUI
import Charts

struct AnalyticsView: View {
    @State private var service = HermesDataService.shared
    @State private var selectedMetric: MetricType = .tokens

    enum MetricType: String, CaseIterable {
        case tokens = "Tokens"
        case sessions = "Sessions"
        case cost = "Cost"
    }

    private let chartPalette: [Color] = [
        Color.wxAccent,
        Color(red: 0.55, green: 0.55, blue: 0.78),
        Color(red: 0.78, green: 0.55, blue: 0.42),
        Color(red: 0.42, green: 0.65, blue: 0.78),
        Color(red: 0.78, green: 0.42, blue: 0.55),
        Color(red: 0.65, green: 0.65, blue: 0.42),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analytics")
                            .font(.largeTitle.bold())
                        Text("Usage patterns and trends")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(MetricType.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                // Main trend chart
                trendChartSection

                // Bottom row
                HStack(alignment: .top, spacing: 16) {
                    modelDistributionSection
                    platformBreakdownSection
                    tokenRatioSection
                }
            }
            .padding(24)
        }
        .background(Color.wxBase)
    }

    // MARK: - Trend Chart

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Activity Trend", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                if let first = service.dailyStats.first?.dateObj,
                   let last = service.dailyStats.last?.dateObj {
                    Text(first.formatted(date: .abbreviated, time: .omitted) + " – " + last.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if service.dailyStats.isEmpty {
                ContentUnavailableView("No Data Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Analytics will appear once activity is recorded"))
                    .frame(height: 240)
                    .padding(20)
            } else {
                Chart {
                    ForEach(service.dailyStats) { day in
                        let yValue: Double = {
                            switch selectedMetric {
                            case .tokens: return Double(day.total)
                            case .sessions: return Double(day.sessions)
                            case .cost: return day.cost
                            }
                        }()

                        LineMark(
                            x: .value("Date", day.dateObj ?? Date(), unit: .day),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                        .foregroundStyle(Color.wxAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", day.dateObj ?? Date(), unit: .day),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.wxAccent.opacity(0.2), Color.wxAccent.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", day.dateObj ?? Date(), unit: .day),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                        .foregroundStyle(Color.wxAccent)
                        .symbolSize(18)
                    }
                }
                .chartXAxis {
                    let count = service.dailyStats.count
                    let stride = max(1, count / 8)
                    AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 280)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Model Distribution

    private var modelDistributionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Model Usage", systemImage: "cpu")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if modelDistribution.isEmpty {
                ContentUnavailableView("No Data", systemImage: "cpu")
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(16)
            } else {
                Chart {
                    ForEach(Array(modelDistribution.enumerated()), id: \.element.name) { index, item in
                        SectorMark(
                            angle: .value("Sessions", item.count),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(chartPalette[index % chartPalette.count])
                        .cornerRadius(4)
                        .annotation(position: .overlay) {
                            if item.count > 2 {
                                Text("\(item.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8) {
                    VStack(spacing: 6) {
                        ForEach(Array(modelDistribution.prefix(6).enumerated()), id: \.element.name) { index, item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(chartPalette[index % chartPalette.count])
                                    .frame(width: 7, height: 7)
                                Text(shortModel(item.name))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 220)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Platform Breakdown

    private var platformBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("By Platform", systemImage: "network")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if platformBreakdown.isEmpty {
                ContentUnavailableView("No Data", systemImage: "network.slash")
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(16)
            } else {
                VStack(spacing: 10) {
                    ForEach(platformBreakdown, id: \.name) { item in
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: platformIcon(item.name))
                                    .foregroundStyle(platformColor(item.name))
                                    .frame(width: 16)
                                Text(platformLabel(item.name))
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.subheadline.weight(.semibold))
                                Text("(\(item.percent)%)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.04))
                                    .frame(width: geo.size.width)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(platformColor(item.name).opacity(0.5))
                                    .frame(width: geo.size.width * Double(item.percent) / 100)
                            }
                            .frame(height: 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Token Ratio

    private var tokenRatioSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Token Ratio", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            let total = service.overview.inputTokens + service.overview.outputTokens
            if total == 0 {
                ContentUnavailableView("No Data", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(16)
            } else {
                let inputPct = Double(service.overview.inputTokens) / Double(total) * 100
                let outputPct = Double(service.overview.outputTokens) / Double(total) * 100

                VStack(spacing: 14) {
                    // Visual bar
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(chartPalette[0])
                                .frame(width: geo.size.width * inputPct / 100)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(chartPalette[1])
                                .frame(width: geo.size.width * outputPct / 100)
                            if inputPct + outputPct < 100 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                            }
                        }
                    }
                    .frame(height: 28)

                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(chartPalette[0]).frame(width: 8, height: 8)
                            Text("Input")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", inputPct))%")
                                .font(.caption.weight(.semibold))
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(chartPalette[1]).frame(width: 8, height: 8)
                            Text("Output")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", outputPct))%")
                                .font(.caption.weight(.semibold))
                        }
                    }

                    // Token counts
                    HStack {
                        Text(formatTokens(service.overview.inputTokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTokens(service.overview.outputTokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var modelDistribution: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for sess in service.sessions {
            let m = service.model(for: sess.sessionId)
            if !m.isEmpty && m != "—" { counts[m, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private var platformBreakdown: [(name: String, count: Int, percent: Int)] {
        var counts: [String: Int] = [:]
        for sess in service.sessions { counts[sess.platform, default: 0] += 1 }
        let total = max(counts.values.reduce(0, +), 1)
        return counts.map { (name: $0.key, count: $0.value, percent: Int(Double($0.value) / Double(total) * 100)) }
            .sorted { $0.count > $1.count }
    }

    private func shortModel(_ m: String) -> String {
        if m.contains("/") { return String(m.split(separator: "/").last ?? Substring(m)) }
        return m.count > 18 ? String(m.prefix(16)) + "…" : m
    }

    private func platformIcon(_ p: String) -> String {
        switch p {
        case "cli": return "terminal"
        case "weixin": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        case "webui": return "globe"
        default: return "questionmark.circle"
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

    private func platformLabel(_ p: String) -> String {
        switch p {
        case "cli": return "CLI"
        case "weixin": return "WeChat"
        case "telegram": return "Telegram"
        case "discord": return "Discord"
        case "webui": return "Web UI"
        default: return p.capitalized
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
