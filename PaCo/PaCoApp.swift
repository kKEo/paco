import AppKit
import SwiftUI
import SwiftData
import PaCoShared

@main
struct PaCoApp: App {

    @State private var appState = AppState()
    @StateObject private var daemonClient = DaemonXPCClient()
    @StateObject private var bonjour = BonjourService()
    @State private var usageWatcher: DispatchSourceFileSystemObject?
    @State private var eventsWatcher: DispatchSourceFileSystemObject?
    @StateObject private var eventTracker = EventTracker()

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
                .environmentObject(bonjour)
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
                    startEventsWatcher(context: context)
                    // NOTE: determineMode(context:) is synchronous — appState.mode is fully resolved
                    // by the call above. This mode check must remain after determineMode.
                    // If determineMode ever becomes async, move advertising setup into its completion.
                    if appState.mode == .child {
                        let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
                        bonjour.startAdvertising(name: deviceName)
                        bonjour.onIncomingMessage = { message in
                            handleChildIncoming(message)
                        }
                    } else if appState.mode == .parent {
                        // Handle time-extension requests arriving from any paired child.
                        bonjour.onChildRequest = { message, identity in
                            handleParentIncoming(message, from: identity, context: context)
                        }
                        // On connect, provision the parent PIN to the child so its
                        // "Parent Access" can be verified locally.
                        bonjour.onParentConnected = { identity in
                            guard let pin = try? PINManager.exportPIN() else { return }
                            let payload = PINProvisionTransfer(hash: pin.hash, salt: pin.salt)
                            if let data = try? JSONEncoder().encode(payload) {
                                bonjour.send(PaCoMessage(command: .provisionPIN, payload: data), to: identity)
                            }
                        }
                    }
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

    private func startEventsWatcher(context: ModelContext) {
        let url = PaCoFiles.eventsFileURL
        try? FileManager.default.createDirectory(at: PaCoFiles.baseDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [self] in
            processNewEvents(context: context)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        eventsWatcher = source
    }

    /// Parent-side handling of child-initiated messages (cross-Mac requests).
    private func handleParentIncoming(_ message: PaCoMessage, from identity: String, context: ModelContext) {
        guard message.command == .requestExtension,
              let data = message.payload,
              let payload = try? JSONDecoder().decode(ExtensionRequestPayload.self, from: data) else { return }
        DispatchQueue.main.async {
            let requestId = payload.requestId
            let existing = (try? context.fetch(FetchDescriptor<TimeExtensionRequest>()))?.first { $0.id == requestId }
            guard existing == nil else { return }
            let req = TimeExtensionRequest(
                id: requestId,
                childDeviceName: payload.childDeviceName.isEmpty ? identity : payload.childDeviceName,
                requestedMinutes: payload.requestedMinutes,
                reason: payload.reason
            )
            context.insert(req)
            try? context.save()
        }
    }

    /// Child-side handling of parent-initiated messages over the authenticated channel.
    private func handleChildIncoming(_ message: PaCoMessage) {
        switch message.command {
        case .approveExtension:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data),
                  ChildRequestLog.shared.consume(payload.requestId) else {
                PaCoLogger.app.warning("Ignoring approveExtension: unknown or replayed request id")
                return
            }
            let minutes = payload.grantedMinutes ?? 30
            OverrideStore.write(InternetOverride(
                requestId: payload.requestId,
                grantedUntil: Date().addingTimeInterval(TimeInterval(minutes * 60))
            ))
            PaCoLogger.app.info("Extension approved: granted \(minutes) min (agent will enable)")

        case .denyExtension:
            if let data = message.payload,
               let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data) {
                _ = ChildRequestLog.shared.consume(payload.requestId)
            }
            PaCoLogger.app.info("Extension denied by parent")

        case .provisionPIN:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(PINProvisionTransfer.self, from: data) else { return }
            try? PINManager.storeProvisionedPIN(hash: payload.hash, salt: payload.salt)
            PaCoLogger.app.info("Parent PIN provisioned to this child")

        default:
            break
        }
    }

    private func processNewEvents(context: ModelContext) {
        guard let data = try? Data(contentsOf: PaCoFiles.eventsFileURL),
              let events = try? JSONDecoder().decode([NotificationEvent].self, from: data)
        else { return }

        for event in events where !eventTracker.seenIds.contains(event.id) {
            eventTracker.seenIds.insert(event.id)
            guard event.kind == .extensionRequested else { continue }
            let childName = event.payload["childDeviceName"] ?? "Unknown Device"
            let minutes = Int(event.payload["requestedMinutes"] ?? "30") ?? 30
            let reason = event.payload["reason"] ?? ""
            let requestId = UUID(uuidString: event.payload["requestId"] ?? "") ?? UUID()
            let existing = (try? context.fetch(FetchDescriptor<TimeExtensionRequest>()))?.first { $0.id == requestId }
            guard existing == nil else { continue }
            let req = TimeExtensionRequest(
                id: requestId,
                childDeviceName: childName,
                requestedMinutes: minutes,
                reason: reason
            )
            context.insert(req)
            try? context.save()
        }
    }
}

/// Tracks seen event IDs across closure captures.
final class EventTracker: ObservableObject {
    var seenIds: Set<UUID> = []
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
