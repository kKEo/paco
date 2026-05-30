import AppKit
import SwiftUI
import SwiftData
import PaCoShared

@main
struct PaCoApp: App {

    @State private var appState = AppState()
    @StateObject private var daemonClient = DaemonXPCClient()
    @State private var usageWatcher: DispatchSourceFileSystemObject?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            Schedule.self,
            AppRestriction.self,
            UsageRecord.self,
            PairingInfo.self,
            DeviceConfig.self,
            TimeExtensionRequest.self,
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
                    // Sync all data to shared JSON files so the agent always has current data
                    let allSchedules = (try? context.fetch(FetchDescriptor<Schedule>())) ?? []
                    let allRestrictions = (try? context.fetch(FetchDescriptor<AppRestriction>())) ?? []
                    let config = (try? context.fetch(FetchDescriptor<DeviceConfig>()))?.first
                    SyncManager.shared.syncSchedules(allSchedules)
                    SyncManager.shared.syncRestrictions(allRestrictions)
                    SyncManager.shared.syncDeviceConfig(activeProfileId: config?.childProfileId)
                    startUsageWatcher(context: context)
                    SyncManager.shared.readUsage(context: context)
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

    private func startUsageWatcher(context: ModelContext) {
        let url = SyncManager.shared.usageFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler {
            SyncManager.shared.readUsage(context: context)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        usageWatcher = source
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
