import SwiftUI
import SwiftData
import PaCoShared

enum AppMode: Equatable {
    case onboarding
    case parent
    case child
}

enum UnlockResult: Equatable {
    case success
    case incorrect
    case noPIN
    case lockedOut(until: Date)
    /// Child device only: the parent Mac is not connected, so the PIN cannot be checked.
    case parentUnavailable
    case error
}

@Observable
final class AppState {
    /// What the UI shows. On a child device this flips to `.parent` only while a
    /// parent has unlocked with the PIN, and back to `.child` on lock.
    var mode: AppMode = .onboarding
    /// The persisted device role; nil until onboarding completes. Network roles
    /// (advertise vs browse) key off this, not off `mode`.
    private(set) var role: DeviceRole?
    /// The parent dashboard is shown only while unlocked. Cleared by `lock()`
    /// whenever the dashboard goes away so the PIN is required on every open.
    var isUnlocked = false

    /// Child device: verifies a PIN against the connected parent (set by AppDelegate).
    /// The parent PIN hash is never stored on a child, so this is the only way to
    /// check it there.
    @ObservationIgnored var remotePINVerifier: ((String, @escaping (UnlockResult) -> Void) -> Void)?
    /// Called after the active profile changes so the daemon can be told.
    @ObservationIgnored var onActiveProfileChanged: ((UUID?) -> Void)?

    private let logger = PaCoLogger.app

    func determineMode(context: ModelContext) {
        let descriptor = FetchDescriptor<DeviceConfig>()
        guard let config = try? context.fetch(descriptor).first else {
            mode = .onboarding
            role = nil
            return
        }
        role = config.role
        mode = config.role == .parent ? .parent : .child
        let currentMode = mode
        logger.info("App mode: \(String(describing: currentMode))")
    }

    func completeSetup(role: DeviceRole, context: ModelContext) {
        let config = DeviceConfig(role: role)
        context.insert(config)
        try? context.save()
        self.role = role
        mode = role == .parent ? .parent : .child
        // The parent just created the PIN; don't ask for it again immediately.
        isUnlocked = role == .parent
        logger.info("Setup complete as \(role.rawValue)")
    }

    // MARK: - PIN gate

    /// Verify the parent PIN with brute-force lockout; on success unlock the
    /// dashboard (unless `unlockOnSuccess` is false, as when answering a child
    /// Mac's remote check — the same lockout counter protects both paths).
    func attemptUnlock(pin: String, unlockOnSuccess: Bool = true) -> UnlockResult {
        guard (try? PINManager.hasPIN()) == true else { return .noPIN }
        if let until = PINManager.lockedOutUntil() { return .lockedOut(until: until) }
        do {
            if try PINManager.verifyStoredPIN(pin) {
                try? PINManager.resetAttempts()
                if unlockOnSuccess { unlock() }
                return .success
            }
            if let until = PINManager.recordFailedAttempt() { return .lockedOut(until: until) }
            return .incorrect
        } catch {
            return .error
        }
    }

    /// Child device: ask the connected parent to verify the PIN. Completion runs on main.
    func attemptRemoteUnlock(pin: String, completion: @escaping (UnlockResult) -> Void) {
        guard !pin.isEmpty else { completion(.incorrect); return }
        guard let verifier = remotePINVerifier else { completion(.parentUnavailable); return }
        verifier(pin) { [weak self] result in
            if result == .success { self?.unlock() }
            completion(result)
        }
    }

    /// Show the parent dashboard without a PIN check (after PIN creation).
    func unlock() {
        isUnlocked = true
        mode = .parent
    }

    /// Hide the parent dashboard; a child device returns to the child view.
    func lock() {
        guard isUnlocked || (role == .child && mode == .parent) else { return }
        isUnlocked = false
        if role == .child { mode = .child }
        logger.info("Parent dashboard locked")
    }

    // MARK: - Active profile

    func setActiveProfile(id: UUID?, context: ModelContext) {
        let descriptor = FetchDescriptor<DeviceConfig>()
        guard let config = try? context.fetch(descriptor).first else { return }
        config.childProfileId = id
        try? context.save()
        onActiveProfileChanged?(id)
    }

    func activeProfileId(context: ModelContext) -> UUID? {
        let descriptor = FetchDescriptor<DeviceConfig>()
        return (try? context.fetch(descriptor).first)?.childProfileId
    }
}
