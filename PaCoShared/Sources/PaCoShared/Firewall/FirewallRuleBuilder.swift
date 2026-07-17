import Foundation

public enum FirewallRuleBuilder {
    public static func blockInternetRules() -> String {
        """
        # PaCo internet block rules
        # Allow LAN traffic. NOTE: this permits reaching a proxy running on another
        # LAN host, which is an advanced bypass vector under an adversarial-child
        # model. Narrow these ranges if that matters for your deployment.
        pass out to 10.0.0.0/8
        pass out to 172.16.0.0/12
        pass out to 192.168.0.0/16
        pass out to 169.254.0.0/16
        pass out to 127.0.0.0/8
        pass out to ::1/128
        pass out to fe80::/10

        # Block all other outbound traffic (incl. ICMP so ping/traceroute don't leak).
        block drop out proto { tcp udp icmp icmp6 } from any to any
        """
    }

    public static func allowInternetRules() -> String { "" }
    public static let anchorName = "com.paco"
    public static let anchorFilePath = "/etc/pf.anchors/com.paco"
}
