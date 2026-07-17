import Foundation

/// Manages the symmetric pre-shared keys that authenticate & encrypt the
/// parent↔child Bonjour channel (TLS-PSK).
///
/// The key is derived from a one-time pairing code shown by the parent and
/// entered on the child, so both sides arrive at the same 32-byte key without
/// ever transmitting a secret. Keys are stored in the keychain, indexed by peer
/// identity (device name), so a parent can hold one key per paired child.
public enum PairingKeyManager {

    private static let iterations: UInt32 = 210_000
    private static let keyLength = 32
    /// Fixed application salt — the pairing code itself is the secret.
    private static let pairingSalt = Data("com.paco.pairing.v1".utf8)
    private static let storeKey = "com.paco.pairing.keys"

    /// A stored pairing key for one peer.
    private struct Entry: Codable {
        var identity: String
        var key: Data
    }

    // MARK: - Code generation & derivation

    /// Generate a human-enterable one-time pairing code (Crockford base32, 8 chars ≈ 40 bits).
    public static func generateCode() -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let random = (try? CryptoKDF.randomBytes(count: 8)) ?? Data(count: 8)
        var code = ""
        for byte in random { code.append(alphabet[Int(byte) % alphabet.count]) }
        return code
    }

    /// Derive the 32-byte PSK from a pairing code. Deterministic on both sides.
    public static func deriveKey(fromCode code: String) throws -> Data {
        let normalized = code.uppercased().replacingOccurrences(of: " ", with: "")
        return try CryptoKDF.deriveKey(
            password: normalized, salt: pairingSalt, iterations: iterations, keyLength: keyLength
        )
    }

    // MARK: - Storage

    private static func loadEntries() -> [Entry] {
        guard let data = try? KeychainManager.load(key: storeKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func saveEntries(_ entries: [Entry]) throws {
        let data = try JSONEncoder().encode(entries)
        try KeychainManager.save(key: storeKey, data: data)
    }

    /// Store (or replace) the pairing key for `identity`.
    public static func storeKey(_ key: Data, identity: String) throws {
        var entries = loadEntries().filter { $0.identity != identity }
        entries.append(Entry(identity: identity, key: key))
        try saveEntries(entries)
    }

    /// Pair from a code, storing the derived key under `identity`.
    @discardableResult
    public static func pair(code: String, identity: String) throws -> Data {
        let key = try deriveKey(fromCode: code)
        try storeKey(key, identity: identity)
        return key
    }

    /// The key for a specific peer, if paired.
    public static func key(for identity: String) -> Data? {
        loadEntries().first { $0.identity == identity }?.key
    }

    /// All stored (identity, key) pairs — used by the child listener to accept its parent.
    public static func allKeys() -> [(identity: String, key: Data)] {
        loadEntries().map { ($0.identity, $0.key) }
    }

    public static func hasAnyKey() -> Bool { !loadEntries().isEmpty }

    public static func removeKey(identity: String) throws {
        try saveEntries(loadEntries().filter { $0.identity != identity })
    }
}
