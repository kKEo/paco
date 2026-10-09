import Foundation

/// Per-user files exchanged between the app and the agent. Enforcement policy is
/// *not* here any more: it lives in the root daemon (see `DaemonPolicy`), so the
/// monitored user cannot edit it.
public enum PaCoFiles {
    public static let usageFileName         = "usage.json"
    public static let eventsFileName        = "events.json"
    public static let childRequestsFileName = "child-requests.json"

    public static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.paco")
    }

    public static var usageFileURL:         URL { baseDirectory.appendingPathComponent(usageFileName) }
    public static var eventsFileURL:        URL { baseDirectory.appendingPathComponent(eventsFileName) }
    public static var childRequestsFileURL: URL { baseDirectory.appendingPathComponent(childRequestsFileName) }
}
