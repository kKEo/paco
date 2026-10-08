import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case profiles = "Profiles"
    case schedules = "Schedules"
    case appRules = "App Rules"
    case usage = "Usage"
    case devices = "Devices"
    case requests = "Requests"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .profiles: "person.2"
        case .schedules: "clock"
        case .appRules: "app.badge.checkmark"
        case .usage: "chart.bar"
        case .devices: "laptopcomputer"
        case .requests: "clock.badge.questionmark"
        case .settings: "gear"
        }
    }
}

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: DashboardTab = .home

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("PaCo")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit PaCo", systemImage: "power")
                    }
                    .help("Quit PaCo")
                }
            }
        } detail: {
            switch selectedTab {
            case .home:
                HomeView()
            case .profiles:
                ProfilesView()
            case .schedules:
                SchedulesView()
            case .appRules:
                AppRulesView()
            case .usage:
                UsageView()
            case .devices:
                DevicesView()
            case .requests:
                RequestsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        // Popover closed (or child device leaving parent mode): require the PIN again.
        .onDisappear { appState.lock() }
    }
}
