import XCTest
@testable import OnePlusConnect

final class BleProtocolTests: XCTestCase {
    func testV2CommandFrameHasExpectedLengthAndVersion() {
        let frame = BleProtocol.encodeCommand(BleProtocol.cmdConnect, secret: String(repeating: "a", count: 32), nonce: 0x0102030405060708)

        XCTAssertEqual(frame.count, 26)
        XCTAssertEqual(frame.first, 2)
        XCTAssertEqual(frame.dropFirst().first, BleProtocol.cmdConnect)
        XCTAssertEqual(Array(frame.suffix(16)), [
            0xd4, 0xe6, 0x88, 0x00, 0xb9, 0x4a, 0x40, 0x16,
            0x43, 0xdf, 0x56, 0xa8, 0xa1, 0x6d, 0xbc, 0xb0
        ])
    }

    func testStatusRejectsUnsupportedVersionAndTruncatedSSID() {
        XCTAssertNil(BleProtocol.parseStatus(Data([1, 0, 0xff, 0])))
        XCTAssertNil(BleProtocol.parseStatus(Data([2, 1, 0xff, 3, 0x61])))
    }
}
