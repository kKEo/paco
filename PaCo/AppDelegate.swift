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
    private var statusTimer: DispatchSourceTimer?
    private var configuredRole: DeviceRole?
    /// Child side: outstanding PIN checks sent to the parent, keyed by nonce.
    private var pendingPINChecks: [UUID: (UnlockResult) -> Void] = [:]
    private let logger = PaCoLogger.app

    /// Matches the daemon's policy tick, so the menu bar icon and status views
    /// follow what the daemon actually did rather than the last manual toggle.
    private static let statusRefreshInterval: TimeInterval = 30
    private static let pinCheckTimeout: TimeInterval = 10

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
        // Explicit store location: the SwiftData default is
        // ~/Library/Application Support/default.store, shared with any other
        // non-sandboxed SwiftData app on the machine.
        let config = ModelConfiguration(url: PaCoFiles.baseDirectory.appendingPathComponent("PaCo.store"))
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
        SyncManager.shared.onPolicyChanged = { [weak self] policy in
            self?.publishPolicy(policy)
        }
        appState.onActiveProfileChanged = { [weak self] id in
            self?.daemonClient.setActiveProfile(id)
        }
        appState.remotePINVerifier = { [weak self] pin, completion in
            self?.verifyPINWithParent(pin, completion: completion)
        }
        // The daemon keeps policy across restarts; the active profile is the one
        // device-local piece, so re-assert it from SwiftData at every launch.
        daemonClient.setActiveProfile(appState.activeProfileId(context: context))
        startUsageWatcher()
        SyncManager.shared.readUsage(context: context)
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
            // Policy on a child comes only from the parent's pushes (into the
            // local daemon); nothing is derived from this Mac's own SwiftData.
            bonjour.onIncomingMessage = { [weak self] message in
                self?.handleChildIncoming(message)
            }
            bonjour.onIncomingResponse = { [weak self] response in
                self?.handleChildResponse(response)
            }
            bonjour.startAdvertising(name: Self.deviceName)
        case .parent:
            // The parent's own daemon enforces the same policy locally (single-Mac use).
            SyncManager.shared.syncAll(context: context)
            // Handle requests arriving from any paired child.
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
            // On connect, push the current policy so the child enforces it.
            bonjour.onParentConnected = { [weak self] identity in
                self?.pushPolicy(to: identity)
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

    // MARK: - Policy distribution

    /// Parent: a policy change goes to the local daemon and to every connected child.
    /// Offline children receive it when they next connect.
    private func publishPolicy(_ policy: PolicyTransfer) {
        guard configuredRole == .parent else { return }
        daemonClient.pushPolicy(policy)
        guard let data = try? JSONEncoder().encode(policy) else { return }
        for identity in bonjour.connectedIdentities {
            if bonjour.send(PaCoMessage(command: .updatePolicy, payload: data), to: identity) {
                logger.info("Pushed policy to '\(identity)': \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
            }
        }
    }

    /// Send the full policy to one connected child.
    private func pushPolicy(to identity: String) {
        let policy = SyncManager.shared.currentPolicy(context: context)
        guard let data = try? JSONEncoder().encode(policy) else { return }
        if bonjour.send(PaCoMessage(command: .updatePolicy, payload: data), to: identity) {
            logger.info("Pushed policy to '\(identity)': \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
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

    // MARK: - Parent: messages from children

    /// The request is attributed to the *connection identity* (the paired name the
    /// TLS session was opened under), never to the name the child wrote into the
    /// payload: the reply is routed by that identity, so using anything else can
    /// leave an approval undeliverable.
    private func handleParentIncoming(_ message: PaCoMessage, from identity: String) {
        switch message.command {
        case .requestExtension:
            guard let data = message.payload,
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

        case .verifyPIN:
            guard let data = message.payload,
                  let request = try? JSONDecoder().decode(PINVerifyRequest.self, from: data) else { return }
            let result = PINVerifyResult(nonce: request.nonce, outcome: .incorrect)
            var reply = result
            switch appState.attemptUnlock(pin: request.pin, unlockOnSuccess: false) {
            case .success: reply.outcome = .success
            case .incorrect, .error: reply.outcome = .incorrect
            case .noPIN: reply.outcome = .noPIN
            case .lockedOut(let until):
                reply.outcome = .lockedOut
                reply.lockedOutUntil = until
            case .parentUnavailable: reply.outcome = .incorrect
            }
            logger.info("PIN check from '\(identity)': \(reply.outcome.rawValue)")
            if let payload = try? JSONEncoder().encode(reply) {
                bonjour.reply(PaCoResponse(success: reply.outcome == .success, payload: payload), to: identity)
            }

        default:
            break
        }
    }

    // MARK: - Child: messages from the parent

    private func handleChildIncoming(_ message: PaCoMessage) {
        switch message.command {
        case .updatePolicy:
            guard let data = message.payload,
                  let policy = try? JSONDecoder().decode(PolicyTransfer.self, from: data) else {
                bonjour.replyToParent(PaCoResponse(success: false, error: "bad policy payload"))
                return
            }
            // Into the root daemon, which persists and enforces it.
            daemonClient.pushPolicy(policy) { [weak self] ok in
                self?.bonjour.replyToParent(PaCoResponse(success: ok, error: ok ? nil : "daemon rejected policy"))
                if ok {
                    self?.logger.info("Applied policy from parent: \(policy.schedules.count) schedules, \(policy.restrictions.count) restrictions")
                }
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
            daemonClient.grantOverride(requestId: payload.requestId, until: until) { [weak self] ok in
                if ok {
                    self?.logger.info("Extension approved: granted \(minutes) min (daemon will enable)")
                } else {
                    self?.logger.error("Extension approved but the daemon refused the override")
                }
            }

        case .denyExtension:
            guard let data = message.payload,
                  let payload = try? JSONDecoder().decode(ExtensionResponsePayload.self, from: data),
                  ChildRequestLog.shared.resolve(id: payload.requestId, approved: false) else {
                logger.warning("Ignoring denyExtension: unknown or already-resolved request id")
                return
            }
            logger.info("Extension denied by parent")

        default:
            break
        }
    }

    private func handleChildResponse(_ response: PaCoResponse) {
        guard let data = response.payload,
              let result = try? JSONDecoder().decode(PINVerifyResult.self, from: data),
              let completion = pendingPINChecks.removeValue(forKey: result.nonce) else { return }
        switch result.outcome {
        case .success: completion(.success)
        case .incorrect: completion(.incorrect)
        case .noPIN: completion(.noPIN)
        case .lockedOut: completion(.lockedOut(until: result.lockedOutUntil ?? Date().addingTimeInterval(300)))
        }
    }

    /// Child: send the typed PIN to the parent over the TLS-PSK channel and wait
    /// (bounded) for its verdict. The parent applies its own lockout.
    private func verifyPINWithParent(_ pin: String, completion: @escaping (UnlockResult) -> Void) {
        let nonce = UUID()
        guard let data = try? JSONEncoder().encode(PINVerifyRequest(nonce: nonce, pin: pin)),
              bonjour.sendToParent(PaCoMessage(command: .verifyPIN, payload: data)) else {
            completion(.parentUnavailable)
            return
        }
        pendingPINChecks[nonce] = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pinCheckTimeout) { [weak self] in
            if let pending = self?.pendingPINChecks.removeValue(forKey: nonce) {
                pending(.parentUnavailable)
            }
        }
    }
}
