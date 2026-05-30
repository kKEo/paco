import Foundation
import SwiftData

@Model
public final class UsageRecord {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var internetOnDuration: TimeInterval
    public var appUsageData: Data

    public var childProfile: ChildProfile?

    public var appUsage: [AppUsageEntry] {
        get {
            (try? JSONDecoder().decode([AppUsageEntry].self, from: appUsageData)) ?? []
        }
        set {
            appUsageData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public init(date: Date, internetOnDuration: TimeInterval = 0, appUsage: [AppUsageEntry] = []) {
        self.id = UUID()
        self.date = date
        self.internetOnDuration = internetOnDuration
        self.appUsageData = (try? JSONEncoder().encode(appUsage)) ?? Data()
    }
}
