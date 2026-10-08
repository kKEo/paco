import AppKit
import SwiftUI
import SwiftData
import PaCoShared

@main
struct PaCoApp: App {

    /// All services and startup live in the delegate so they run once at launch,
    /// not on every popover open. See AppDelegate.swift.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appDelegate.appState)
                .environmentObject(appDelegate.daemonClient)
                .environmentObject(appDelegate.bonjour)
        } label: {
            MenuBarIcon(daemonClient: appDelegate.daemonClient)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(appDelegate.modelContainer)
    }
}

/// The menu bar icon — updates color/symbol based on internet state.
struct MenuBarIcon: View {
    @ObservedObject var daemonClient: DaemonXPCClient

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(iconColor)
    }

    private var symbolName: String {
        if !daemonClient.isConnected { return "shield.slash" }
        return daemonClient.isInternetEnabled ? "shield.checkered" : "shield.slash"
    }

    private var iconColor: Color {
        if !daemonClient.isConnected { return .secondary }
        return daemonClient.isInternetEnabled ? .green : .red
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.mode {
        case .onboarding:
            RoleSelectionView()
        case .parent:
            // The dashboard is PIN-gated: anyone can open the menu bar popover,
            // so the parent PIN is required every time it is shown.
            if appState.isUnlocked {
                DashboardView()
            } else {
                ParentUnlockView()
            }
        case .child:
            ChildModeView()
        }
    }
}
