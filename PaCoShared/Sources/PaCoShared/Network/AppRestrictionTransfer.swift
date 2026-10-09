import Foundation

/// Codable app restriction representation for network transfer and agent-side storage.
/// The agent cannot use SwiftData @Model classes, so this lightweight struct
/// is used for JSON serialization over Bonjour and local file caching.
public struct AppRestrictionTransfer: Codable, Sendable, Equatable {
    public var id: UUID
    public var bundleIdentifier: String
    public var appName: String
    public var restrictionType: RestrictionType
    public var allowedScheduleId: UUID?
    public var profileId: UUID?

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        restrictionType: RestrictionType,
        allowedScheduleId: UUID? = nil,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.restrictionType = restrictionType
        self.allowedScheduleId = allowedScheduleId
        self.profileId = profileId
    }

    public init(from r: AppRestriction) {
        self.id = r.id
        self.bundleIdentifier = r.bundleIdentifier
        self.appName = r.appName
        self.restrictionType = r.restrictionType
        self.allowedScheduleId = r.allowedScheduleId
        self.profileId = r.childProfile?.id
    }
}
