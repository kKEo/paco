import Foundation
import CommonCrypto

public enum PINManager {

    public enum PINError: Error, Equatable {
        case emptyPIN
        case hashingFailed
    }

    private static let iterations: UInt32 = 10_000
    private static let keyLength = 32
    private static let saltLength = 16

    public static func hash(pin: String) throws -> (hash: Data, salt: Data) {
        guard !pin.isEmpty else { throw PINError.emptyPIN }

        var salt = Data(count: saltLength)
        let saltResult = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard saltResult == errSecSuccess else { throw PINError.hashingFailed }

        let hash = try deriveKey(pin: pin, salt: salt)
        return (hash, salt)
    }

    public static func verify(pin: String, hash: Data, salt: Data) throws -> Bool {
        guard !pin.isEmpty else { throw PINError.emptyPIN }
        let derived = try deriveKey(pin: pin, salt: salt)
        return derived == hash
    }

    private static func deriveKey(pin: String, salt: Data) throws -> Data {
        let pinData = Array(pin.utf8)
        var derivedKey = Data(count: keyLength)

        let result = derivedKey.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinData, pinData.count,
                    saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), keyLength
                )
            }
        }

        guard result == kCCSuccess else { throw PINError.hashingFailed }
        return derivedKey
    }

    // MARK: - Keychain integration

    private static let pinHashKey = "com.paco.pin.hash"
    private static let pinSaltKey = "com.paco.pin.salt"

    public static func storePIN(_ pin: String) throws {
        let (hash, salt) = try hash(pin: pin)
        try KeychainManager.save(key: pinHashKey, data: hash)
        try KeychainManager.save(key: pinSaltKey, data: salt)
    }

    public static func verifyStoredPIN(_ pin: String) throws -> Bool {
        guard let hash = try KeychainManager.load(key: pinHashKey),
              let salt = try KeychainManager.load(key: pinSaltKey) else {
            return false
        }
        return try verify(pin: pin, hash: hash, salt: salt)
    }

    public static func hasPIN() throws -> Bool {
        return try KeychainManager.load(key: pinHashKey) != nil
    }

    public static func deletePIN() throws {
        try KeychainManager.delete(key: pinHashKey)
        try KeychainManager.delete(key: pinSaltKey)
    }
}
