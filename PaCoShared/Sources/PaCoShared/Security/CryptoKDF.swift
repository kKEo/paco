import Foundation
import CommonCrypto

/// Shared PBKDF2-SHA256 key derivation used by both PIN hashing and pairing-key derivation.
public enum CryptoKDF {

    public enum KDFError: Error, Equatable {
        case emptyInput
        case derivationFailed
        case randomFailed
    }

    /// Derive a key of `keyLength` bytes from `password` and `salt` using PBKDF2-SHA256.
    public static func deriveKey(
        password: String,
        salt: Data,
        iterations: UInt32,
        keyLength: Int
    ) throws -> Data {
        // An empty salt or key would give an empty buffer whose base address is nil;
        // force-unwrapping it crashed the app when a peer sent such a payload.
        guard !password.isEmpty, !salt.isEmpty, keyLength > 0, iterations > 0 else { throw KDFError.emptyInput }
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt)
        var derivedKey = [UInt8](repeating: 0, count: keyLength)

        let result = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derivedKey, keyLength
        )

        guard result == kCCSuccess else { throw KDFError.derivationFailed }
        return Data(derivedKey)
    }

    /// Cryptographically secure random bytes.
    public static func randomBytes(count: Int) throws -> Data {
        guard count > 0 else { throw KDFError.emptyInput }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw KDFError.randomFailed }
        return Data(bytes)
    }

    /// Constant-time comparison to avoid timing side-channels on secret comparisons.
    public static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
