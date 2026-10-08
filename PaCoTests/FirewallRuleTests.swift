import XCTest
@testable import PaCoShared

final class FirewallRuleTests: XCTestCase {
    private var ruleLines: [String] {
        FirewallRuleBuilder.blockInternetRules()
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func testBlockRuleContent() {
        let rules = FirewallRuleBuilder.blockInternetRules()
        XCTAssertTrue(rules.contains("block drop out"))
        XCTAssertTrue(rules.contains("proto { tcp udp icmp icmp6 }"))
    }

    func testBlockRulePreservesLAN() {
        let rules = FirewallRuleBuilder.blockInternetRules()
        XCTAssertTrue(rules.contains("pass out quick to 10.0.0.0/8"))
        XCTAssertTrue(rules.contains("pass out quick to 172.16.0.0/12"))
        XCTAssertTrue(rules.contains("pass out quick to 192.168.0.0/16"))
    }

    func testBlockRulePreservesMulticastAndBroadcast() {
        let rules = FirewallRuleBuilder.blockInternetRules()
        XCTAssertTrue(rules.contains("pass out quick to 224.0.0.0/4"), "mDNS/Bonjour IPv4")
        XCTAssertTrue(rules.contains("pass out quick to ff02::/16"), "mDNS/Bonjour IPv6")
        XCTAssertTrue(rules.contains("pass out quick to 255.255.255.255/32"), "DHCP broadcast")
    }

    /// pf: last matching rule wins unless `quick`. Every pass rule must be quick and
    /// precede the block rule, otherwise the catch-all block overrides them.
    func testPassRulesAreQuickAndPrecedeBlock() {
        let lines = ruleLines
        let passLines = lines.filter { $0.hasPrefix("pass") }
        let blockIndex = lines.firstIndex { $0.hasPrefix("block") }
        XCTAssertFalse(passLines.isEmpty)
        XCTAssertNotNil(blockIndex)
        for line in passLines {
            XCTAssertTrue(line.hasPrefix("pass out quick "), "not quick: \(line)")
        }
        XCTAssertEqual(blockIndex, lines.count - 1, "block rule must be last")
        XCTAssertEqual(passLines.count, FirewallRuleBuilder.passDestinations.count)
    }

    func testEmptyRulesForAllow() {
        let rules = FirewallRuleBuilder.allowInternetRules()
        XCTAssertTrue(rules.isEmpty)
    }
}
