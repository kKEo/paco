import XCTest
@testable import PaCoShared

final class FrameCodecTests: XCTestCase {

    func testMessageRoundTrip() throws {
        let payload = try JSONEncoder().encode(ExtensionRequestPayload(requestId: UUID(), childDeviceName: "Kid", requestedMinutes: 30, reason: "hw"))
        let message = PaCoMessage(command: .requestExtension, payload: payload)
        let frame = try message.encoded()

        let header = frame.prefix(FrameCodec.headerLength)
        let length = try XCTUnwrap(FrameCodec.bodyLength(header: header))
        XCTAssertEqual(length, frame.count - FrameCodec.headerLength)

        let body = try XCTUnwrap(FrameCodec.decodeBody(frame.dropFirst(FrameCodec.headerLength)))
        XCTAssertEqual(body.type, .message)
        let decoded = try JSONDecoder().decode(PaCoMessage.self, from: body.json)
        XCTAssertEqual(decoded.command, .requestExtension)
        XCTAssertEqual(decoded.payload, payload)
    }

    func testResponseFrameIsTaggedAsResponse() throws {
        let frame = try PaCoResponse(success: false, error: "nope").encoded()
        let body = try XCTUnwrap(FrameCodec.decodeBody(frame.dropFirst(FrameCodec.headerLength)))
        XCTAssertEqual(body.type, .response)
        XCTAssertEqual(try JSONDecoder().decode(PaCoResponse.self, from: body.json).error, "nope")
    }

    func testHeaderIsBigEndian() {
        let frame = FrameCodec.encode(type: .message, json: Data(repeating: 0x41, count: 255))
        XCTAssertEqual(Array(frame.prefix(4)), [0, 0, 1, 0])  // 256 = 1 type byte + 255
        XCTAssertEqual(FrameCodec.bodyLength(header: frame.prefix(4)), 256)
    }

    func testMalformedHeadersAreRejected() {
        XCTAssertNil(FrameCodec.bodyLength(header: Data([0, 0, 0, 0])), "zero length")
        XCTAssertNil(FrameCodec.bodyLength(header: Data([0xFF, 0xFF, 0xFF, 0xFF])), "over the cap")
        XCTAssertNil(FrameCodec.bodyLength(header: Data([0, 1])), "short header")
        XCTAssertNil(FrameCodec.decodeBody(Data()), "empty body")
        XCTAssertNil(FrameCodec.decodeBody(Data([9, 1, 2]))?.type, "unknown frame type")
    }
}
