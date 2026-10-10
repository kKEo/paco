import Foundation

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

    /// pf evaluates every rule and the *last* match wins unless a rule says `quick`.
    /// The pass rules therefore must be `quick`, otherwise the trailing catch-all
    /// block rule overrides them and LAN/Bonjour traffic is dropped as well.
    public static func blockInternetRules() -> String {
        var lines = ["# PaCo internet block rules", "# Keep local traffic reachable (quick: stop evaluating on match)."]
        lines += passDestinations.map { "pass out quick to \($0)" }
        lines.append("")
        lines.append("# Block all other outbound traffic (incl. ICMP so ping/traceroute don't leak).")
        lines.append("block drop out proto { tcp udp icmp icmp6 } from any to any")
        return lines.joined(separator: "\n") + "\n"
    }

    public static let anchorName = "com.paco"
    public static let anchorFilePath = "/etc/pf.anchors/com.paco"
}
