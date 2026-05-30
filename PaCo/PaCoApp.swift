import AppKit
import SwiftUI
import SwiftData
import PaCoShared

/// Ensures the main window is always visible:
/// - On launch, if no visible windows exist (closed last session), opens the window.
/// - When Dock icon is clicked with no visible windows, opens the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeWindowVisible()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            makeWindowVisible()
        }
        return true
    }

    private func makeWindowVisible() {
        // Give SwiftUI a chance to create its window first
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { !$0.isMiniaturized }) {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } else if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}

@main
struct PaCoApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
        WindowGroup {
            ContentView()
                .environment(appState)
                .environmentObject(daemonClient)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    appState.determineMode(context: context)
                    daemonClient.connect()
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 900, height: 700)
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
