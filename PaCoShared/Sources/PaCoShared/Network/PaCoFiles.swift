import Foundation

public enum PaCoFiles {
    public static let schedulesFileName   = "schedules.json"
    public static let restrictionsFileName = "restrictions.json"
    public static let configFileName      = "config.json"
    public static let usageFileName       = "usage.json"
    public static let eventsFileName      = "events.json"
    public static let overrideFileName    = "override.json"

    public static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.paco")
    }

    public static var schedulesFileURL:    URL { baseDirectory.appendingPathComponent(schedulesFileName) }
    public static var restrictionsFileURL: URL { baseDirectory.appendingPathComponent(restrictionsFileName) }
    public static var configFileURL:       URL { baseDirectory.appendingPathComponent(configFileName) }
    public static var usageFileURL:        URL { baseDirectory.appendingPathComponent(usageFileName) }
    public static var eventsFileURL:       URL { baseDirectory.appendingPathComponent(eventsFileName) }
    public static var overrideFileURL:     URL { baseDirectory.appendingPathComponent(overrideFileName) }
}
