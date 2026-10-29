import SwiftUI
import WatchConnectivity

@main
struct MyFIATWatchApp: App {
    @StateObject private var vehicle = WatchVehicleModel.shared

    var body: some Scene {
        WindowGroup {
            WatchDashboard(snapshot: vehicle.snapshot)
                .preferredColorScheme(.dark)
        }
    }
}

final class WatchVehicleModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchVehicleModel()

    @Published private(set) var snapshot = WatchVehicleSnapshot.empty

    private override init() {
        super.init()
        load(WCSession.default.receivedApplicationContext)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func load(_ context: [String: Any]) {
        guard let data = context["vehicleSnapshot"] as? Data,
              let value = try? JSONDecoder().decode(WatchVehicleSnapshot.self, from: data) else { return }
        snapshot = value
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.load(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.load(message) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async { [weak self] in self?.load(context) }
    }
}

private struct WatchDashboard: View {
    let snapshot: WatchVehicleSnapshot

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        let pattern = #"\.(\d+)(?=Z|[+-]\d{2}:?\d{2}$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let fullRange = Range(match.range, in: value),
              let fractionRange = Range(match.range(at: 1), in: value) else {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        let fraction = String((String(value[fractionRange]) + "000").prefix(3))
        let normalized = value.replacingCharacters(in: fullRange, with: ".\(fraction)")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: normalized)
    }

    private func chargeEstimate(at date: Date) -> (batteryPercent: Double, rangeKm: Double, minutesRemaining: Int)? {
        guard snapshot.charging == true,
              let startSOC = snapshot.chargeSampleBatteryPercent,
              let initialMinutes = snapshot.chargeInitialMinutes, initialMinutes > 0,
              let stamp = snapshot.chargeSampleTimestamp,
              let start = parseDate(stamp) else { return nil }
        let elapsed = max(0, date.timeIntervalSince(start) / 60)
        let remaining = max(0, initialMinutes - Int(elapsed))
        let soc = max(startSOC, min(100, 100 - (100 - startSOC) * Double(remaining) / Double(initialMinutes)))
        return (soc, max(0, 18 + (soc - 27) * (11.0 / 14.0)), remaining)
    }

    private func status(at date: Date) -> String {
        if let estimate = chargeEstimate(at: date) {
            let minutes = estimate.minutesRemaining
                if minutes == 0 { return "Şarj tamamlandı (tahmin)" }
                let hours = minutes / 60
                let rest = minutes % 60
                if hours > 0 && rest > 0 { return "ESP şarj kaydı · \(hours) sa \(rest) dk" }
                if hours > 0 { return "ESP şarj kaydı · \(hours) sa" }
                return "ESP şarj kaydı · \(rest) dk"
        }
        if snapshot.charging == true { return "Son ESP şarj verisi" }
        return snapshot.timestamp == nil ? "Araç verisi bekleniyor" : "Son alınan araç bilgisi"
    }

    private func lastUpdate(at date: Date) -> String {
        guard let stamp = snapshot.timestamp,
              let updated = parseDate(stamp) else { return "Henüz veri yok" }
        return updated.formatted(.relative(presentation: .named))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let estimate = chargeEstimate(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "car.side.fill").foregroundStyle(.mint)
                        Text("my FIAT").font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(estimate.map { "\(Int($0.batteryPercent.rounded()))%" } ?? snapshot.batteryPercent.map { "\(Int($0.rounded()))%" } ?? "—%")
                            .font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.mint)
                        Text("batarya").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(estimate.map { "≈ \(Int($0.rangeKm.rounded())) km" } ?? snapshot.rangeKm.map { "\(Int($0.rounded())) km" } ?? "— km", systemImage: "bolt.batteryblock.fill")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text("Kalan menzil").font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(status(at: context.date)).font(.caption.bold()).foregroundStyle(snapshot.charging == true ? .mint : .white)
                    if let odometer = snapshot.odometerKm {
                        Label("\(odometer.formatted(.number.precision(.fractionLength(0...1)))) km", systemImage: "gauge.with.dots.needle.50percent")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Güncelleme: \(lastUpdate(at: context.date))")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .containerBackground(Color(red: 0.035, green: 0.055, blue: 0.105).gradient, for: .navigation)
        }
    }
}
