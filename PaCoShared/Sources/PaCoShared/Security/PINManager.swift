import Foundation

public enum PINManager {

    public enum PINError: Error, Equatable {
        case emptyPIN
        case hashingFailed
    }

    private static let iterations: UInt32 = 210_000
    private static let keyLength = 32
    private static let saltLength = 16

    public static func hash(pin: String) throws -> (hash: Data, salt: Data) {
        guard !pin.isEmpty else { throw PINError.emptyPIN }
        do {
            let salt = try CryptoKDF.randomBytes(count: saltLength)
            let hash = try deriveKey(pin: pin, salt: salt)
            return (hash, salt)
        } catch {
            throw PINError.hashingFailed
        }
    }

    public static func verify(pin: String, hash: Data, salt: Data) throws -> Bool {
        guard !pin.isEmpty else { throw PINError.emptyPIN }
        let derived = try deriveKey(pin: pin, salt: salt)
        return CryptoKDF.constantTimeEquals(derived, hash)
    }

    private static func deriveKey(pin: String, salt: Data) throws -> Data {
        do {
            return try CryptoKDF.deriveKey(password: pin, salt: salt, iterations: iterations, keyLength: keyLength)
        } catch {
            throw PINError.hashingFailed
        }
    }

    // MARK: - Keychain integration

    private static let pinHashKey = "com.paco.pin.hash"
    private static let pinSaltKey = "com.paco.pin.salt"

    public static func storePIN(_ pin: String) throws {
        let (hash, salt) = try hash(pin: pin)
        try KeychainManager.save(key: pinHashKey, data: hash)
        try KeychainManager.save(key: pinSaltKey, data: salt)
        try? resetAttempts()
    }

    /// Store a parent PIN provisioned from another device (hash + salt only, no plaintext).
    /// Used by the child after pairing so "Parent Access" can be verified locally.
    public static func storeProvisionedPIN(hash: Data, salt: Data) throws {
        try KeychainManager.save(key: pinHashKey, data: hash)
        try KeychainManager.save(key: pinSaltKey, data: salt)
        try? resetAttempts()
    }

    /// Read the stored hash+salt (for provisioning to a paired child).
    public static func exportPIN() throws -> (hash: Data, salt: Data)? {
        guard let hash = try KeychainManager.load(key: pinHashKey),
              let salt = try KeychainManager.load(key: pinSaltKey) else {
            return nil
        }
        return (hash, salt)
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
        try? resetAttempts()
    }

    // MARK: - Brute-force lockout

    private static let attemptsKey = "com.paco.pin.attempts"
    private static let lockoutUntilKey = "com.paco.pin.lockoutUntil"
    private static let maxAttempts = 5
    private static let lockoutSeconds: TimeInterval = 300  // 5 minutes

    /// If currently locked out, returns the date the lockout ends; otherwise nil.
    public static func lockedOutUntil() -> Date? {
        guard let data = try? KeychainManager.load(key: lockoutUntilKey),
              let raw = String(data: data, encoding: .utf8),
              let epoch = TimeInterval(raw) else { return nil }
        let until = Date(timeIntervalSince1970: epoch)
        return until > Date() ? until : nil
    }

    /// Record a failed attempt; once `maxAttempts` is reached, engages a timed lockout.
    /// Returns the lockout end date if a lockout is now in effect.
    @discardableResult
    public static func recordFailedAttempt() -> Date? {
        let current = (try? KeychainManager.load(key: attemptsKey))
            .flatMap { $0 }
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { Int($0) } ?? 0
        let next = current + 1
        try? KeychainManager.save(key: attemptsKey, data: Data(String(next).utf8))
        if next >= maxAttempts {
            let until = Date().addingTimeInterval(lockoutSeconds)
            try? KeychainManager.save(
                key: lockoutUntilKey,
                data: Data(String(until.timeIntervalSince1970).utf8)
            )
            try? KeychainManager.save(key: attemptsKey, data: Data("0".utf8))
            return until
        }
        return nil
    }

    public static func resetAttempts() throws {
        try KeychainManager.delete(key: attemptsKey)
        try KeychainManager.delete(key: lockoutUntilKey)
    }
}
