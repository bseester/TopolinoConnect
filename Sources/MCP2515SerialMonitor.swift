import Combine
import Darwin
import Foundation

struct CANSerialEntry: Identifiable {
    let id = UUID()
    let time: Date
    let identifier: UInt32
    let isExtended: Bool
    let dlc: Int
    let bytes: [UInt8]
    let summary: String
    let espTimestampMicros: UInt32?

    var idText: String { String(format: "%@0x%0*X", isExtended ? "29-bit " : "11-bit ", isExtended ? 8 : 3, identifier) }
    var dataText: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

final class MCP2515SerialMonitor: ObservableObject {
    private static let frameRegex = try! NSRegularExpression(
        pattern: #"CAN (11|29)-bit ID=0x([0-9A-Fa-f]+) DLC=(\d+) DATA=([0-9A-Fa-f ]*)"#
    )
    @Published private(set) var ports: [String] = []
    @Published var selectedPort = ""
    @Published private(set) var isConnected = false
    @Published private(set) var status = "ESP32 seri portunu seç"
    @Published private(set) var frameCount = 0
    @Published private(set) var metrics: [(String, String)] = []
    @Published private(set) var entries: [CANSerialEntry] = []
    @Published private(set) var serialMessages: [String] = []
    @Published private(set) var recognizedCounts: [UInt32: Int] = [:]
    @Published private(set) var frameCountsByID: [UInt32: Int] = [:]
    @Published private(set) var lastSeenByID: [UInt32: Date] = [:]
    @Published private(set) var speedSampleCount = 0
    @Published private(set) var speedFilteredKmh: Int?
    @Published private(set) var metricUpdatedAt: [String: Date] = [:]
    @Published private(set) var speedIntervalMilliseconds: Double?
    @Published private(set) var speedRateHz: Double?
    @Published private(set) var speedMaxGapMilliseconds: Double?
    @Published private(set) var rxOverflowCount = 0
    @Published private(set) var captureLogPath = ""

    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var shouldRead = false
    private var speedSamples: [Int] = []
    private var currentSamples: [Double] = []
    private var voltageSamples: [Double] = []
    private var speedIntervals: [Double] = []
    private var lastSpeedEspTimestamp: UInt32?
    private var lastPowerEspTimestamp: UInt32?
    private var latestSpeedKmh: UInt8?
    private var latestChargeMinutes: Int?
    private var energyInKWh = 0.0
    private var energyOutKWh = 0.0
    private var energyRecoveryCandidateKWh = 0.0
    private let logQueue = DispatchQueue(label: "local.topolinoconnect.can-log", qos: .utility)
    private var logHandle: FileHandle?
    private let decoderQueue = DispatchQueue(label: "local.topolinoconnect.mcp-serial", qos: .userInitiated)

    func refreshPorts() {
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let found = candidates.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted().map { "/dev/\($0)" }
        ports = found
        if !found.contains(selectedPort) { selectedPort = found.first ?? "" }
        if found.isEmpty { status = "USB seri port bulunamadı · ESP32 USB ile bağlı olmalı" }
        else if !isConnected { status = "ESP32 seri portu hazır" }
    }

    func connect() {
        guard !selectedPort.isEmpty else { status = "Önce seri portu seç"; return }
        disconnect(updateStatus: false)
        let fd = Darwin.open(selectedPort, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { status = "Port açılamadı: \(selectedPort)"; return }
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            Darwin.close(fd)
            status = "Seri port ayarlanamadı"
            return
        }
        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            Darwin.close(fd)
            status = "115200 baud ayarı uygulanamadı"
            return
        }
        tcflush(fd, TCIOFLUSH)
        lock.lock()
        descriptor = fd
        shouldRead = true
        lock.unlock()
        entries = []
        serialMessages = []
        metrics = []
        recognizedCounts = [:]
        frameCountsByID = [:]
        lastSeenByID = [:]
        speedSampleCount = 0
        speedSamples = []
        currentSamples = []
        voltageSamples = []
        speedFilteredKmh = nil
        speedIntervals = []
        lastSpeedEspTimestamp = nil
        lastPowerEspTimestamp = nil
        latestSpeedKmh = nil
        latestChargeMinutes = nil
        energyInKWh = 0
        energyOutKWh = 0
        energyRecoveryCandidateKWh = 0
        speedIntervalMilliseconds = nil
        speedRateHz = nil
        speedMaxGapMilliseconds = nil
        lastEspTimestampByID = [:]
        rxOverflowCount = 0
        metricUpdatedAt = [:]
        frameCount = 0
        isConnected = true
        startCaptureLog()
        status = "USB seri bağlı · ESP32/MCP2515 CAN çerçevesi bekleniyor · 115200 baud"
        decoderQueue.async { [weak self] in self?.readLoop(fd: fd) }
    }

    func disconnect() { disconnect(updateStatus: true) }

    private func disconnect(updateStatus: Bool) {
        lock.lock()
        let fd = descriptor
        descriptor = -1
        shouldRead = false
        lock.unlock()
        if fd >= 0 { Darwin.close(fd) }
        closeCaptureLog()
        DispatchQueue.main.async {
            self.isConnected = false
            if updateStatus { self.status = "Seri bağlantı kapatıldı" }
        }
    }

    private func readLoop(fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 2048)
        while true {
            lock.lock()
            let shouldContinue = shouldRead && descriptor == fd
            lock.unlock()
            guard shouldContinue else { return }

            let count = chunk.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                buffer.append(contentsOf: chunk.prefix(count))
                while let newline = buffer.firstIndex(of: 10) {
                    let lineData = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    let line = String(decoding: lineData, as: UTF8.self)
                    recordSerialMessage(line)
                    if let telemetry = Self.parseTelemetry(line) { acceptTelemetry(telemetry) }
                    else if let entry = Self.parse(line) { accept(entry) }
                    else if let overflow = Self.parseOverflowCount(line) {
                        DispatchQueue.main.async {
                            self.rxOverflowCount = max(self.rxOverflowCount, overflow)
                            if line.hasPrefix("STAT "), self.frameCount == 0 {
                                self.status = "ESP çalışıyor · CAN çerçevesi bekleniyor; araç/CAN hattı sessiz olabilir"
                            }
                        }
                    }
                }
            } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.status = "Seri bağlantı koptu"
                }
                disconnect(updateStatus: false)
                return
            } else {
                usleep(1_000)
            }
        }
    }

    private func recordSerialMessage(_ line: String) {
        // CAN frames have their own bounded frame list; publishing each one again
        // through diagnostics would force an extra SwiftUI refresh per frame.
        guard !line.isEmpty, !line.hasPrefix("CAN "), !line.hasPrefix("{\"type\":\"telemetry\"") else { return }
        let message = String(line.prefix(240))
        DispatchQueue.main.async {
            self.serialMessages.append(message)
            if self.serialMessages.count > 30 {
                self.serialMessages.removeFirst(self.serialMessages.count - 30)
            }
            if message.contains("MCP2515 baslatilamadi") {
                self.status = "MCP2515 başlatılamadı · SPI, besleme ve kristal bağlantısını kontrol et"
            } else if message.contains("MCP2515 hazir") {
                self.status = "MCP2515 hazır · araçtan CAN çerçevesi bekleniyor"
            } else if message.hasPrefix("STAT "), self.frameCount == 0 {
                self.status = message.contains("BUS=QUIET")
                    ? "MCP2515 hazır ama hatta çerçeve yok · araç uyanık mı, OBD 6/14 bağlantısı doğru mu?"
                    : "ESP çalışıyor · ilk araç CAN çerçevesi bekleniyor"
            }
        }
    }

    private func acceptTelemetry(_ packet: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            func number(_ key: String) -> Double? { (packet[key] as? NSNumber)?.doubleValue }
            func text(_ key: String, digits: Int = 1) -> String? {
                guard let value = number(key) else { return nil }
                return digits == 0 ? String(Int(value)) : String(format: "%.*f", digits, value)
            }

            let now = Date()
            let canIsLive = (packet["can"] as? Bool) ?? false
            let frames = Int(number("frames") ?? 0)
            var current = Dictionary(uniqueKeysWithValues: self.metrics)
            func put(_ name: String, _ value: String?) {
                guard let value else { return }
                current[name] = value
                self.metricUpdatedAt[name] = now
            }

            if let speed = number("speed_kmh") {
                let value = Int(speed.rounded())
                self.latestSpeedKmh = UInt8(clamping: value)
                self.speedFilteredKmh = value
                put("Hız · son CAN örneği", "\(value) km/sa")
                put("Hız · 5 örnek medyanı", "\(value) km/sa")
            }
            put("Kilometre", text("odometer_km").map { "\($0) km" })
            if let soc = number("soc_pct"), soc >= 0, soc <= 100 { put("Batarya", "\(Int(soc))%") }
            put("Tahmini menzil", text("range_km", digits: 0).map { "\($0) km" })
            put("Batarya gerilimi · ham", text("voltage_v").map { "\($0) V" })
            put("Batarya akımı · ham", text("current_a").map { "\($0) A" })
            put("12 V akü", text("battery_12v").map { "\($0) V" })
            if let temp1 = number("temp1_c"), temp1 > -90 { put("Batarya sıcaklığı 1", "\(Int(temp1)) °C") }
            if let temp2 = number("temp2_c"), temp2 > -90 { put("Batarya sıcaklığı 2", "\(Int(temp2)) °C") }
            if let minutes = number("remaining_min"), minutes >= 0 { put("Kalan şarj süresi", "\(Int(minutes)) dk") }
            if let gear = packet["gear"] as? String, !gear.isEmpty { put("Vites", gear) }
            if let ready = number("ready"), ready >= 0 { put("Araç hazır", ready == 1 ? "Evet" : "Hayır") }
            if let handbrake = number("handbrake"), handbrake >= 0 { put("El freni", handbrake == 1 ? "Çekili" : "İndirilmiş") }
            put("CAN çerçeve sayısı", String(frames))

            self.frameCount = frames
            self.metrics = current.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            self.status = canIsLive
                ? "CAN canlı · Topolino verisi · \(frames) çerçeve"
                : "USB seri bağlı · araç CAN çerçevesi bekleniyor"
        }
    }

    private func accept(_ entry: CANSerialEntry) {
        appendCaptureLog(entry)
        DispatchQueue.main.async {
            self.frameCount += 1
            self.entries.insert(entry, at: 0)
            if self.entries.count > 250 { self.entries.removeLast(self.entries.count - 250) }
            self.lastSeenByID[entry.identifier] = entry.time
            self.frameCountsByID[entry.identifier, default: 0] += 1
            if let timestamp = entry.espTimestampMicros {
                self.lastEspTimestampByID[entry.identifier] = timestamp
            }
            if let decoded = AmiCANDecoder.decode(CANFrame(identifier: entry.identifier, data: entry.bytes)) {
                self.recognizedCounts[entry.identifier, default: 0] += 1
                self.apply(decoded)
                self.status = "CAN canlı · \(self.frameCount) çerçeve · son \(entry.idText)"
            } else {
                self.status = "CAN ham veri canlı · \(self.frameCount) çerçeve · son \(entry.idText)"
            }
        }
    }

    private func apply(_ value: CommunityCANValues) {
        var current = Dictionary(uniqueKeysWithValues: metrics)
        let now = Date()
        if let soc = value.stateOfChargePercent { current["Batarya"] = "\(soc)%"; metricUpdatedAt["Batarya"] = now }
        if let voltage = value.batteryVoltageVolts {
            voltageSamples.append(voltage)
            if voltageSamples.count > 3 { voltageSamples.removeFirst(voltageSamples.count - 3) }
            let averageVoltage = voltageSamples.reduce(0, +) / Double(voltageSamples.count)
            current["Batarya gerilimi · ham"] = String(format: "%.2f V", voltage)
            current["Batarya gerilimi · 3 örnek ortalaması"] = String(format: "%.2f V", averageVoltage)
            metricUpdatedAt["Batarya gerilimi · ham"] = now
            metricUpdatedAt["Batarya gerilimi · 3 örnek ortalaması"] = now
        }
        if let amps = value.batteryCurrentAmps {
            currentSamples.append(amps)
            if currentSamples.count > 3 { currentSamples.removeFirst(currentSamples.count - 3) }
            let averageAmps = currentSamples.reduce(0, +) / Double(currentSamples.count)
            current["Batarya akımı · ham"] = String(format: "%.1f A", amps)
            current["Batarya akımı · 3 örnek ortalaması"] = String(format: "%.1f A", averageAmps)
            metricUpdatedAt["Batarya akımı · ham"] = now
            metricUpdatedAt["Batarya akımı · 3 örnek ortalaması"] = now
        }
        if let voltage = value.batteryVoltageVolts, let amps = value.batteryCurrentAmps {
            // Both display projects use consumption = -(battery current × voltage).
            // Keep the sign convention labelled as a community-source candidate until vehicle validation.
            let consumptionPowerKw = -(voltage * amps / 1_000)
            current["Batarya gücü · tüketim işaret adayı"] = String(format: "%+.2f kW", consumptionPowerKw)
            if consumptionPowerKw < 0 {
                current["Enerji akış yorumu"] = (latestSpeedKmh ?? 0) > 0
                    ? "Bataryaya dönüş adayı · rejenerasyon doğrulanmadı"
                    : "Şarj yönü adayı · CAN durumu doğrulanacak"
            } else {
                current["Enerji akış yorumu"] = "Bataryadan çekiş yönü adayı"
            }
            metricUpdatedAt["Batarya gücü · tüketim işaret adayı"] = now
            metricUpdatedAt["Enerji akış yorumu"] = now

            if let timestamp = entryTimestamp(for: value.rawFrame), let previous = lastPowerEspTimestamp {
                let deltaUs = timestamp &- previous
                // Ignore long gaps so a parked/offline interval is never counted as energy.
                if deltaUs > 0 && deltaUs <= 2_000_000 {
                    let deltaHours = Double(deltaUs) / 3_600_000_000
                    if consumptionPowerKw < 0 {
                        energyInKWh += -consumptionPowerKw * deltaHours
                        if (latestSpeedKmh ?? 0) > 0 {
                            energyRecoveryCandidateKWh += -consumptionPowerKw * deltaHours
                        }
                    } else {
                        energyOutKWh += consumptionPowerKw * deltaHours
                    }
                }
            }
            if let timestamp = entryTimestamp(for: value.rawFrame) { lastPowerEspTimestamp = timestamp }
            current["Enerji girişi · oturum tahmini"] = String(format: "%.4f kWh", energyInKWh)
            current["Enerji çıkışı · oturum tahmini"] = String(format: "%.4f kWh", energyOutKWh)
            current["Rejenerasyon · yalnızca aday"] = String(format: "%.4f kWh", energyRecoveryCandidateKWh)
            metricUpdatedAt["Enerji girişi · oturum tahmini"] = now
            metricUpdatedAt["Enerji çıkışı · oturum tahmini"] = now
            metricUpdatedAt["Rejenerasyon · yalnızca aday"] = now
        }
        if let speed = value.speedKmh {
            latestSpeedKmh = speed
            speedSampleCount += 1
            speedSamples.append(Int(speed))
            if speedSamples.count > 5 { speedSamples.removeFirst(speedSamples.count - 5) }
            let sorted = speedSamples.sorted()
            speedFilteredKmh = sorted[sorted.count / 2]
            current["Hız · son CAN örneği"] = "\(speed) km/sa"
            current["Hız · 5 örnek medyanı"] = "\(speedFilteredKmh!) km/sa"
            current["Hız · örnek sayısı"] = "\(speedSampleCount)"
            metricUpdatedAt["Hız · son CAN örneği"] = now
            metricUpdatedAt["Hız · 5 örnek medyanı"] = now
            metricUpdatedAt["Hız · örnek sayısı"] = now
            if let timestamp = entryTimestamp(for: value.rawFrame) {
                updateSpeedCadence(timestampUs: timestamp, at: now, values: &current)
            }
        }
        if let odo = value.odometerRawDBC { current["Kilometre"] = String(format: "%.1f km", Double(odo) * 0.1); metricUpdatedAt["Kilometre"] = now }
        if let range = value.rangeDBCBit0Candidate { current["Menzil · DBC 7-bit adayı"] = "\(range) km"; metricUpdatedAt["Menzil · DBC 7-bit adayı"] = now }
        if let range = value.rangeTopolinoDisplayCandidate { current["Menzil · Topolino ekran adayı"] = "\(range) km"; metricUpdatedAt["Menzil · Topolino ekran adayı"] = now }
        if let range = value.rangeEVCCBit1Candidate { current["Menzil · EVCC bit-1 adayı"] = "\(range) km"; metricUpdatedAt["Menzil · EVCC bit-1 adayı"] = now }
        if let gear = value.gear { current["Vites · CAN 0x713 adayı"] = gear; metricUpdatedAt["Vites · CAN 0x713 adayı"] = now }
        if let ready = value.readyTopolinoDisplayCandidate { current["READY · Topolino ekran adayı"] = ready; metricUpdatedAt["READY · Topolino ekran adayı"] = now }
        if let ready = value.readyDBCBit18Candidate { current["READY · DBC bit-18 adayı"] = ready ? "Açık" : "Kapalı"; metricUpdatedAt["READY · DBC bit-18 adayı"] = now }
        if let on = value.vehicleOnEVCCBit21Candidate { current["Araç açık · EVCC bit-21 adayı"] = on ? "Açık" : "Kapalı"; metricUpdatedAt["Araç açık · EVCC bit-21 adayı"] = now }
        if let brake = value.parkingBrake { current["Park freni"] = brake ? "Etkin" : "Kapalı"; metricUpdatedAt["Park freni"] = now }
        if let time = value.chargeTimeRawDBC { current["Şarj zamanı · DBC little-endian ham"] = "\(time)"; metricUpdatedAt["Şarj zamanı · DBC little-endian ham"] = now }
        if let time = value.chargeTimeRawEVCC { current["Şarj zamanı · byte-swap ham"] = "\(time)"; metricUpdatedAt["Şarj zamanı · byte-swap ham"] = now }
        if let minutes = value.chargeTimeMinutesTopolinoCandidate {
            latestChargeMinutes = minutes
            current["Doluma kalan süre · Topolino aday"] = "\(minutes) dk"
            metricUpdatedAt["Doluma kalan süre · Topolino aday"] = now
        }
        if let v12 = value.twelveVoltVoltage { current["12 V akü"] = String(format: "%.2f V", v12); metricUpdatedAt["12 V akü"] = now }
        if let temp = value.batteryTemperature1C { current["Batarya sıcaklığı 1"] = "\(temp) °C"; metricUpdatedAt["Batarya sıcaklığı 1"] = now }
        if let temp = value.batteryTemperature2C { current["Batarya sıcaklığı 2"] = "\(temp) °C"; metricUpdatedAt["Batarya sıcaklığı 2"] = now }
        metrics = current.keys.sorted().map { ($0, current[$0] ?? "—") }
    }

    private func updateSpeedCadence(timestampUs: UInt32, at now: Date, values: inout [String: String]) {
        if let previous = lastSpeedEspTimestamp {
            let deltaUs = timestampUs &- previous
            if deltaUs > 0 && deltaUs < 30_000_000 {
                let intervalMs = Double(deltaUs) / 1_000
                speedIntervals.append(intervalMs)
                if speedIntervals.count > 30 { speedIntervals.removeFirst(speedIntervals.count - 30) }
                let mean = speedIntervals.reduce(0, +) / Double(speedIntervals.count)
                let maxGap = speedIntervals.max() ?? intervalMs
                speedIntervalMilliseconds = intervalMs
                speedRateHz = mean > 0 ? 1_000 / mean : nil
                speedMaxGapMilliseconds = maxGap
                values["Hız mesaj aralığı · son"] = String(format: "%.1f ms", intervalMs)
                values["Hız mesaj sıklığı · 30 örnek ort."] = String(format: "%.1f Hz", speedRateHz ?? 0)
                values["Hız mesaj aralığı · en uzun"] = String(format: "%.1f ms", maxGap)
                metricUpdatedAt["Hız mesaj aralığı · son"] = now
                metricUpdatedAt["Hız mesaj sıklığı · 30 örnek ort."] = now
                metricUpdatedAt["Hız mesaj aralığı · en uzun"] = now
            }
        }
        lastSpeedEspTimestamp = timestampUs
    }

    private func entryTimestamp(for frame: CANFrame) -> UInt32? {
        // Timestamp is supplied by the ESP serial parser and cached by CAN ID.
        lastEspTimestampByID[frame.identifier]
    }

    private var lastEspTimestampByID: [UInt32: UInt32] = [:]

    private func startCaptureLog() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Topolino ESP CAN Monitor/Captures", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss'Z'"
            let url = directory.appendingPathComponent("esp-can-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).jsonl")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            logQueue.sync {
                logHandle = try? FileHandle(forWritingTo: url)
            }
            captureLogPath = url.path
        } catch {
            captureLogPath = "Kayıt dosyası açılamadı: \(error.localizedDescription)"
        }
    }

    private func appendCaptureLog(_ entry: CANSerialEntry) {
        logQueue.async { [weak self] in
            guard let self, let handle = self.logHandle else { return }
            let formatter = ISO8601DateFormatter()
            let object: [String: Any] = [
                "timestamp_utc": formatter.string(from: entry.time),
                "esp_timestamp_us": (entry.espTimestampMicros.map { NSNumber(value: $0) } as Any?) ?? NSNull(),
                "can_id": String(format: "0x%0*X", entry.isExtended ? 8 : 3, entry.identifier),
                "extended": entry.isExtended,
                "dlc": entry.dlc,
                "data_hex": entry.dataText,
                "decoder_match": entry.summary
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
            try? handle.write(contentsOf: data + Data([0x0A]))
        }
    }

    private func closeCaptureLog() {
        logQueue.async { [weak self] in
            try? self?.logHandle?.synchronize()
            try? self?.logHandle?.close()
            self?.logHandle = nil
        }
    }

    private static func parse(_ line: String) -> CANSerialEntry? {
        let parts = line.components(separatedBy: " TS_US=")
        let frameLine = parts[0]
        let espTimestamp = parts.count > 1 ? UInt32(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        guard let match = Self.frameRegex.firstMatch(in: frameLine, range: NSRange(frameLine.startIndex..., in: frameLine)),
              let idRange = Range(match.range(at: 2), in: frameLine),
              let dlcRange = Range(match.range(at: 3), in: frameLine),
              let dataRange = Range(match.range(at: 4), in: frameLine),
              let identifier = UInt32(frameLine[idRange], radix: 16),
              let dlc = Int(frameLine[dlcRange]),
              let formatRange = Range(match.range(at: 1), in: frameLine) else { return nil }
        let extended = (frameLine[formatRange] == "29")
        let bytes = frameLine[dataRange].split(whereSeparator: { $0.isWhitespace }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == min(dlc, 8) else { return nil }
        let summary = AmiCANDecoder.decode(CANFrame(identifier: identifier, data: bytes)) == nil ? "Ham · eşleşme yok" : "DBC alanı çözüldü"
        return CANSerialEntry(time: Date(), identifier: identifier, isExtended: extended, dlc: dlc, bytes: bytes, summary: summary, espTimestampMicros: espTimestamp)
    }

    private static func parseTelemetry(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("{\"type\":\"telemetry\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let packet = object as? [String: Any],
              packet["type"] as? String == "telemetry" else { return nil }
        return packet
    }

    private static func parseOverflowCount(_ line: String) -> Int? {
        guard line.hasPrefix("STAT "), let range = line.range(of: "RX_OVERFLOW=") else { return nil }
        return Int(line[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first ?? "")
    }
}
