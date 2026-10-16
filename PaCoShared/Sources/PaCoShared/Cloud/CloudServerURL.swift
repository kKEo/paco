import Foundation

/// Validation of the PaCo Cloud server address typed during enrollment.
public enum CloudServerURL {
    /// Shown in the address field. There is no default server: the parent runs
    /// (or is given) a PaCo Cloud instance and types its address.
    public static let placeholder = "https://paco.example.com"

    /// A normalized base URL (`scheme://host[:port][/path]`, no trailing slash),
    /// or nil when the address is unusable.
    ///
    /// Only `https` is accepted. Plain `http` is allowed for a loopback host when
    /// `allowInsecureLoopback` is set, which the daemon does in Debug builds only
    /// (local development against `php artisan serve`).
    public static func validate(_ input: String, allowInsecureLoopback: Bool = false) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            return nil
        }

        switch scheme {
        case "https":
            break
        case "http" where allowInsecureLoopback && isLoopback(host):
            break
        default:
            return nil
        }

        components.scheme = scheme
        components.host = host
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }

    /// `base` + `api/v1/<path>`.
    public static func endpoint(_ base: URL, _ path: String) -> URL {
        base.appendingPathComponent("api/v1").appendingPathComponent(path)
    }

    public static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }
}
