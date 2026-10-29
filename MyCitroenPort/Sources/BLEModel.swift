import Combine
import Foundation

struct TripLocationPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double
}

struct VehicleTrip: Identifiable, Codable {
    let id: String
    let startedAt: Date
    var endedAt: Date?
    var endReason: String?
    var points: [TripLocationPoint]
    var startOdometerKm: Double? = nil
    var endOdometerKm: Double? = nil
    var startBatteryPercent: Double? = nil
    var endBatteryPercent: Double? = nil
    var startEstimatedRangeKm: Double? = nil
    var endEstimatedRangeKm: Double? = nil
}

struct ChargeSession: Identifiable, Codable {
    let id: String
    let startedAt: Date
    var endedAt: Date?
    var endReason: String? = nil
    var startBatteryPercent: Double?
    var endBatteryPercent: Double?
    var startOdometerKm: Double?
    var endOdometerKm: Double?
    var lastObservedAt: Date
}

/// iOS vehicle state store. Live vehicle data comes only from the Android relay.
final class VehicleStore: ObservableObject {
    static let shared = VehicleStore()

    @Published var gatewayConnected = false
    @Published private(set) var estimateNow = Date()
    @Published var lastParkedLocation: TripLocationPoint?
    @Published var lastParkedAt: Date?
    @Published var savedTrips: [VehicleTrip] = []
    @Published private(set) var routeHistoryRevision = 0
    @Published private(set) var chargeSessions: [ChargeSession] = []

    private let persistenceQueue = DispatchQueue(label: "local.topolinoconnect.vehicle-storage", qos: .utility)
    private let supportDirectory: URL
    private let tripsURL: URL
    private let tripsBackupURL: URL
    private let chargeSessionsURL: URL
    private var activeChargeSessionID: String?
    private var lastGatewayChargeSampleTimestamp: String?
    private var estimateTicker: AnyCancellable?

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TopolinoConnect", isDirectory: true)
        supportDirectory = directory
        tripsURL = directory.appendingPathComponent("vehicle_trips.json")
        tripsBackupURL = directory.appendingPathComponent("vehicle_trips.backup.json")
        chargeSessionsURL = directory.appendingPathComponent("charge_sessions.json")
        loadChargeSessions()
        loadVehicleTrips()
        loadLastParkedLocation()
        estimateTicker = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.estimateNow = date }
    }

    @MainActor
    func setGatewayState(connected: Bool) {
        gatewayConnected = connected
    }

    @MainActor
    func replaceAndroidRouteData(trips remoteTrips: [VehicleTrip], parkedLocation: TripLocationPoint?, parkedAt: Date?) {
        let sortedTrips = remoteTrips.sorted { $0.startedAt > $1.startedAt }
        savedTrips = sortedTrips
        if let parkedLocation { lastParkedLocation = parkedLocation }
        if let parkedAt { lastParkedAt = parkedAt }
        persistVehicleTrips()
        persistParkedLocation()
    }

    @MainActor
    func acceptGatewayChargeSample(charging: Bool?, batteryPercent: Double?, odometerKm: Double?, timestamp: String, at date: Date) {
        guard let charging, timestamp != lastGatewayChargeSampleTimestamp else { return }
        lastGatewayChargeSampleTimestamp = timestamp

        if charging {
            if let id = activeChargeSessionID,
               let index = chargeSessions.firstIndex(where: { $0.id == id }) {
                let gap = date.timeIntervalSince(chargeSessions[index].lastObservedAt)
                if gap > Self.chargeSessionObservationGapLimit {
                    chargeSessions[index].endedAt = chargeSessions[index].lastObservedAt
                    chargeSessions[index].endReason = "Bağlantı kesildi · son ESP kaydı"
                    activeChargeSessionID = nil
                } else {
                    chargeSessions[index].lastObservedAt = date
                    chargeSessions[index].endBatteryPercent = batteryPercent
                    chargeSessions[index].endOdometerKm = odometerKm
                }
            }
            if activeChargeSessionID == nil {
                let session = ChargeSession(
                    id: UUID().uuidString,
                    startedAt: date,
                    endedAt: nil,
                    startBatteryPercent: batteryPercent,
                    endBatteryPercent: batteryPercent,
                    startOdometerKm: odometerKm,
                    endOdometerKm: odometerKm,
                    lastObservedAt: date
                )
                chargeSessions.insert(session, at: 0)
                activeChargeSessionID = session.id
            }
        } else if let id = activeChargeSessionID,
                  let index = chargeSessions.firstIndex(where: { $0.id == id }) {
            let previous = chargeSessions[index].lastObservedAt
            let gap = date.timeIntervalSince(previous)
            chargeSessions[index].endedAt = gap <= Self.chargeSessionObservationGapLimit ? date : previous
            chargeSessions[index].endReason = gap > Self.chargeSessionObservationGapLimit
                ? "Bağlantı kesildi · son ESP kaydı"
                : ((batteryPercent ?? 0) >= 99 ? "Şarj tamamlandı" : "Şarj durumu sona erdi")
            if gap <= Self.chargeSessionObservationGapLimit {
                chargeSessions[index].endBatteryPercent = batteryPercent ?? chargeSessions[index].endBatteryPercent
                chargeSessions[index].endOdometerKm = odometerKm ?? chargeSessions[index].endOdometerKm
            }
            activeChargeSessionID = nil
        }
        persistChargeSessions()
    }

    func deleteSavedTrip(id: String) {
        savedTrips.removeAll { $0.id == id }
        routeHistoryRevision += 1
        persistVehicleTrips()
    }

    private static let chargeSessionObservationGapLimit: TimeInterval = 15 * 60

    private func loadChargeSessions() {
        guard let data = try? Data(contentsOf: chargeSessionsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        chargeSessions = (try? decoder.decode([ChargeSession].self, from: data)) ?? []
        activeChargeSessionID = chargeSessions.first(where: { $0.endedAt == nil })?.id
    }

    private func persistChargeSessions() {
        let sessions = chargeSessions
        let destination = chargeSessionsURL
        let directory = supportDirectory
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(sessions).write(to: destination, options: .atomic)
            } catch {
                NSLog("Şarj geçmişi kaydedilemedi: %@", error.localizedDescription)
            }
        }
    }

    private func loadVehicleTrips() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loadedFromBackup = false
        var trips = (try? Data(contentsOf: tripsURL)).flatMap { try? decoder.decode([VehicleTrip].self, from: $0) }
        if trips == nil {
            trips = (try? Data(contentsOf: tripsBackupURL)).flatMap { try? decoder.decode([VehicleTrip].self, from: $0) }
            loadedFromBackup = trips != nil
        }
        guard let trips else { return }
        savedTrips = trips.sorted { $0.startedAt > $1.startedAt }
        if loadedFromBackup { NSLog("Rotalar yedek kayıttan kurtarıldı") }
    }

    private func persistVehicleTrips() {
        let trips = savedTrips.sorted { $0.startedAt > $1.startedAt }
        let destination = tripsURL
        let backup = tripsBackupURL
        let directory = supportDirectory
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(trips)
                try data.write(to: destination, options: .atomic)
                try data.write(to: backup, options: .atomic)
                #if os(iOS)
                let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                try? FileManager.default.setAttributes(protection, ofItemAtPath: destination.path)
                try? FileManager.default.setAttributes(protection, ofItemAtPath: backup.path)
                #endif
            } catch {
                NSLog("Rota kaydedilemedi: %@", error.localizedDescription)
            }
        }
    }

    private func loadLastParkedLocation() {
        guard let data = UserDefaults.standard.data(forKey: "topolino.lastParkedLocation") else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        lastParkedLocation = try? decoder.decode(TripLocationPoint.self, from: data)
        lastParkedAt = UserDefaults.standard.object(forKey: "topolino.lastParkedAt") as? Date
    }

    private func persistParkedLocation() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let point = lastParkedLocation, let data = try? encoder.encode(point) {
            UserDefaults.standard.set(data, forKey: "topolino.lastParkedLocation")
        }
        if let lastParkedAt { UserDefaults.standard.set(lastParkedAt, forKey: "topolino.lastParkedAt") }
    }
}
