import SwiftUI

@main
struct HermesVizApp: App {
    @State private var service = HermesDataService.shared
    @StateObject private var setup = SetupService()
    @State private var selectedTab: Tab = .chat
    @State private var isConfigured: Bool = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.hermes/config.yaml")

    enum Tab: String, CaseIterable {
        case chat = "Chat"
        case dashboard = "Home"
        case sessions = "Sessions"
        case analytics = "Analytics"
        case skills = "Skills"
        case cron = "Tasks"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .chat: "bubble.left.and.bubble.right.fill"
            case .dashboard: "house"
            case .sessions: "clock"
            case .analytics: "chart.bar"
            case .skills: "star"
            case .cron: "calendar"
            case .settings: "gearshape"
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !setup.isInstalled {
                    OnboardingView(setup: setup)
                        .transition(.opacity)
                } else if !isConfigured {
                    ConfigWizardView(onComplete: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isConfigured = true
                        }
                    })
                        .transition(.opacity)
                } else {
                    NavigationSplitView {
                        sidebar
                    } detail: {
                        tabContent
                            .navigationTitle("")
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button {
                                        service.refresh()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .disabled(service.isLoading)
                                    .keyboardShortcut("r", modifiers: .command)
                                    .help("Refresh data")
                                }
                            }
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 460)
            .task {
                if setup.isInstalled && isConfigured {
                    service.refresh()
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.wxAccent)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text("Hermes")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Navigation
            VStack(spacing: 1) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // Gateway status
            HStack(spacing: 6) {
                Circle()
                    .fill(service.gateway?.isRunning == true ? Color.wxAccent : .red.opacity(0.7))
                    .frame(width: 6, height: 6)
                Text(service.gateway?.isRunning == true ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color.wxSurface)
    }

    private func sidebarRow(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.wxAccent : .secondary)
                Text(tab.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if tab == .chat && service.gateway?.isRunning == true {
                    Circle()
                        .fill(Color.wxAccent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 6).fill(Color.wxAccent.opacity(0.15))
                    : RoundedRectangle(cornerRadius: 6).fill(.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .chat: ChatView()
        case .dashboard: DashboardView()
        case .sessions: SessionsView()
        case .analytics: AnalyticsView()
        case .skills: SkillsView()
        case .cron: CronView()
        case .settings: SettingsView()
        }
    }
}
