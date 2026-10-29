import Combine
import Foundation
import Security

struct AndroidGatewayEnvelope: Decodable {
    let status: String?
    let isStale: Bool?
    let espTemperature: AndroidGatewayTemperature?
    let espCan: AndroidGatewayCANTelemetry?
}

struct AndroidGatewayCANTelemetry: Decodable {
    let timestamp: String
    let canLive: Bool?
    let odometerKm: Double?
    let batteryPercent: Int?
    let rangeKm: Int?
    let voltageV: Double?
    let currentA: Double?
    let batteryPowerKw: Double?
    let battery12V: Double?
    let temperature1C: Int?
    let temperature2C: Int?
    let gear: String?
    let ready: Bool?
    let handbrake: Bool?
    let charging: Bool?
    let chargeMinutesRemaining: Int?
    let chargePowerKw: Double?
    let sessionTripDistanceKm: Double?
    let sessionEnergyOutKwh: Double?
    let sessionEnergyInKwh: Double?
    let sessionRegenCandidateKwh: Double?
    let sessionEstimatedDriveEnergyKwh: Double?
    let sessionEstimatedConsumptionKwhPer100Km: Double?
    let canFrameCount: Int?
    let gattFrameStatus: String?
    let canFrames: [AndroidGatewayCANFrame]?
    let isStale: Bool?
}

struct AndroidGatewayCANFrame: Decodable, Identifiable {
    let id: String
    let extended: Bool?
    let dlc: Int
    let data: String
    let timestampUs: UInt32?
    let timestamp: String?
}

struct ESPChargeSnapshot: Codable {
    var timestamp: String
    var observedAt: Date
    var batteryPercent: Double
    var odometerKm: Double?
    var gear: String?
    var chargeMinutesRemaining: Int?
    var chargePowerKw: Double?
    var voltageV: Double?
    var currentA: Double?
    var batteryPowerKw: Double?
    var charging: Bool
}

struct ESPClassicChargeEstimate {
    let batteryPercent: Double
    let rangeKm: Double
    let minutesRemaining: Int?
    let isCharging: Bool
    let sourceTimestamp: String
    let lastChargePowerKw: Double?
    let odometerKm: Double?
    let gear: String?
    let voltageV: Double?
    let currentA: Double?
    let batteryPowerKw: Double?
}

struct AndroidGatewayTemperature: Decodable {
    let celsius: Double
    let timestamp: String
    let rssi: Int?
    let isStale: Bool?

    var observedAt: Date? { GatewayTimestamp.parse(timestamp) }
}

private struct AndroidGatewayRoutes: Decodable {
    let trips: [VehicleTrip]
    let lastParkedLocation: AndroidGatewayLocation?
    let lastParkedAt: String?
}

private struct AndroidGatewayRoutesUpload: Encodable {
    let trips: [VehicleTrip]
    let lastParkedLocation: TripLocationPoint?
    let lastParkedAt: Date?
}

struct AndroidGatewayLocation: Decodable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let speedMetersPerSecond: Double
    let timestamp: String

    enum CodingKeys: String, CodingKey { case latitude, longitude, accuracyMeters, horizontalAccuracyMeters, speedMetersPerSecond, timestamp }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        accuracyMeters = try values.decodeIfPresent(Double.self, forKey: .accuracyMeters)
            ?? values.decode(Double.self, forKey: .horizontalAccuracyMeters)
        speedMetersPerSecond = try values.decodeIfPresent(Double.self, forKey: .speedMetersPerSecond) ?? 0
        timestamp = try values.decode(String.self, forKey: .timestamp)
    }

    var observedAt: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}

enum GatewayTimestamp {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }

        // Android Instant.toString() can emit 1–9 fractional digits; some
        // Foundation versions only parse milliseconds. Keep the first three
        // digits, which is sufficient for freshness and UI timestamps.
        let pattern = #"\.(\d+)(?=Z|[+-]\d{2}:?\d{2}$)"#
        let normalized: String
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let fullRange = Range(match.range, in: value),
           let fractionRange = Range(match.range(at: 1), in: value) {
            let milliseconds = String((String(value[fractionRange]) + "000").prefix(3))
            normalized = value.replacingCharacters(in: fullRange, with: ".\(milliseconds)")
        } else {
            normalized = value
        }
        if let date = formatter.date(from: normalized) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

}

@MainActor
final class AndroidGatewayClient: ObservableObject {
    @Published private(set) var endpoint: String
    @Published private(set) var accessKey: String
    @Published private(set) var isEnabled: Bool
    @Published private(set) var status = "Android ağ geçidi ayarlanmadı"
    @Published private(set) var isReachable = false
    @Published private(set) var lastFetchAt: Date?
    @Published private(set) var latestTemperature: AndroidGatewayTemperature?
    @Published private(set) var latestEspCan: AndroidGatewayCANTelemetry?
    @Published private(set) var latestIsStale = false
    @Published private(set) var lastESPChargeSnapshot: ESPChargeSnapshot?

    var liveEspCan: AndroidGatewayCANTelemetry? {
        guard !latestIsStale, latestEspCan?.isStale != true else { return nil }
        return latestEspCan
    }

    private let defaults = UserDefaults.standard
    private let defaultEndpoint = "https://topolino-gateway-relay.88doruk55.workers.dev"
    private let enabledKey = "androidGatewayEnabled"
    private let chargeSnapshotKey = "androidGateway.lastESPChargeSnapshot"
    private var pollTask: Task<Void, Never>?
    private weak var vehicle: VehicleStore?
    private var lastRoutesFetchAt: Date = .distantPast
    private var didSeedRouteHistory = false
    private var lastPushedRouteHistoryRevision: Int?
    // Aktif uygulamada veri yokken de 15 sn'de kontrol et; Android sonradan
    // paketi röleye yazarsa iPhone'un 5 dk beklemesini önler. GET yanıtı küçüktür.
    private let livePollInterval: UInt64 = 1_000_000_000
    private let offlinePollInterval: UInt64 = 15_000_000_000
    // Recover quickly after a temporary network hiccup. A one-minute backoff
    // made a healthy Android stream look dead after a single failed request.
    private let errorPollInterval: UInt64 = 5_000_000_000
    private var nextPollInterval: UInt64 = 300_000_000_000

    init() {
        // Use the deployed relay consistently. A stale endpoint persisted by an
        // earlier local-IP/Tailscale build must not silently route iOS elsewhere.
        let relayEndpoint = "https://topolino-gateway-relay.88doruk55.workers.dev"
        endpoint = relayEndpoint
        UserDefaults.standard.set(relayEndpoint, forKey: "androidGatewayEndpoint")
        accessKey = GatewayKeychain.load() ?? ""
        isEnabled = UserDefaults.standard.bool(forKey: "androidGatewayEnabled")
        if let data = defaults.data(forKey: chargeSnapshotKey) {
            lastESPChargeSnapshot = try? JSONDecoder().decode(ESPChargeSnapshot.self, from: data)
        }
    }

    func classicChargeEstimate(at date: Date = .now) -> ESPClassicChargeEstimate? {
        guard let sample = lastESPChargeSnapshot else { return nil }
        let elapsedMinutes = sample.charging ? max(0, date.timeIntervalSince(sample.observedAt) / 60) : 0
        let soc: Double
        let remaining: Int?
        if sample.charging, let initialMinutes = sample.chargeMinutesRemaining, initialMinutes > 0 {
            let elapsed = min(Double(initialMinutes), elapsedMinutes)
            soc = min(100, sample.batteryPercent + (100 - sample.batteryPercent) * elapsed / Double(initialMinutes))
            remaining = max(0, initialMinutes - Int(elapsedMinutes))
        } else {
            soc = sample.batteryPercent
            remaining = sample.charging ? sample.chargeMinutesRemaining : nil
        }
        let range = max(0, 18 + (soc - 27) * (11.0 / 14.0))
        let estimatedCharging = sample.charging && (remaining.map { $0 > 0 } ?? true)
        return ESPClassicChargeEstimate(
            batteryPercent: soc,
            rangeKm: range,
            minutesRemaining: remaining,
            isCharging: estimatedCharging,
            sourceTimestamp: sample.timestamp,
            lastChargePowerKw: sample.chargePowerKw,
            odometerKm: sample.odometerKm,
            gear: sample.gear,
            voltageV: sample.voltageV,
            currentA: sample.currentA,
            batteryPowerKw: sample.batteryPowerKw
        )
    }

    func save(accessKey: String) -> String? {
        let cleanedEndpoint = defaultEndpoint
        guard !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Android uygulamasındaki erişim anahtarını gir."
        }
        self.endpoint = cleanedEndpoint
        self.accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(cleanedEndpoint, forKey: "androidGatewayEndpoint")
        GatewayKeychain.save(self.accessKey)
        status = "Adres kaydedildi · bağlantı denenebilir"
        return nil
    }

    func setEnabled(_ enabled: Bool, vehicle: VehicleStore) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            startPolling(vehicle: vehicle)
        } else {
            stopPolling()
            isReachable = false
            vehicle.setGatewayState(connected: false)
        }
    }

    func startPolling(vehicle: VehicleStore) {
        self.vehicle = vehicle
        if lastPushedRouteHistoryRevision == nil { lastPushedRouteHistoryRevision = vehicle.routeHistoryRevision }
        guard isEnabled, !endpoint.isEmpty, !accessKey.isEmpty else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await fetchLatest()
                do { try await Task.sleep(nanoseconds: nextPollInterval) }
                catch { break }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isReachable = false
        vehicle?.setGatewayState(connected: false)
    }

    func fetchNow(vehicle: VehicleStore) {
        self.vehicle = vehicle
        Task { await fetchLatest() }
    }

    private func fetchLatest() async {
        guard isEnabled else { return }
        await fetchRouteHistory()
        guard let url = latestURL() else {
            status = "Android API adresini kontrol et"
            isReachable = false
            vehicle?.setGatewayState(connected: false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue(accessKey, forHTTPHeaderField: "X-Topolino-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GatewayClientError.badResponse }
            lastFetchAt = Date()
            isReachable = true
            if http.statusCode == 204 {
                latestIsStale = latestEspCan != nil
                nextPollInterval = offlinePollInterval
                status = "Röle yanıt veriyor · ESP CAN yayını bekleniyor"
                vehicle?.setGatewayState(connected: false)
                return
            }
            guard http.statusCode == 200 else { throw GatewayClientError.http(http.statusCode) }
            let envelope = try JSONDecoder().decode(AndroidGatewayEnvelope.self, from: data)
            latestTemperature = envelope.espTemperature
            latestEspCan = envelope.espCan
            latestIsStale = envelope.isStale ?? false
            if let can = envelope.espCan {
                let observedAt = GatewayTimestamp.parse(can.timestamp)
                latestIsStale = latestIsStale || (observedAt.map { Date().timeIntervalSince($0) >= 45 } ?? true)
                if !latestIsStale || can.charging == true {
                    persistChargeSnapshot(from: can, observedAt: observedAt ?? Date())
                }
                nextPollInterval = livePollInterval
                status = latestIsStale ? "ESP CAN · Android’den son bilinen veri" : "ESP CAN · Android’den canlı veri alınıyor"
                vehicle?.setGatewayState(connected: !latestIsStale)
                if !latestIsStale, let observedAt {
                    vehicle?.acceptGatewayChargeSample(
                        charging: can.charging,
                        batteryPercent: can.batteryPercent.map(Double.init),
                        odometerKm: can.odometerKm,
                        timestamp: can.timestamp,
                        at: observedAt
                    )
                }
            } else {
                nextPollInterval = offlinePollInterval
                status = envelope.status ?? "ESP CAN verisi bekleniyor · 15 sn sonra yeniden denenecek"
                vehicle?.setGatewayState(connected: false)
            }
        } catch {
            isReachable = false
            if latestEspCan != nil { latestIsStale = true }
            nextPollInterval = errorPollInterval
            status = Self.connectionMessage(for: error)
            vehicle?.setGatewayState(connected: false)
        }
    }

    private func persistChargeSnapshot(from can: AndroidGatewayCANTelemetry, observedAt: Date) {
        if can.charging == true, let batteryPercent = can.batteryPercent {
            if let existing = lastESPChargeSnapshot, existing.observedAt >= observedAt { return }
            lastESPChargeSnapshot = ESPChargeSnapshot(
                timestamp: can.timestamp,
                observedAt: observedAt,
                batteryPercent: Double(batteryPercent),
                odometerKm: can.odometerKm,
                gear: can.gear,
                chargeMinutesRemaining: can.chargeMinutesRemaining,
                chargePowerKw: can.chargePowerKw,
                voltageV: can.voltageV,
                currentA: can.currentA,
                batteryPowerKw: can.batteryPowerKw,
                charging: true
            )
            saveChargeSnapshot()
        } else if can.charging == false, var sample = lastESPChargeSnapshot {
            // Preserve the last ESP reading captured while charging for offline
            // SOC/range calculations, but stop its countdown after ESP confirms
            // that charging ended.
            sample.charging = false
            sample.chargeMinutesRemaining = nil
            lastESPChargeSnapshot = sample
            saveChargeSnapshot()
        }
    }

    private func saveChargeSnapshot() {
        guard let snapshot = lastESPChargeSnapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: chargeSnapshotKey)
    }

    private func fetchRouteHistory() async {
        guard isEnabled, Date().timeIntervalSince(lastRoutesFetchAt) >= 25,
              !endpoint.isEmpty, !accessKey.isEmpty,
              let url = routeHistoryURL() else { return }
        lastRoutesFetchAt = Date()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(accessKey, forHTTPHeaderField: "X-Topolino-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                guard let date = GatewayTimestamp.parse(value) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Rota zamanı çözümlenemedi")
                }
                return date
            }
            let routes = try decoder.decode(AndroidGatewayRoutes.self, from: data)
            if routes.trips.isEmpty, !didSeedRouteHistory,
               let vehicle, !vehicle.savedTrips.isEmpty {
                didSeedRouteHistory = true
                await seedExistingRouteHistory(vehicle: vehicle)
                return
            }
            if let vehicle,
               let lastPushedRouteHistoryRevision,
               vehicle.routeHistoryRevision != lastPushedRouteHistoryRevision {
                await uploadCurrentRouteHistory(vehicle: vehicle)
                return
            }
            let parkedPoint: TripLocationPoint? = routes.lastParkedLocation.flatMap { remote in
                guard let date = remote.observedAt else { return nil }
                return TripLocationPoint(timestamp: date, latitude: remote.latitude, longitude: remote.longitude,
                                         horizontalAccuracyMeters: remote.accuracyMeters,
                                         speedMetersPerSecond: max(0, remote.speedMetersPerSecond))
            }
            let parkedAt = routes.lastParkedAt.flatMap(GatewayTimestamp.parse)
            vehicle?.replaceAndroidRouteData(trips: routes.trips, parkedLocation: parkedPoint, parkedAt: parkedAt)
        } catch {
            // Route synchronization is independent from live vehicle telemetry.
            // Keep the last locally mirrored history available while offline.
        }
    }

    private func seedExistingRouteHistory(vehicle: VehicleStore) async {
        await uploadCurrentRouteHistory(vehicle: vehicle)
    }

    private func uploadCurrentRouteHistory(vehicle: VehicleStore) async {
        guard let url = routeHistoryURL() else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "PUT"
        request.setValue(accessKey, forHTTPHeaderField: "X-Topolino-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = AndroidGatewayRoutesUpload(trips: vehicle.savedTrips,
                                                 lastParkedLocation: vehicle.lastParkedLocation,
                                                 lastParkedAt: vehicle.lastParkedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(payload) else { return }
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 202 {
                lastPushedRouteHistoryRevision = vehicle.routeHistoryRevision
            }
        } catch { }
    }

    private static func connectionMessage(for error: Error) -> String {
        if case GatewayClientError.http(let code) = error {
            if code == 401 { return "Erişim anahtarı hatalı · Android ekranındaki anahtarı kopyala" }
            return "Android API HTTP hatası · \(code)"
        }
        let networkError = error as? URLError
        switch networkError?.code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            return "Cloudflare rölesine ulaşılamıyor · internet bağlantısını kontrol et"
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS bu HTTP bağlantısını engelledi · Android adresini ve yerel ağ iznini kontrol et"
        default:
            return error.localizedDescription
        }
    }

    private func latestURL() -> URL? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        let latestRoute = "api/v1/vehicle/latest"
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath == latestRoute {
            return components.url
        }
        components.path = "/" + ([basePath, latestRoute].filter { !$0.isEmpty }.joined(separator: "/"))
        return components.url
    }

    private func routeHistoryURL() -> URL? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("api/v1/vehicle/latest") { path.removeLast("api/v1/vehicle/latest".count) }
        components.path = "/" + ([path, "api/v1/vehicle/routes"].filter { !$0.isEmpty }.joined(separator: "/"))
        return components.url
    }
}

private enum GatewayClientError: LocalizedError {
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Android API geçerli yanıt vermedi"
        case .http(401): return "Erişim anahtarı hatalı"
        case .http(let code): return "Android API yanıtı: HTTP \(code)"
        }
    }
}

private enum GatewayKeychain {
    private static let account = "android-gateway-access-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "MyCitroenPort",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "MyCitroenPort",
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
