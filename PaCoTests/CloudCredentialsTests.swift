import XCTest
@testable import PaCoShared

final class CloudCredentialsTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("paco-cloud-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func credentials(_ server: String = "https://paco.example.com") -> CloudCredentials {
        CloudCredentials(
            serverURL: URL(string: server)!, deviceId: UUID(), deviceName: "Mac",
            deviceToken: "pcd_x.secret", eventCursor: 12, policyVersion: 3,
            relayAddresses: ["203.0.113.7"], relayResolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            enrolledAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testRoundTripsAndIsReadableOnlyByOwner() throws {
        let url = directory.appendingPathComponent("cloud.json")
        let original = credentials()
        try original.save(to: url)

        XCTAssertEqual(CloudCredentials.load(from: url), original)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o600)
    }

    func testOverwriteKeepsPermissionsAndLeavesNoTempFiles() throws {
        let url = directory.appendingPathComponent("cloud.json")
        var creds = credentials()
        try creds.save(to: url)
        creds.eventCursor = 99
        try creds.save(to: url)

        XCTAssertEqual(CloudCredentials.load(from: url)?.eventCursor, 99)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["cloud.json"])
    }

    func testMissingOrCorruptFileLoadsNil() throws {
        let url = directory.appendingPathComponent("cloud.json")
        XCTAssertNil(CloudCredentials.load(from: url))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(CloudCredentials.load(from: url))
    }

    func testServerPortAndRelay() {
        XCTAssertEqual(credentials().serverPort, 443)
        XCTAssertEqual(credentials("https://paco.example.com:8443").serverPort, 8443)
        XCTAssertEqual(credentials("http://localhost").serverPort, 80)
        XCTAssertEqual(credentials().relay, CloudRelay(addresses: ["203.0.113.7"], port: 443))
    }

    func testTokenRotatesAfterThirtyDays() {
        var creds = credentials()   // enrolled at 1_790_000_000, no rotation yet
        let enrolled = creds.enrolledAt
        XCTAssertFalse(creds.needsTokenRotation(at: enrolled.addingTimeInterval(29 * 86_400)))
        XCTAssertTrue(creds.needsTokenRotation(at: enrolled.addingTimeInterval(30 * 86_400)))

        creds.tokenIssuedAt = enrolled.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(creds.needsTokenRotation(at: enrolled.addingTimeInterval(31 * 86_400)))
    }

    func testCredentialsSavedBeforeRotationExistedStillLoad() throws {
        let url = directory.appendingPathComponent("cloud.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {"serverURL":"https://paco.example.com","deviceId":"01A1444E-FF94-70FD-82BD-5A8FF2932945","deviceName":"Mac",
         "deviceToken":"pcd_x.y","eventCursor":3,"policyVersion":2,"relayAddresses":[],"enrolledAt":"2026-10-16T10:00:00Z"}
        """
        try Data(legacy.utf8).write(to: url)
        XCTAssertNil(CloudCredentials.load(from: url)?.tokenIssuedAt)
        XCTAssertEqual(CloudCredentials.load(from: url)?.eventCursor, 3)
    }

    // MARK: - Server address validation

    func testAcceptsAndNormalizesHTTPSAddresses() {
        XCTAssertEqual(CloudServerURL.validate("paco.example.com")?.absoluteString, "https://paco.example.com")
        XCTAssertEqual(CloudServerURL.validate(" HTTPS://Paco.Example.com/ ")?.absoluteString, "https://paco.example.com")
        XCTAssertEqual(CloudServerURL.validate("https://example.com:8443/paco/")?.absoluteString, "https://example.com:8443/paco")
    }

    func testRejectsInsecureOrOddAddresses() {
        XCTAssertNil(CloudServerURL.validate(""))
        XCTAssertNil(CloudServerURL.validate("http://paco.example.com"))
        XCTAssertNil(CloudServerURL.validate("ftp://paco.example.com"))
        XCTAssertNil(CloudServerURL.validate("https://user:pw@paco.example.com"))
        XCTAssertNil(CloudServerURL.validate("https://paco.example.com/?x=1"))
        XCTAssertNil(CloudServerURL.validate("http://localhost:8080"), "plain http only when explicitly allowed")
    }

    func testAllowsPlainHTTPOnLoopbackForDevelopment() {
        XCTAssertEqual(
            CloudServerURL.validate("http://localhost:8080", allowInsecureLoopback: true)?.absoluteString,
            "http://localhost:8080")
        XCTAssertNil(CloudServerURL.validate("http://192.168.1.10:8080", allowInsecureLoopback: true))
    }

    func testEndpointPaths() {
        let base = CloudServerURL.validate("https://example.com/paco")!
        XCTAssertEqual(CloudServerURL.endpoint(base, "device/events").absoluteString, "https://example.com/paco/api/v1/device/events")
        XCTAssertEqual(CloudServerURL.endpoint(base, "enroll").absoluteString, "https://example.com/paco/api/v1/enroll")
    }
}
