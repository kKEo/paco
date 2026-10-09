import XCTest
@testable import PaCoShared

final class PairingKeyTests: XCTestCase {

    func testDerivationIsDeterministicForSameCode() throws {
        let a = try PairingKeyManager.deriveKey(fromCode: "ABCD1234")
        let b = try PairingKeyManager.deriveKey(fromCode: "abcd1234")  // case-insensitive
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    func testDerivationDiffersForDifferentCodes() throws {
        let a = try PairingKeyManager.deriveKey(fromCode: "ABCD1234")
        let b = try PairingKeyManager.deriveKey(fromCode: "ABCD1235")
        XCTAssertNotEqual(a, b)
    }

    func testGeneratedCodeIsNonEmpty() {
        XCTAssertFalse(PairingKeyManager.generateCode().isEmpty)
    }

    func testEmptySaltIsRejectedInsteadOfCrashing() {
        XCTAssertThrowsError(try CryptoKDF.deriveKey(password: "x", salt: Data(), iterations: 1, keyLength: 32))
        XCTAssertThrowsError(try CryptoKDF.deriveKey(password: "", salt: Data([1]), iterations: 1, keyLength: 32))
        XCTAssertThrowsError(try CryptoKDF.deriveKey(password: "x", salt: Data([1]), iterations: 1, keyLength: 0))
        XCTAssertThrowsError(try PINManager.verify(pin: "1234", hash: Data([1, 2]), salt: Data()))
    }

    func testConstantTimeEquals() {
        let a = Data([1, 2, 3, 4])
        XCTAssertTrue(CryptoKDF.constantTimeEquals(a, Data([1, 2, 3, 4])))
        XCTAssertFalse(CryptoKDF.constantTimeEquals(a, Data([1, 2, 3, 5])))
        XCTAssertFalse(CryptoKDF.constantTimeEquals(a, Data([1, 2, 3])))
    }
}
