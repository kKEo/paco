import XCTest
@testable import PaCoShared

final class FirewallRuleTests: XCTestCase {
    func testBlockRuleContent() {
        let rules = FirewallRuleBuilder.blockInternetRules()
        XCTAssertTrue(rules.contains("block drop out"))
        XCTAssertTrue(rules.contains("proto { tcp udp }"))
    }
    func testBlockRulePreservesLAN() {
        let rules = FirewallRuleBuilder.blockInternetRules()
        XCTAssertTrue(rules.contains("pass out to 10.0.0.0/8"))
        XCTAssertTrue(rules.contains("pass out to 172.16.0.0/12"))
        XCTAssertTrue(rules.contains("pass out to 192.168.0.0/16"))
    }
    func testEmptyRulesForAllow() {
        let rules = FirewallRuleBuilder.allowInternetRules()
        XCTAssertTrue(rules.isEmpty)
    }
}
