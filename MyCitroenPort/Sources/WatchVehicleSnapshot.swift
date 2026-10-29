import Foundation

struct WatchVehicleSnapshot: Codable, Equatable {
    let batteryPercent: Double?
    let rangeKm: Double?
    let odometerKm: Double?
    let gear: String?
    let charging: Bool?
    let chargeMinutesRemaining: Int?
    let chargeSampleBatteryPercent: Double?
    let chargeSampleTimestamp: String?
    let chargeInitialMinutes: Int?
    let timestamp: String?

    static let empty = WatchVehicleSnapshot(
        batteryPercent: nil,
        rangeKm: nil,
        odometerKm: nil,
        gear: nil,
        charging: nil,
        chargeMinutesRemaining: nil,
        chargeSampleBatteryPercent: nil,
        chargeSampleTimestamp: nil,
        chargeInitialMinutes: nil,
        timestamp: nil
    )
}
