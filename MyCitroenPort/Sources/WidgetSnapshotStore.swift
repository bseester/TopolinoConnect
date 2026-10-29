import Foundation
import WidgetKit

struct WidgetVehicleSnapshot: Codable, Equatable {
    let batteryPercent: Double?
    let rangeKm: Double?
    let odometerKm: Double?
    let gear: String?
    let charging: Bool?
    let chargeMinutesRemaining: Int?
    let chargeSampleBatteryPercent: Double?
    let chargeSampleTimestamp: String?
    let chargeInitialMinutes: Int?
    let isConnected: Bool
    let timestamp: String?

    static let empty = WidgetVehicleSnapshot(
        batteryPercent: nil, rangeKm: nil, odometerKm: nil, gear: nil,
        charging: nil, chargeMinutesRemaining: nil, chargeSampleBatteryPercent: nil,
        chargeSampleTimestamp: nil, chargeInitialMinutes: nil, isConnected: false, timestamp: nil
    )
}

enum WidgetSnapshotStore {
    static let appGroup = "group.local.topolinoconnect.mycitroenport.shared"
    static let storageKey = "latestVehicleSnapshot"
    static let widgetKind = "MyCitroenVehicleWidget"
    private static let lastReloadKey = "lastVehicleWidgetReload"
    private static let minimumReloadInterval: TimeInterval = 60

    static func save(_ snapshot: WidgetVehicleSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot),
              defaults.data(forKey: storageKey) != data else { return }
        defaults.set(data, forKey: storageKey)

        // Keep the shared snapshot current for the next widget read, while
        // avoiding a reload request for every BLE packet.
        let now = Date()
        let lastReload = defaults.object(forKey: lastReloadKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(lastReload) >= minimumReloadInterval else { return }
        defaults.set(now, forKey: lastReloadKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func load() -> WidgetVehicleSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetVehicleSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
