import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case profiles = "Profiles"
    case schedules = "Schedules"
    case appRules = "App Rules"
    case usage = "Usage"
    case devices = "Devices"
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
        case .settings: "gear"
        }
    }
}

struct DashboardView: View {
    @State private var selectedTab: DashboardTab = .home

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("PaCo")
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
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
