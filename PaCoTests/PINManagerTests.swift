import XCTest
@testable import PaCoShared

final class PINManagerTests: XCTestCase {

    func testHashAndVerify() throws {
        let pin = "123456"
        let (hash, salt) = try PINManager.hash(pin: pin)
        XCTAssertTrue(try PINManager.verify(pin: pin, hash: hash, salt: salt))
    }

    func testWrongPINFails() throws {
        let (hash, salt) = try PINManager.hash(pin: "123456")
        XCTAssertFalse(try PINManager.verify(pin: "654321", hash: hash, salt: salt))
    }

    func testDifferentSaltsProduceDifferentHashes() throws {
        let (hash1, _) = try PINManager.hash(pin: "123456")
        let (hash2, _) = try PINManager.hash(pin: "123456")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testEmptyPINThrows() {
        XCTAssertThrowsError(try PINManager.hash(pin: "")) { error in
            XCTAssertEqual(error as? PINManager.PINError, .emptyPIN)
        }
    }
}
