import Foundation

public struct AppUsageEntry: Codable, Sendable, Equatable {
    public var bundleIdentifier: String
    public var appName: String
    public var duration: TimeInterval
    public var launchCount: Int

    public init(bundleIdentifier: String, appName: String, duration: TimeInterval, launchCount: Int) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.duration = duration
        self.launchCount = launchCount
    }
}
