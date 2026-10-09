import Foundation

/// One time-extension request sent by a child device and its outcome.
public struct ChildRequestRecord: Codable, Sendable, Equatable, Identifiable {
    public enum State: String, Codable, Sendable {
        case sent
        case approved
        case denied
    }

    public var id: UUID
    public var requestedMinutes: Int
    public var reason: String
    public var sentAt: Date
    public var state: State
    public var resolvedAt: Date?
    /// Present on approval: the end of the granted internet window.
    public var grantedUntil: Date?

    public init(id: UUID, requestedMinutes: Int, reason: String, sentAt: Date = Date()) {
        self.id = id
        self.requestedMinutes = requestedMinutes
        self.reason = reason
        self.sentAt = sentAt
        self.state = .sent
    }

    public var isPending: Bool { state == .sent }
}

/// Child-side record of sent extension requests, persisted to disk so that an
/// approval arriving after the app relaunched is still accepted (and so the
/// child can see what happened to each request). A request id can be resolved
/// only once, which is the replay guard on top of the authenticated channel.
public struct ChildRequestStore: Codable, Equatable, Sendable {

    public static let defaultKeepCount = 20

    public private(set) var records: [ChildRequestRecord]

    public init(records: [ChildRequestRecord] = []) {
        self.records = records
    }

    // MARK: - Persistence

    public static func load(from url: URL) -> ChildRequestStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(ChildRequestStore.self, from: data) else {
            return ChildRequestStore()
        }
        return store
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Mutation

    /// Record a request that was handed to the network layer.
    public mutating func record(id: UUID, requestedMinutes: Int, reason: String, at date: Date = Date()) {
        records.append(ChildRequestRecord(id: id, requestedMinutes: requestedMinutes, reason: reason, sentAt: date))
        prune()
    }

    /// Resolve an outstanding request. Returns `false` if the id is unknown or
    /// was already resolved, in which case nothing changes (replay / stray reply).
    @discardableResult
    public mutating func resolve(id: UUID, approved: Bool, grantedUntil: Date? = nil, at date: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].isPending else {
            return false
        }
        records[index].state = approved ? .approved : .denied
        records[index].resolvedAt = date
        records[index].grantedUntil = approved ? grantedUntil : nil
        return true
    }

    /// Drop all unanswered requests (the child gave up waiting). A late reply for
    /// a withdrawn id is then rejected like any unknown id.
    public mutating func withdrawPending() {
        records.removeAll(where: \.isPending)
    }

    /// Forget requests older than `maxAge` that are still unanswered.
    public mutating func expirePending(olderThan maxAge: TimeInterval, now: Date = Date()) {
        records.removeAll { $0.isPending && now.timeIntervalSince($0.sentAt) > maxAge }
    }

    private mutating func prune(keep: Int = ChildRequestStore.defaultKeepCount) {
        if records.count > keep { records = Array(records.suffix(keep)) }
    }

    // MARK: - Queries

    /// The most recent unanswered request, if any.
    public var pending: ChildRequestRecord? { records.last(where: \.isPending) }

    /// The most recent request of any state.
    public var latest: ChildRequestRecord? { records.last }
}
