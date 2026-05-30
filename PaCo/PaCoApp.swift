import AppKit
import SwiftUI
import SwiftData
import PaCoShared

@main
struct PaCoApp: App {

    @State private var appState = AppState()
    @StateObject private var daemonClient = DaemonXPCClient()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            Schedule.self,
            AppRestriction.self,
            UsageRecord.self,
            PairingInfo.self,
            DeviceConfig.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
                .environmentObject(daemonClient)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    appState.determineMode(context: context)
                    daemonClient.connect()
                }
        } label: {
            MenuBarIcon(
                isInternetEnabled: daemonClient.isInternetEnabled,
                isConnected: daemonClient.isConnected
            )
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}

/// The menu bar icon — updates color/symbol based on internet state.
struct MenuBarIcon: View {
    let isInternetEnabled: Bool
    let isConnected: Bool

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(iconColor)
    }

    private var symbolName: String {
        if !isConnected { return "shield.slash" }
        return isInternetEnabled ? "shield.checkered" : "shield.slash"
    }

    private var iconColor: Color {
        if !isConnected { return .secondary }
        return isInternetEnabled ? .green : .red
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.mode {
        case .onboarding:
            RoleSelectionView()
        case .parent:
            DashboardView()
        case .child:
            ChildModeView()
        }
    }
}
