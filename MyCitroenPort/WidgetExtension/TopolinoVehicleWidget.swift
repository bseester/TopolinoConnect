import SwiftUI
import WidgetKit

private struct VehicleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetVehicleSnapshot
}

private struct VehicleProvider: TimelineProvider {
    func placeholder(in context: Context) -> VehicleEntry {
        VehicleEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleEntry) -> Void) {
        completion(VehicleEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleEntry>) -> Void) {
        let now = Date()
        let stored = WidgetSnapshotStore.load()
        // Recompute the saved charging countdown, including an estimated-full state.
        // WidgetKit controls actual delivery and may defer any requested refresh.
        let entries = (0...12).map { step -> VehicleEntry in
            let date = now.addingTimeInterval(Double(step) * 5 * 60)
            return VehicleEntry(date: date, snapshot: estimatedSnapshot(stored, at: date))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }

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

    private func estimatedSnapshot(_ snapshot: WidgetVehicleSnapshot, at date: Date) -> WidgetVehicleSnapshot {
        guard snapshot.charging == true,
              let latestText = snapshot.timestamp,
              let latest = parseDate(latestText),
              date.timeIntervalSince(latest) > 30,
              let startText = snapshot.chargeSampleTimestamp,
              let startDate = parseDate(startText),
              let startSOC = snapshot.chargeSampleBatteryPercent,
              let initial = snapshot.chargeInitialMinutes, initial > 0 else { return snapshot }
        let elapsed = max(0, date.timeIntervalSince(startDate) / 60)
        let left = max(0, min(initial, initial - Int(elapsed)))
        let soc = max(startSOC, min(100, 100 - (100 - startSOC) * Double(left) / Double(initial)))
        let range = max(0, 18 + (soc - 27) * (11.0 / 14.0))
        return WidgetVehicleSnapshot(
            batteryPercent: soc,
            rangeKm: range,
            odometerKm: snapshot.odometerKm,
            gear: snapshot.gear,
            charging: left == 0 ? false : true,
            chargeMinutesRemaining: left,
            chargeSampleBatteryPercent: snapshot.chargeSampleBatteryPercent,
            chargeSampleTimestamp: snapshot.chargeSampleTimestamp,
            chargeInitialMinutes: snapshot.chargeInitialMinutes,
            isConnected: snapshot.isConnected,
            timestamp: snapshot.timestamp
        )
    }
}

private struct VehicleWidgetView: View {
    let entry: VehicleEntry
    @Environment(\.widgetFamily) private var family

    private var widgetBackground: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.03, green: 0.22, blue: 0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var battery: String {
        entry.snapshot.batteryPercent.map { "\(Int($0.rounded()))%" } ?? "—%"
    }
    private var range: String {
        entry.snapshot.rangeKm.map { "\(Int($0.rounded())) km" } ?? "— km"
    }
    private var isFresh: Bool {
        guard let stamp = entry.snapshot.timestamp,
              let updated = parseDate(stamp) else { return false }
        return entry.date.timeIntervalSince(updated) < 45
    }
    private var remainingChargeTime: String? {
        guard entry.snapshot.charging == true,
              let minutes = entry.snapshot.chargeMinutesRemaining, minutes > 0 else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours) sa \(rest) dk" }
        if hours > 0 { return "\(hours) sa" }
        return "\(rest) dk"
    }
    private var status: String {
        if entry.snapshot.chargeMinutesRemaining == 0,
           entry.snapshot.chargeSampleTimestamp != nil,
           let stamp = entry.snapshot.timestamp,
           let updated = parseDate(stamp),
           entry.date.timeIntervalSince(updated) > 30 {
            return "Tahmini şarj tamamlandı"
        }
        if entry.snapshot.charging == true {
            let prefix = isFresh ? "Şarj oluyor" : "Son kayda göre şarjda"
            return remainingChargeTime.map { "\(prefix) · \($0) kaldı" } ?? prefix
        }
        return isFresh ? "Araç bağlı · canlı bilgi" : "Son bilinen bilgi"
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "car.side.fill").foregroundStyle(Color.mint)
            Text("TOPOLINO").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
            Spacer(minLength: 0)
            Circle().fill(isFresh ? Color.mint : Color.gray).frame(width: 7, height: 7)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 2)
            Text(battery)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mint)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("Batarya")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1).padding(.vertical, 2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(range).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                Text("menzil").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Text(status)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var lockScreenContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "car.side.fill")
                Text("Topolino")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                if isFresh {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.mint)
            HStack(spacing: 5) {
                Image(systemName: "battery.100percent")
                Text(battery)
                    .fontWeight(.bold)
                Text("·")
                Text(range)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            if entry.snapshot.charging == true {
                Text(remainingChargeTime.map { "Şarjda · \($0) kaldı" } ?? status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var circularLockScreenContent: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(range.replacingOccurrences(of: " km", with: ""))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("km")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(battery).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Color.mint)
                    Text("Batarya").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 36)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(range).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Kalan menzil").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            HStack(spacing: 4) {
                Text(status)
                if let odo = entry.snapshot.odometerKm {
                    Text("· \(odo.formatted(.number.precision(.fractionLength(0...1)))) km")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            if entry.snapshot.charging == true {
                Label(remainingChargeTime.map { "Doluma kalan \($0)" } ?? "Şarjda", systemImage: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.mint).lineLimit(1)
            }
        }
    }

    private var content: some View {
        Group {
            if family == .accessoryCircular { circularLockScreenContent }
            else if family == .accessoryRectangular { lockScreenContent }
            else if family == .systemSmall { smallContent }
            else { mediumContent }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { widgetBackground }
        } else {
            content.background(widgetBackground)
        }
    }
}

@main
struct TopolinoVehicleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: VehicleProvider()) { entry in
            VehicleWidgetView(entry: entry)
        }
        .configurationDisplayName("my FIAT")
        .description("Batarya ve kalan menzil bilgisi; ana ekran ve kilit ekranı widget’ı.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
