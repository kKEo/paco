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
        guard !password.isEmpty else { throw KDFError.emptyInput }
        let passwordBytes = Array(password.utf8)
        var derivedKey = Data(count: keyLength)

        let result = derivedKey.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes, passwordBytes.count,
                    saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), keyLength
                )
            }
        }

        guard result == kCCSuccess else { throw KDFError.derivationFailed }
        return derivedKey
    }

    /// Cryptographically secure random bytes.
    public static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw KDFError.randomFailed }
        return bytes
    }

    /// Constant-time comparison to avoid timing side-channels on secret comparisons.
    public static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
