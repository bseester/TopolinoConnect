import AppKit
import SwiftUI

@main
struct TopolinoConnectMacApp: App {
    @StateObject private var monitor = MCP2515SerialMonitor()

    var body: some Scene {
        WindowGroup {
            ESP32CANView(monitor: monitor)
                .frame(minWidth: 720, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}

/// A focused bench tool for ESP32 + MCP2515 CAN capture and signal inspection.
private struct ESP32CANView: View {
    @ObservedObject var monitor: MCP2515SerialMonitor
    @State private var showRawFrames = true
    @State private var portRefreshTimer: Timer?

    private var values: [String: String] { Dictionary(uniqueKeysWithValues: monitor.metrics) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                connectionPanel
                espDiagnostics
                speedPanel
                signalPanel
                expectedFramesPanel
                trafficPanel
                frameLog
                Text("Bu araç yalnızca ESP32’den gelen CAN verisini okur ve çözümler. CAN’a/arabaya komut göndermez. Hız göstergesi doğrulaması için ham kayıtları araçtaki değerle karşılaştır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            monitor.refreshPorts()
            if !monitor.selectedPort.isEmpty { monitor.connect() }
            portRefreshTimer?.invalidate()
            portRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                guard !monitor.isConnected else { return }
                monitor.refreshPorts()
                if !monitor.selectedPort.isEmpty { monitor.connect() }
            }
        }
        .onDisappear {
            portRefreshTimer?.invalidate()
            portRefreshTimer = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Topolino · ESP CAN Monitor").font(.title2.bold())
                Text("ESP32 + MCP2515 · canlı veri okuma ve hız sinyali inceleme")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            let canIsLive = monitor.status.contains("CAN canlı") || monitor.status.contains("CAN ham veri canlı")
            Label(canIsLive ? "CAN verisi geliyor" : (monitor.isConnected ? "USB seri bağlı" : "ESP bağlı değil"),
                  systemImage: canIsLive ? "checkmark.circle.fill" : (monitor.isConnected ? "cable.connector" : "bolt.slash.circle"))
                .font(.callout.bold())
                .foregroundStyle(canIsLive ? .green : (monitor.isConnected ? .orange : .secondary))
        }
    }

    private var connectionPanel: some View {
        GroupBox("ESP32 seri bağlantısı") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("USB seri port", selection: $monitor.selectedPort) {
                        Text("Port seç").tag("")
                        ForEach(monitor.ports, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 330)
                    Button("Portları yenile") { monitor.refreshPorts() }
                    if monitor.isConnected {
                        Button("Bağlantıyı kes") { monitor.disconnect() }
                    } else {
                        Button("ESP’ye bağlan") { monitor.connect() }
                            .disabled(monitor.selectedPort.isEmpty)
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Circle().fill(monitor.isConnected ? .green : .gray).frame(width: 8, height: 8)
                    Text(monitor.status).font(.callout.bold())
                    Spacer()
                    Text("115200 baud · \(monitor.frameCount) CAN çerçevesi")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
    }

    private var espDiagnostics: some View {
        GroupBox("ESP32 / MCP2515 durum mesajları") {
            if monitor.serialMessages.isEmpty {
                Text("Seri porttan mesaj bekleniyor. Bağlantıyı kestikten sonra ESP’ye yeniden bağlanırsan açılış mesajları da görünür.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(monitor.serialMessages.suffix(10).enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(message.contains("baslatilamadi") ? .orange : .secondary)
                        }
                    }
                }
                .frame(height: 112)
            }
        }
    }

    private var speedPanel: some View {
        GroupBox {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let age = monitor.metricUpdatedAt["Hız · son CAN örneği"].map {
                    max(0, timeline.date.timeIntervalSince($0))
                }
                let fresh = age.map { $0 < 10.0 } ?? false
                let lastSpeed = values["Hız · son CAN örneği"] ?? "— km/sa"
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARAÇ HIZI · TOPOLINO CAN").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(lastSpeed)
                            .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(age == nil ? .secondary : .primary)
                        Text(speedAgeDescription(age: age, fresh: fresh))
                            .font(.callout.bold()).foregroundStyle(fresh ? .green : (age == nil ? .orange : .secondary))
                    }
                    Divider().frame(height: 84)
                    VStack(alignment: .leading, spacing: 8) {
                        metricLine("CAN çerçevesi", values["CAN çerçeve sayısı"] ?? "0")
                        metricLine("Batarya", values["Batarya"] ?? "—")
                        metricLine("Tahmini menzil", values["Tahmini menzil"] ?? "—")
                        metricLine("Vites", values["Vites"] ?? "—")
                        metricLine("Kilometre", values["Kilometre"] ?? "—")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                .padding(8)
            }
        } label: {
            Label("Hız sinyali", systemImage: "speedometer")
                .font(.headline)
        }
    }

    private func speedAgeDescription(age: TimeInterval?, fresh: Bool) -> String {
        guard let age else { return "0x581 hız çerçevesi bekleniyor" }
        return fresh ? String(format: "CAN canlı · %.1f sn önce", age) : String(format: "Son okunan · %.0f sn önce", age)
    }

    private var signalPanel: some View {
        GroupBox("Okunan CAN sinyalleri") {
            if monitor.metrics.isEmpty {
                Text("Çözülebilen sinyal bekleniyor. Ham mesajlar aşağıda görünür.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(Array(monitor.metrics.enumerated()), id: \.offset) { _, metric in
                        let age = monitor.metricUpdatedAt[metric.0].map { max(0, Int(Date().timeIntervalSince($0))) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.0).font(.caption).foregroundStyle(.secondary)
                            Text(metric.1).font(.headline.monospacedDigit())
                            Text(age.map { $0 < 2 ? "Canlı" : "\($0) sn önce" } ?? "—")
                                .font(.caption2).foregroundStyle((age ?? 99) < 3 ? .green : .orange)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .padding(9)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var trafficPanel: some View {
        GroupBox("ESP’nin gördüğü CAN kimlikleri") {
            if monitor.lastSeenByID.isEmpty {
                Text("Henüz çerçeve alınmadı.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 7) {
                    ForEach(monitor.lastSeenByID.keys.sorted(), id: \.self) { canID in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(format: "0x%03X", canID)).font(.caption.bold().monospaced())
                            Text("\(monitor.frameCountsByID[canID, default: 0]) çerçeve")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let time = monitor.lastSeenByID[canID] {
                                Text(time.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }

    private var expectedFramesPanel: some View {
        let definitions: [(UInt32, String)] = [
            (0x580, "Batarya akımı, gerilimi ve doluluk"),
            (0x581, "Hız ve kilometre sayacı"),
            (0x582, "Şarjda kalan süre"),
            (0x593, "12 V akü gerilimi"),
            (0x594, "Batarya sıcaklıkları"),
            (0x713, "Vites, menzil, READY ve park freni"),
            (0x714, "Park freni durumu")
        ]
        return GroupBox("Üç kaynakta bulunan araç mesajları") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), alignment: .leading)], alignment: .leading, spacing: 7) {
                ForEach(definitions, id: \.0) { identifier, description in
                    let count = monitor.frameCountsByID[identifier, default: 0]
                    let lastSeen = monitor.lastSeenByID[identifier]
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(count > 0 ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(format: "0x%03X", identifier)).font(.caption.bold().monospaced())
                            Text(description).font(.caption).foregroundStyle(.secondary)
                            Text(count > 0 ? "\(count) çerçeve · son \(lastSeen?.formatted(date: .omitted, time: .standard) ?? "—")" : "Henüz gelmedi")
                                .font(.caption2).foregroundStyle(count > 0 ? .green : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Text("Bu ESP yapılandırması veri sorgusu göndermez; kaynak projelerdeki gibi 500 kbit/s CAN yayınlarını dinler. Araç kapalı/uykudaysa veya OBD pinleri uyuşmuyorsa sayaçlar sıfır kalır.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var frameLog: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Son CAN çerçeveleri · en yeni üstte").font(.headline)
                    Spacer()
                    Toggle("Ham kayıtları göster", isOn: $showRawFrames).toggleStyle(.checkbox)
                }
                if showRawFrames {
                    if monitor.entries.isEmpty {
                        Text("Seri bağlantıdan CAN çerçevesi bekleniyor…")
                            .foregroundStyle(.secondary).padding(.vertical, 10)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(monitor.entries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.time.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                                        Text(entry.idText).bold()
                                        Text("DLC \(entry.dlc)")
                                        Text(entry.dataText)
                                        Spacer(minLength: 4)
                                        Text(entry.summary).foregroundStyle(entry.summary == "DBC alanı çözüldü" ? .green : .secondary)
                                    }
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 180)
                    }
                }
                HStack {
                    Text(monitor.captureLogPath.isEmpty ? "CAN kayıt dosyası hazırlanıyor…" : monitor.captureLogPath)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Dosyayı göster") {
                        guard !monitor.captureLogPath.isEmpty else { return }
                        NSWorkspace.shared.selectFile(monitor.captureLogPath, inFileViewerRootedAtPath: "")
                    }
                    .disabled(monitor.captureLogPath.isEmpty || !monitor.captureLogPath.hasSuffix(".jsonl"))
                }
                if monitor.rxOverflowCount > 0 {
                    Label("ESP MCP2515 alım taşması bildirimi: \(monitor.rxOverflowCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.callout)
    }
}
