import Foundation

/// Sent from parent to child over the authenticated (TLS-PSK) channel right
/// after pairing, so the child can verify the parent PIN locally without ever
/// receiving the plaintext PIN. Carries only the PBKDF2 hash and salt.
public struct PINProvisionTransfer: Codable, Sendable {
    public var hash: Data
    public var salt: Data

    public init(hash: Data, salt: Data) {
        self.hash = hash
        self.salt = salt
    }
}
