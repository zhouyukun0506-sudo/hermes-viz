import SwiftUI

struct CronView: View {
    @State private var service = HermesDataService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled Tasks")
                        .font(.largeTitle.bold())
                    Text("\(service.crons.count) configured jobs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            if service.crons.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Tasks",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Set up cron jobs in Hermes and they will appear here")
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(service.crons) { job in
                            CronCard(job: job)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color.wxBase)
    }
}

struct CronCard: View {
    let job: CronItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 16, weight: .semibold))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    if !job.schedule.isEmpty {
                        Label(job.schedule, systemImage: "clock")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Label(job.enabled ? "Enabled" : "Disabled", systemImage: job.enabled ? "checkmark.circle" : "pause.circle")
                        .font(.caption)
                        .foregroundStyle(job.enabled ? .green : .secondary)
                }
            }

            Spacer()

            // Status badge
            Text(job.status.capitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.accentColor.opacity(0.2) : .clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.02), radius: 4, x: 0, y: 2)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var statusColor: Color {
        switch job.status {
        case "running": return .orange
        case "enabled", "configured": return .green
        case "failed", "error": return .red
        default: return .secondary
        }
    }

    private var statusIcon: String {
        switch job.status {
        case "running": return "arrow.triangle.2.circlepath"
        case "enabled", "configured": return "checkmark.circle.fill"
        case "failed", "error": return "exclamationmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
}
