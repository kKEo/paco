import Foundation

/// The PaCo Cloud server, kept reachable while internet is blocked so a child
/// can still ask for more time and the parent's commands still arrive. Only
/// this host and port pass; addresses are resolved while internet is on,
/// because DNS is blocked too.
public struct CloudRelay: Codable, Sendable, Equatable {
    public var addresses: [String]
    public var port: Int

    public init(addresses: [String], port: Int) {
        self.addresses = addresses
        self.port = port
    }

    /// Addresses that are literal IPv4/IPv6 addresses. Anything else is dropped,
    /// so nothing but an address can ever reach the generated `pf` rules.
    public var validAddresses: [String] {
        var seen = Set<String>()
        return addresses.filter { FirewallRuleBuilder.isIPAddress($0) && seen.insert($0).inserted }
    }
}

public enum FirewallRuleBuilder {
    /// Destinations that stay reachable while the internet is blocked: private LAN
    /// ranges, link-local, loopback, multicast (mDNS/Bonjour) and broadcast (DHCP).
    ///
    /// NOTE: allowing LAN permits reaching a proxy on another LAN host, which is an
    /// advanced bypass vector under an adversarial-child model. Narrow these ranges
    /// if that matters for your deployment.
    public static let passDestinations: [String] = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "127.0.0.0/8",
        "224.0.0.0/4",
        "255.255.255.255/32",
        "::1/128",
        "fe80::/10",
        "ff02::/16",
    ]

    /// Anchor-local table holding the cloud server's addresses; refreshed in place
    /// with `pfctl -a com.paco -t paco_cloud -T replace …` when they change.
    public static let relayTableName = "paco_cloud"

    /// pf evaluates every rule and the *last* match wins unless a rule says `quick`.
    /// The pass rules therefore must be `quick`, otherwise the trailing catch-all
    /// block rule overrides them and LAN/Bonjour traffic is dropped as well.
    ///
    /// With `relay` (a cloud-enrolled Mac) the server's addresses pass too, on its
    /// port only. The table is emitted even when no address is known yet, so a
    /// later table refresh has something to replace.
    public static func blockInternetRules(relay: CloudRelay? = nil) -> String {
        var lines = ["# PaCo internet block rules"]
        if let relay {
            let addresses = relay.validAddresses.joined(separator: " ")
            lines.append("# PaCo Cloud server, reachable while blocked (table refreshed by the daemon).")
            lines.append("table <\(relayTableName)> persist {\(addresses.isEmpty ? "" : " \(addresses) ")}")
        }
        lines.append("# Keep local traffic reachable (quick: stop evaluating on match).")
        lines += passDestinations.map { "pass out quick to \($0)" }
        if let relay {
            lines.append("pass out quick proto tcp to <\(relayTableName)> port \(relay.port)")
        }
        lines.append("")
        lines.append("# Block all other outbound traffic (incl. ICMP so ping/traceroute don't leak).")
        lines.append("block drop out proto { tcp udp icmp icmp6 } from any to any")
        return lines.joined(separator: "\n") + "\n"
    }

    /// True for a literal IPv4 or IPv6 address (no names, ranges or extra text).
    public static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return text.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    public static let anchorName = "com.paco"
    public static let anchorFilePath = "/etc/pf.anchors/com.paco"
}
