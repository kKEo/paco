import Foundation

/// JSON coding for the PaCo Cloud device API.
///
/// Dates are ISO-8601 without fractional seconds (`2026-10-16T18:00:00Z`), the
/// format the server emits and accepts. Local files and XPC payloads keep the
/// default `JSONEncoder` (seconds since 2001); only cloud traffic goes through
/// here, plus the cloud payloads the daemon hands the app over XPC.
public enum CloudCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}
