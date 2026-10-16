import Foundation

/// What the daemon does in response to cloud events (pure, unit-tested).
public enum CloudAction: Sendable, Equatable {
    /// Fetch the policy envelope (at most once per batch).
    case fetchPolicy
    case setActiveProfile(UUID?)
    case grantOverride(requestId: UUID, until: Date)
    case resolveRequest(requestId: UUID, approved: Bool, grantedUntil: Date?)
    case setManual(enabled: Bool, until: Date)
    case clearManual
    /// The parent unenrolled this Mac: forget the credentials, keep enforcing.
    case unenroll
}

/// Cursor and policy version the reducer checks events against.
public struct CloudSyncState: Sendable, Equatable {
    public var eventCursor: Int
    public var policyVersion: Int

    public init(eventCursor: Int, policyVersion: Int) {
        self.eventCursor = eventCursor
        self.policyVersion = policyVersion
    }
}

/// Turns a batch of events into actions. Events arrive at least once, so:
/// - an id at or below the cursor was already applied and is skipped;
/// - `policyChanged` for a version the device already holds is skipped;
/// - time windows are absolute, so a late or replayed grant never extends one,
///   and one that already ended is not applied (the request is still resolved).
public enum CloudEventReducer {
    public static func reduce(_ events: [CloudEvent], state: inout CloudSyncState, now: Date = Date()) -> [CloudAction] {
        var actions: [CloudAction] = []
        var needsPolicy = false

        for event in events.sorted(by: { $0.id < $1.id }) {
            // The server ends an open poll with a synthetic `unenrolled` whose id
            // equals the cursor, so it is honoured regardless of id.
            if event.kind == .unenrolled {
                actions.append(.unenroll)
                state.eventCursor = max(state.eventCursor, event.id)
                return actions + (needsPolicy ? [.fetchPolicy] : [])
            }
            guard event.id > state.eventCursor else { continue }
            state.eventCursor = event.id

            switch event.kind {
            case .policyChanged(let version):
                if version > state.policyVersion { needsPolicy = true }
            case .activeProfileChanged(let profileId):
                actions.append(.setActiveProfile(profileId))
                needsPolicy = true
            case .approveExtension(let requestId, _, let until):
                actions.append(.resolveRequest(requestId: requestId, approved: true, grantedUntil: until))
                if until > now { actions.append(.grantOverride(requestId: requestId, until: until)) }
            case .denyExtension(let requestId):
                actions.append(.resolveRequest(requestId: requestId, approved: false, grantedUntil: nil))
            case .setManualInternet(let enabled, _, let until):
                if until > now { actions.append(.setManual(enabled: enabled, until: until)) }
            case .clearManualInternet:
                actions.append(.clearManual)
            case .unenrolled, .unknown:
                break
            }
        }

        if needsPolicy { actions.append(.fetchPolicy) }
        return actions
    }
}
