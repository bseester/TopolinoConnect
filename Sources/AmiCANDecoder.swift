    import Foundation

/// Parser for community-published AMI/Rocks-e CAN descriptions only.
/// CAN signal positions are only interpreted from CAN frames.
struct CANFrame: Equatable {
    let identifier: UInt32
    let data: [UInt8]
}

struct CommunityCANValues: Equatable {
    let rawFrame: CANFrame
    var stateOfChargePercent: UInt8? = nil
    var batteryVoltageVolts: Double? = nil
    var batteryCurrentAmps: Double? = nil
    var twelveVoltVoltage: Double? = nil
    var batteryTemperature1C: Int8? = nil
    var batteryTemperature2C: Int8? = nil
    var speedKmh: UInt8? = nil
    var rangeDBCBit0Candidate: UInt8? = nil
    var rangeTopolinoDisplayCandidate: UInt8? = nil
    var rangeEVCCBit1Candidate: UInt8? = nil
    var gear: String? = nil
    var odometerRawDBC: UInt32? = nil
    var chargeTimeRawDBC: UInt16? = nil
    var chargeTimeRawEVCC: UInt16? = nil
    var chargeTimeMinutesTopolinoCandidate: Int? = nil
    var readyDBCBit18Candidate: Bool? = nil
    var readyTopolinoDisplayCandidate: String? = nil
    var vehicleOnEVCCBit21Candidate: Bool? = nil
    var parkingBrake: Bool? = nil
}

enum AmiCANDecoder {
    static func decode(_ frame: CANFrame) -> CommunityCANValues? {
        guard frame.data.count >= 2 else { return nil }
        var values = CommunityCANValues(rawFrame: frame)
        switch frame.identifier {
        case 0x580:
            guard frame.data.count == 8 else { return nil }
            // B5 is a verified SOC candidate only for B6=0x13. Charging
            // layouts (B6=0x36/0x6C) use different, unresolved fields.
            if frame.data[6] == 0x13 && frame.data[5] <= 100 {
                values.stateOfChargePercent = frame.data[5]
            }
            let currentRaw = Int16(bitPattern: littleEndian16(frame.data, 0))
            if currentRaw != -1 { values.batteryCurrentAmps = Double(currentRaw) * 0.1 }
            let voltageRaw = littleEndian16(frame.data, 2)
            if voltageRaw != UInt16.max && voltageRaw <= 8_000 {
                values.batteryVoltageVolts = Double(voltageRaw) * 0.01
            }
        case 0x581:
            guard frame.data.count == 8 else { return nil }
            // 0xFF is the unavailable sentinel. Accept every other byte and
            // let the UI retain the last sample between slower speed frames.
            if frame.data[7] != 0xFF { values.speedKmh = frame.data[7] }
            let odometer = UInt32(frame.data[4])
                | (UInt32(frame.data[5]) << 8) | (UInt32(frame.data[6]) << 16)
            if odometer != 0x00FF_FFFF { values.odometerRawDBC = odometer }
        case 0x582:
            guard frame.data.count == 8 else { return nil }
            // The DBC and WiCAN example use opposite byte orders. Retain both candidate interpretations.
            values.chargeTimeRawDBC = littleEndian16(frame.data, 0)
            values.chargeTimeRawEVCC = (UInt16(frame.data[0]) << 8) | UInt16(frame.data[1])
            // TopolinoInfoDisplay and AMI-Display both treat the little-endian value as seconds.
            let remainingSeconds = Int(values.chargeTimeRawDBC ?? 0)
            if remainingSeconds <= 36_000 { values.chargeTimeMinutesTopolinoCandidate = remainingSeconds / 60 }
        case 0x593:
            guard frame.data.count == 8 else { return nil }
            let raw = littleEndian16(frame.data, 0)
            if raw != UInt16.max && raw <= 2_000 { values.twelveVoltVoltage = Double(raw) * 0.01 }
        case 0x594:
            guard frame.data.count == 8 else { return nil }
            values.batteryTemperature1C = Int8(bitPattern: frame.data[0])
            if frame.data.count >= 4 { values.batteryTemperature2C = Int8(bitPattern: frame.data[3]) }
        case 0x713:
            guard frame.data.count == 7 else { return nil }
            // Keep independent community interpretations visible: DBC 7-bit, TopolinoInfoDisplay 6-bit, EVCC bit-1.
            let rangeDBC = frame.data[0] & 0x7F
            let rangeTopolino = frame.data[0] & 0x3F
            let rangeEVCC = (frame.data[0] >> 1) & 0x7F
            if rangeDBC < 0x7F { values.rangeDBCBit0Candidate = rangeDBC }
            if rangeTopolino < 0x3F { values.rangeTopolinoDisplayCandidate = rangeTopolino }
            if rangeEVCC < 0x7F { values.rangeEVCCBit1Candidate = rangeEVCC }
            let rawGear = ((frame.data[0] >> 7) & 1) | ((frame.data[1] & 1) << 1)
            values.gear = ["R", "N", "D", nil][Int(rawGear)]
            values.readyDBCBit18Candidate = ((frame.data[2] >> 2) & 1) != 0
            values.vehicleOnEVCCBit21Candidate = ((frame.data[2] >> 5) & 1) != 0
            let readyState = frame.data[2] & 0x07
            if readyState == 0b101 { values.readyTopolinoDisplayCandidate = "Hazır" }
            else if readyState == 0b011 { values.readyTopolinoDisplayCandidate = "Hazır değil" }
            else { values.readyTopolinoDisplayCandidate = "Belirsiz (\(readyState))" }
            values.parkingBrake = ((frame.data[3] >> 5) & 1) != 0
        case 0x714:
            guard frame.data.count == 2 else { return nil }
            values.parkingBrake = frame.data[0] == 0x01
        default:
            return nil
        }
        return values
    }

    private static func littleEndian16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
}
