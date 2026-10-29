import XCTest
@testable import TopolinoConnect

final class AmiCANDecoderTests: XCTestCase {
    func testSOCIsOnlyDecodedForKnownFrameLayout() {
        let verifiedLayout = CANFrame(identifier: 0x580, data: [0, 0, 0x58, 0x1B, 0, 78, 0x13, 0])
        let chargeLayout = CANFrame(identifier: 0x580, data: [0, 0, 0x58, 0x1B, 0, 78, 0x36, 0])

        XCTAssertEqual(AmiCANDecoder.decode(verifiedLayout)?.stateOfChargePercent, 78)
        XCTAssertNil(AmiCANDecoder.decode(chargeLayout)?.stateOfChargePercent)
    }

    func testSpeedSentinelAndInvalidLengthsAreRejected() {
        let speed = CANFrame(identifier: 0x581, data: [0, 0, 0, 0, 0, 0, 0, 42])
        let unavailable = CANFrame(identifier: 0x581, data: [0, 0, 0, 0, 0, 0, 0, 0xFF])
        let malformed = CANFrame(identifier: 0x581, data: [0, 0])

        XCTAssertEqual(AmiCANDecoder.decode(speed)?.speedKmh, 42)
        XCTAssertNil(AmiCANDecoder.decode(unavailable)?.speedKmh)
        XCTAssertNil(AmiCANDecoder.decode(malformed))
    }
}
