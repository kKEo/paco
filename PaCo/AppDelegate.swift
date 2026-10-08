import AppKit
import SwiftUI
import SwiftData
import PaCoShared

/// Owns the long-lived services and runs startup exactly once, at launch.
///
/// Startup used to live in the MenuBarExtra content's `onAppear`. With the
/// `.window` style that fires only when the popover is first opened (so a child
/// Mac did not advertise until someone clicked the icon) and again on every open
/// (leaking an XPC connection and a file watcher each time).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let appState = AppState()
    let daemonClient = DaemonXPCClient()
    let bonjour = BonjourService()
    let modelContainer: ModelContainer

    private var usageWatcher: DispatchSourceFileSystemObject?
    private var eventsWatcher: DispatchSourceFileSystemObject?
    private var seenEventIds: Set<UUID> = []
    private var configuredRole: DeviceRole?
    private let logger = PaCoLogger.app

    override init() {
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
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        super.init()
    }

    private var context: ModelContext { modelContainer.mainContext }

    static var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.determineMode(context: context)
        daemonClient.connect()
        // Sync all policy to the shared JSON files so the agent always has current data.
        SyncManager.shared.syncAll(context: context)
        startUsageWatcher()
        SyncManager.shared.readUsage(context: context)
        startEventsWatcher()
        configureRole()
        observeRole()
        logger.info("Startup complete")
    }

    /// Safety net for the PIN gate: whenever PaCo stops being the active app the
    /// parent dashboard re-locks (the popover closing also triggers `lock()`).
    func applicationDidResignActive(_ notification: Notification) {
        appState.lock()
    }

    // MARK: - Role-dependent networking

    /// Idempotent per role. Re-run when `appState.role` changes (onboarding
    /// completes) so no relaunch is needed.
    private func configureRole() {
        guard let role = appState.role, role != configuredRole else { return }
        configuredRole = role
        switch role {
        case .child:
            bonjour.onIncomingMessage = { [weak self] message in
                self?.handleChildIncoming(message)
            }
            bonjour.startAdvertising(name: Self.deviceName)
        case .parent:
            // Handle time-extension requests arriving from any paired child.
            bonjour.onChildRequest = { [weak self] message, identity in
                self?.handleParentIncoming(message, from: identity)
            }
            // On connect, provision the parent PIN to the child so its
            // "Parent Access" can be verified locally.
            bonjour.onParentConnected = { [weak self] identity in
                self?.provisionPIN(to: identity)
            }
            bonjour.startBrowsing()
        }
    }

    private func observeRole() {
        withObservationTracking {
            _ = appState.role
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.configureRole()
                self?.observeRole()
            }
        }
    }

    private func provisionPIN(to identity: String) {
        guard let pin = try? PINManager.exportPIN() else { return }
        let payload = PINProvisionTransfer(hash: pin.hash, salt: pin.salt)
        if let data = try? JSONEncoder().encode(payload) {
            bonjour.send(PaCoMessage(command: .provisionPIN, payload: data), to: identity)
        }
    }

    // MARK: - File watchers (agent → app)

    private func makeWatcher(for url: URL, handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func startUsageWatcher() {
        usageWatcher?.cancel()
        usageWatcher = makeWatcher(for: SyncManager.shared.usageFileURL) { [weak self] in
            guard let self else { return }
            SyncManager.shared.readUsage(context: self.context)
        }
    }

    private func startEventsWatcher() {
        eventsWatcher?.cancel()
        eventsWatcher = makeWatcher(for: PaCoFiles.eventsFileURL) { [weak self] in
            self?.processNewEvents()
        }
    }

    // MARK: - Message handling

    /// Parent-side handling of child-initiated messages (cross-Mac requests).
    private func handleParentIncoming(_ message: PaCoMessage, from identity: String) {
        guard message.command == .requestExtension,
              let data = message.payload,
              let payload = try? JSONDecoder().decode(ExtensionRequestPayload.self, from: data) else { return }
        DispatchQueue.main.async { [self] in
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
                logger.warning("Ignoring approveExtension: unknown or replayed request id")
                return
            }
            let minutes = payload.grantedMinutes ?? 30
            OverrideStore.write(InternetOverride(
                requestId: payload.requestId,
                grantedUntil: Date().addingTimeInterval(TimeInterval(minutes * 60))
            ))
            logger.info("Extension approved: granted \(minutes) min (agent will enable)")

        case .denyExtension:
            if let data = message.payload,
               let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data) {
                _ = ChildRequestLog.shared.consume(payload.requestId)
            }
            logger.info("Extension denied by parent")

        case .provisionPIN:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(PINProvisionTransfer.self, from: data) else { return }
            try? PINManager.storeProvisionedPIN(hash: payload.hash, salt: payload.salt)
            logger.info("Parent PIN provisioned to this child")

        default:
            break
        }
    }

    private func processNewEvents() {
        guard let data = try? Data(contentsOf: PaCoFiles.eventsFileURL),
              let events = try? JSONDecoder().decode([NotificationEvent].self, from: data)
        else { return }

        for event in events where !seenEventIds.contains(event.id) {
            seenEventIds.insert(event.id)
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
