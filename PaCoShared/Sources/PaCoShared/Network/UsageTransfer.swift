import Foundation

public struct UsageTransfer: Codable, Sendable, Equatable {
    public var date: Date
    public var profileId: UUID?
    public var internetOnDuration: TimeInterval
    public var appUsage: [AppUsageEntry]

    public init(date: Date, profileId: UUID?, internetOnDuration: TimeInterval, appUsage: [AppUsageEntry]) {
        self.date = date
        self.profileId = profileId
        self.internetOnDuration = internetOnDuration
        self.appUsage = appUsage
    }
}
