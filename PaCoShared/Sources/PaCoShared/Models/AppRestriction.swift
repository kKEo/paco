import Foundation
import SwiftData

public enum RestrictionType: String, Codable, Sendable {
    case blocked
    case scheduledOnly
}

@Model
public final class AppRestriction {
    @Attribute(.unique) public var id: UUID
    public var bundleIdentifier: String
    public var appName: String
    public var restrictionType: RestrictionType
    public var allowedScheduleId: UUID?

    public var childProfile: ChildProfile?

    public init(
        bundleIdentifier: String,
        appName: String,
        restrictionType: RestrictionType,
        allowedScheduleId: UUID? = nil
    ) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.restrictionType = restrictionType
        self.allowedScheduleId = allowedScheduleId
    }
}
