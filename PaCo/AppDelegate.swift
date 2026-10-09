import AppKit
import Combine
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
    private var statusTimer: DispatchSourceTimer?
    private var seenEventIds: Set<UUID> = []
    private var configuredRole: DeviceRole?
    private let logger = PaCoLogger.app

    /// Matches the agent's schedule tick, so the menu bar icon and status views
    /// follow what the agent actually did rather than the last manual toggle.
    private static let statusRefreshInterval: TimeInterval = 30

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
        startStatusTimer()
        SyncManager.shared.onPolicyChanged = { [weak self] in
            self?.pushPolicyToConnectedChildren()
        }
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

    private func startStatusTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.statusRefreshInterval, repeating: Self.statusRefreshInterval)
        timer.setEventHandler { [weak self] in self?.daemonClient.refreshStatus() }
        timer.resume()
        statusTimer = timer
    }

    // MARK: - Role-dependent networking

    /// Idempotent per role. Re-run when `appState.role` changes (onboarding
    /// completes) so no relaunch is needed.
    private func configureRole() {
        guard let role = appState.role, role != configuredRole else { return }
        configuredRole = role
        switch role {
        case .child:
            // Policy files on a child are owned by the parent's pushes; only the
            // device-local config is written from this Mac's own state.
            SyncManager.shared.syncDeviceConfig(activeProfileId: appState.activeProfileId(context: context))
            bonjour.onIncomingMessage = { [weak self] message in
                self?.handleChildIncoming(message)
            }
            bonjour.startAdvertising(name: Self.deviceName)
        case .parent:
            // The parent's own agent enforces the same policy locally (single-Mac use).
            SyncManager.shared.syncAll(context: context)
            // Handle time-extension requests arriving from any paired child.
            bonjour.onChildRequest = { [weak self] message, identity in
                self?.handleParentIncoming(message, from: identity)
            }
            bonjour.onChildResponse = { [weak self] response, identity in
                if response.success {
                    self?.logger.info("Child '\(identity)' acknowledged command")
                } else {
                    self?.logger.warning("Child '\(identity)' rejected command: \(response.error ?? "unknown")")
                }
            }
            // On connect, push the current policy and provision the parent PIN so
            // the child's "Parent Access" can be verified locally.
            bonjour.onParentConnected = { [weak self] identity in
                self?.pushPolicy(to: identity)
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

    // MARK: - Parent → child pushes

    /// Send the full policy to one connected child.
    private func pushPolicy(to identity: String) {
        let policy = SyncManager.shared.currentPolicy(context: context)
        guard let data = try? JSONEncoder().encode(policy) else { return }
        if bonjour.send(PaCoMessage(command: .updatePolicy, payload: data), to: identity) {
            logger.info("Pushed policy to '\(identity)': \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
        }
    }

    /// Re-push after any local policy change so connected children stay in sync.
    /// Offline children receive the policy when they next connect.
    private func pushPolicyToConnectedChildren() {
        guard configuredRole == .parent else { return }
        for identity in bonjour.connectedIdentities {
            pushPolicy(to: identity)
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
    ///
    /// The request is attributed to the *connection identity* (the paired name the
    /// TLS session was opened under), never to the name the child wrote into the
    /// payload: the reply is routed by that identity, so using anything else can
    /// leave an approval undeliverable.
    private func handleParentIncoming(_ message: PaCoMessage, from identity: String) {
        guard message.command == .requestExtension,
              let data = message.payload,
              let payload = try? JSONDecoder().decode(ExtensionRequestPayload.self, from: data) else { return }
        if !payload.childDeviceName.isEmpty, payload.childDeviceName != identity {
            logger.info("Request from '\(identity)' self-reports as '\(payload.childDeviceName)'; using pairing identity")
        }
        let requestId = payload.requestId
        let existing = (try? context.fetch(FetchDescriptor<TimeExtensionRequest>()))?.first { $0.id == requestId }
        guard existing == nil else { return }
        let req = TimeExtensionRequest(
            id: requestId,
            profileId: payload.profileId,
            childDeviceName: identity,
            requestedMinutes: payload.requestedMinutes,
            reason: payload.reason
        )
        context.insert(req)
        try? context.save()
        logger.info("Extension request from '\(identity)': \(payload.requestedMinutes) min")
    }

    /// Child-side handling of parent-initiated messages over the authenticated channel.
    private func handleChildIncoming(_ message: PaCoMessage) {
        switch message.command {
        case .updatePolicy:
            guard let data = message.payload,
                  let policy = try? JSONDecoder().decode(PolicyTransfer.self, from: data) else {
                bonjour.replyToParent(PaCoResponse(success: false, error: "bad policy payload"))
                return
            }
            let ok = SyncManager.shared.applyRemotePolicy(policy)
            bonjour.replyToParent(PaCoResponse(success: ok, error: ok ? nil : "could not write policy"))
            if ok {
                logger.info("Applied policy from parent: \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
            }

        case .approveExtension:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data) else { return }
            let minutes = payload.grantedMinutes ?? 30
            let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
            guard ChildRequestLog.shared.resolve(id: payload.requestId, approved: true, grantedUntil: until) else {
                logger.warning("Ignoring approveExtension: unknown or already-resolved request id")
                return
            }
            OverrideStore.write(InternetOverride(requestId: payload.requestId, grantedUntil: until))
            logger.info("Extension approved: granted \(minutes) min (agent will enable)")

        case .denyExtension:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data),
                  ChildRequestLog.shared.resolve(id: payload.requestId, approved: false) else {
                logger.warning("Ignoring denyExtension: unknown or already-resolved request id")
                return
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
