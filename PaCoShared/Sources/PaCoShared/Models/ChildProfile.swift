import Foundation
import SwiftData

@Model
public final class ChildProfile {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var avatarImageData: Data?
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Schedule.childProfile)
    public var schedules: [Schedule] = []

    @Relationship(deleteRule: .cascade, inverse: \AppRestriction.childProfile)
    public var appRestrictions: [AppRestriction] = []

    @Relationship(deleteRule: .cascade, inverse: \UsageRecord.childProfile)
    public var usageRecords: [UsageRecord] = []

    public init(name: String, avatarImageData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.avatarImageData = avatarImageData
        self.createdAt = Date()
    }
}
