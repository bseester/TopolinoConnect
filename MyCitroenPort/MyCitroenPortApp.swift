import SwiftUI
import UIKit
import CoreLocation
import MapKit

/// Original dark navy and mint palette used by the first test UI.
private enum CitroenTheme {
    static let brand = Color.mint
    static let brandBright = Color.mint
    static let electric = Color.mint
    static let navy = Color(red: 0.035, green: 0.055, blue: 0.105)
    static let blueGrey = Color(red: 0.34, green: 0.44, blue: 0.56)
    static let red = Color.orange
    static let text = Color.white
    static let muted = Color.white.opacity(0.72)
    static let mutedLight = Color.gray
    static let divider = Color.white.opacity(0.15)
    static let surface = Color(red: 0.07, green: 0.11, blue: 0.19)
    static let canvas = Color(red: 0.035, green: 0.055, blue: 0.105)
    static let softSurface = Color.white.opacity(0.06)
    static let success = Color.mint
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

@main
struct MyCitroenPortApp: App {
    @StateObject private var vehicle = VehicleStore.shared
    @StateObject private var gateway = AndroidGatewayClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MyCitroenShell(vehicle: vehicle, gateway: gateway)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        gateway.startPolling(vehicle: vehicle)
                    } else if phase == .background {
                        gateway.stopPolling()
                    }
                }
        }
    }
}

private struct MyCitroenShell: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = 0
    @State private var showChargeDetails = false

    private var activeCan: AndroidGatewayCANTelemetry? { gateway.liveEspCan }
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            tabContainer
        }
        .background(CitroenTheme.canvas.ignoresSafeArea())
        .foregroundStyle(CitroenTheme.text)
        .tint(CitroenTheme.brand)
        .onAppear {
            syncWidgetSnapshot()
            gateway.startPolling(vehicle: vehicle)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active || phase == .background { syncWidgetSnapshot() }
        }
        .onChange(of: vehicle.estimateNow) { _ in syncWidgetSnapshot() }
        .onChange(of: gateway.latestEspCan?.timestamp) { _ in syncWidgetSnapshot() }
        .onChange(of: vehicle.gatewayConnected) { _ in syncWidgetSnapshot() }
        .sheet(isPresented: $showChargeDetails) {
            NavigationStack {
                ChargePage(vehicle: vehicle, gateway: gateway)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { showChargeDetails = false } } }
            }
             .preferredColorScheme(.dark)
        }
    }

    private func syncWidgetSnapshot() {
        let can = activeCan
        let fresh = can != nil
        let snapshot = WidgetVehicleSnapshot(
            batteryPercent: can?.canLive == false ? classicCharge?.batteryPercent : (can?.batteryPercent.map(Double.init) ?? classicCharge?.batteryPercent),
            rangeKm: can?.canLive == false ? classicCharge?.rangeKm : (can?.rangeKm.map(Double.init) ?? classicCharge?.rangeKm),
            odometerKm: can?.canLive == false ? classicCharge?.odometerKm : (can?.odometerKm ?? classicCharge?.odometerKm),
            gear: can?.canLive == false ? nil : can?.gear,
            charging: can?.charging ?? classicCharge?.isCharging,
            chargeMinutesRemaining: can?.chargeMinutesRemaining ?? classicCharge?.minutesRemaining,
            chargeSampleBatteryPercent: gateway.lastESPChargeSnapshot?.batteryPercent,
            chargeSampleTimestamp: gateway.lastESPChargeSnapshot?.timestamp,
            chargeInitialMinutes: gateway.lastESPChargeSnapshot?.chargeMinutesRemaining,
            isConnected: fresh,
            timestamp: can?.timestamp ?? gateway.lastESPChargeSnapshot?.timestamp
        )
        WidgetSnapshotStore.save(snapshot)
        WatchSnapshotBridge.shared.publish(WatchVehicleSnapshot(
            batteryPercent: snapshot.batteryPercent,
            rangeKm: snapshot.rangeKm,
            odometerKm: snapshot.odometerKm,
            gear: snapshot.gear,
            charging: snapshot.charging,
            chargeMinutesRemaining: snapshot.chargeMinutesRemaining,
            chargeSampleBatteryPercent: snapshot.chargeSampleBatteryPercent,
            chargeSampleTimestamp: snapshot.chargeSampleTimestamp,
            chargeInitialMinutes: snapshot.chargeInitialMinutes,
            timestamp: snapshot.timestamp
        ))
    }

    @ViewBuilder
    private var tabContainer: some View {
        if #available(iOS 26.0, *) {
            nativeTabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            nativeTabs
        }
    }

    private var nativeTabs: some View {
        TabView(selection: $selected) {
            dashboard
                .tabItem { Label("Araç", systemImage: "car.side.fill") }
                .tag(0)
            ChargePage(vehicle: vehicle, gateway: gateway)
                .tabItem { Label("Şarj", systemImage: "bolt.fill") }
                .tag(1)
            AlertsPage(vehicle: vehicle, gateway: gateway)
                .tabItem { Label("Araç durumu", systemImage: "checkmark.shield.fill") }
                .tag(2)
            MorePage(vehicle: vehicle, gateway: gateway)
                .tabItem { Label("Diğer", systemImage: "ellipsis") }
                .tag(3)
        }
        .toolbarBackground(CitroenTheme.canvas, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tint(CitroenTheme.brand)
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            if let logoURL = Bundle.main.url(forResource: "fiat-wordmark", withExtension: "png", subdirectory: "assets"),
               let image = UIImage(contentsOfFile: logoURL.path) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 82, height: 42)
                    .accessibilityLabel("FIAT")
            } else {
                Text("my FIAT").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(CitroenTheme.brand)
            }
            Spacer()
            Label(vehicle.gatewayConnected ? "ESP bağlı" : "ESP bekleniyor",
                  systemImage: vehicle.gatewayConnected ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .font(.caption.bold()).foregroundStyle(vehicle.gatewayConnected ? CitroenTheme.brand : CitroenTheme.muted)
        }
        .padding(.horizontal, 18).padding(.top, 7).padding(.bottom, 4)
    }

    private func apkTabIcon(_ name: String) -> Image {
        Image(systemName: name == "icon_user" ? "person.crop.circle.fill" : name)
    }

    private var dashboard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        apkTabIcon("icon_user")
                            .frame(width: 42, height: 42).foregroundStyle(CitroenTheme.brand)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Topolino").font(.custom("CitroenType-Bold", size: 17))
                            Text("Araç profili").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(vehicle.gatewayConnected ? CitroenTheme.brand : CitroenTheme.mutedLight)
                            .frame(width: 10, height: 10)
                        Text(vehicle.gatewayConnected ? "Canlı ESP verisi" : "ESP bekleniyor")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Araç durumu").font(.caption).foregroundStyle(.secondary)
                        Text("Topolino").font(.custom("CitroenType-Bold", size: 28))
                        Text("Elektrikli şehir otomobili").font(.subheadline).foregroundStyle(.secondary)
                    }

                    carArtwork
                        .frame(maxWidth: .infinity)
                        .frame(height: 205)
                        .padding(.horizontal, 8)
                        .background(Color(red: 0.055, green: 0.09, blue: 0.16), in: RoundedRectangle(cornerRadius: 24))

                    HStack(spacing: 10) {
                        locationCard
                        parkTimeCard
                    }

                    HStack(spacing: 0) {
                        batteryGauge
                        Rectangle().fill(CitroenTheme.divider).frame(width: 1, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayRangeText).font(.custom("CitroenType-Bold", size: 26)).foregroundStyle(CitroenTheme.brand)
                            Text("Kalan menzil").font(.caption).foregroundStyle(CitroenTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                    }
                    .padding(16)
                    .background(Color(red: 0.02, green: 0.25, blue: 0.27), in: RoundedRectangle(cornerRadius: 22))

                    chargeEfficiencyCard

                    if let can = activeCan {
                        espDriveCard(can)
                    } else if let classicCharge {
                        classicChargeCard(classicCharge)
                    }

                    Button { showChargeDetails = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bolt.fill").font(.title3).foregroundStyle(CitroenTheme.brand)
                                .frame(width: 48, height: 48).background(CitroenTheme.brand.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Şarj ve araç bilgisi").font(.custom("CitroenType-Bold", size: 16))
                Text("Şarj: \(chargeStatus) · Kalan süre: \((activeCan?.chargeMinutesRemaining ?? classicCharge?.minutesRemaining).map(chargeMinutesText) ?? chargeDelayText)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(CitroenTheme.brand)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)


                    VStack(alignment: .leading, spacing: 10) {
                        Text("Araç bilgileri").font(.custom("CitroenType-Bold", size: 17))
                        HStack(spacing: 10) {
                            infoTile("Kilometre sayacı", value: odometerText, detail: "Son araç verisi")
                            infoTile("Vites", value: activeCan?.gear ?? classicCharge?.gear ?? "—", detail: connectionLabel)
                        }
                        infoTile("Son veri", value: latestTimestamp, detail: vehicleDataSourceLabel)
                    }

                    if gateway.isEnabled {
                        Label(vehicle.gatewayConnected ? "ESP CAN · Android’den canlı veri alınıyor" : "ESP CAN · son bilinen veri kullanılıyor",
                              systemImage: vehicle.gatewayConnected ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(vehicle.gatewayConnected ? CitroenTheme.brand : CitroenTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                        if let can = activeCan {
                            if can.canLive != false {
                                HStack(spacing: 10) {
                                    infoTile("Batarya", value: can.batteryPercent.map { "\($0)%" } ?? "—", detail: "ESP CAN")
                                    infoTile("Menzil", value: can.rangeKm.map { "\($0) km" } ?? "—", detail: "ESP CAN")
                                }
                                HStack(spacing: 10) {
                                    infoTile("Vites", value: can.gear ?? "—", detail: "ESP CAN")
                                    infoTile("READY", value: can.ready.map { $0 ? "Hazır" : "Kapalı" } ?? "—", detail: "ESP CAN")
                                }
                                HStack(spacing: 10) {
                                    infoTile("El freni", value: can.handbrake.map { $0 ? "Çekili" : "İndirilmiş" } ?? "—", detail: "ESP CAN")
                                    infoTile("Çekiş gerilimi", value: can.voltageV.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "—", detail: "ESP CAN")
                                }
                                HStack(spacing: 10) {
                                    infoTile("Çekiş akımı", value: can.currentA.map { "\($0.formatted(.number.precision(.fractionLength(1)))) A" } ?? "—", detail: "ESP CAN")
                                    infoTile("12 V akü", value: can.battery12V.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "—", detail: "ESP CAN")
                                }
                            }
                            HStack(spacing: 10) {
                                infoTile("Şarj", value: can.charging.map { $0 ? "Şarj oluyor" : "Şarjda değil" } ?? "—", detail: "ESP CAN")
                                infoTile("Doluma kalan", value: can.chargeMinutesRemaining.map(chargeMinutesText) ?? "—", detail: "ESP CAN")
                            }
                            if let power = can.chargePowerKw {
                                infoTile("Şarj gücü", value: "\(power.formatted(.number.precision(.fractionLength(1)))) kW", detail: "ESP CAN")
                            }
                            if can.canLive != false, let power = can.batteryPowerKw {
                                infoTile("Batarya akışı · işaret adayı", value: "\(power.formatted(.number.precision(.fractionLength(2)))) kW", detail: "Araçta doğrulanacak")
                                PowerFlowMeter(powerKw: power)
                            }
                        }
                        if let temperature = gateway.latestTemperature {
                            HStack(spacing: 12) {
                                Image(systemName: "thermometer.medium")
                                    .font(.title3.weight(.semibold)).foregroundStyle(CitroenTheme.brand)
                                    .frame(width: 42, height: 42)
                                    .background(CitroenTheme.brand.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Kabin sıcaklığı").font(.subheadline.bold())
                                    Text(temperature.isStale == true ? "Son ölçüm · \(temperature.observedAt?.formatted(date: .omitted, time: .shortened) ?? "zaman bilinmiyor")" : "Android’den canlı ölçüm")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("\(temperature.celsius.formatted(.number.precision(.fractionLength(1)))) °C")
                                    .font(.custom("CitroenType-Bold", size: 21)).foregroundStyle(CitroenTheme.brand)
                            }
                            .padding(14)
                            .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                    } else {
                        Button { gateway.setEnabled(true, vehicle: vehicle) } label: {
                            Label("ESP CAN Android ağ geçidini kullan", systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gateway.accessKey.isEmpty)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
            }
            .background(CitroenTheme.canvas)
            .navigationBarHidden(true)
        }
    }

    private var batteryText: String { activeCan?.batteryPercent.map { "\($0)%" } ?? classicCharge.map { "≈ \(Int($0.batteryPercent.rounded()))%" } ?? "—%" }
    private var rangeText: String { activeCan?.rangeKm.map { "\($0) km" } ?? classicCharge.map { "≈ \(Int($0.rangeKm.rounded())) km" } ?? "— km" }
    private var displayBatteryText: String {
        batteryText
    }
    private var displayRangeText: String {
        rangeText
    }
    private var odometerText: String { activeCan?.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? classicCharge?.odometerKm.map { "≈ \($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "— km" }
    private var chargeStatus: String {
        guard let can = activeCan else {
            guard let classicCharge else { return "ESP verisi bekleniyor" }
            return classicCharge.isCharging ? "Klasik hesap · son şarjdan beri" : "Son şarj ESP kaydı"
        }
        if can.charging == true { return "Şarj oluyor" }
        if can.charging == false { return "Şarjda değil" }
        if can.ready == true { return "Hazır · \(can.gear ?? "?")" }
        return "Araç beklemede"
    }
    private func chargeMinutesText(_ minutes: Int) -> String {
        minutes == 0 ? "Tamamlandı" : "\(minutes / 60) sa \(minutes % 60) dk"
    }
    private var chargeDelayText: String {
        "ESP CAN süre bilgisi sağlamıyor"
    }
    private var connectionLabel: String {
        if vehicle.gatewayConnected { return "ESP CAN · Android ağ geçidinden canlı veri" }
        return classicCharge == nil ? "ESP CAN verisi bekleniyor" : "Son şarj ESP kaydı · klasik hesap"
    }
    private var vehicleDataSourceLabel: String {
        activeCan != nil ? "ESP32 CAN · Android ağ geçidi" : classicCharge == nil ? "ESP CAN verisi bekleniyor" : "Şarj sırasında kaydedilen ESP verisi · tahmin"
    }
    private var latestTimestamp: String {
        guard let stamp = activeCan?.timestamp ?? classicCharge?.sourceTimestamp,
              let date = GatewayTimestamp.parse(stamp) else { return "Henüz kayıt yok" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var locationCard: some View {
        Button {
            guard let point = vehicle.lastParkedLocation,
                  let url = URL(string: "http://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "location.fill").foregroundStyle(CitroenTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.lastParkedLocation == nil ? "Araç konumu" : "Aracınızı burada park ettiniz")
                        .font(.caption.bold()).foregroundStyle(CitroenTheme.text)
                    Text(vehicle.lastParkedLocation.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) } ?? "Henüz park kaydı yok")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(vehicle.lastParkedLocation == nil)
    }

    private var parkTimeCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "clock.fill").foregroundStyle(CitroenTheme.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text("Park zamanı").font(.caption.bold())
                Text(vehicle.lastParkedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Henüz park kaydı yok")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chargeEfficiencyCard: some View {
        let summary = chargeEfficiencySummary(for: vehicle.savedTrips)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Enerji verimliliği", systemImage: "bolt.fill")
                    .font(.subheadline.bold()).foregroundStyle(CitroenTheme.text)
                Spacer()
                if let summary {
                    Text(summary.efficiencyLabel)
                        .font(.caption.bold()).foregroundStyle(efficiencyTint(summary.kWhPer100Km))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(efficiencyTint(summary.kWhPer100Km).opacity(0.13), in: Capsule())
                }
            }
            if let summary {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle().stroke(CitroenTheme.brand.opacity(0.16), lineWidth: 7)
                            Circle().trim(from: 0, to: CGFloat(min(1, max(0, summary.kWhPer100Km / 12))))
                                .stroke(efficiencyTint(summary.kWhPer100Km), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "bolt.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(efficiencyTint(summary.kWhPer100Km))
                        }.frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(summary.kWhPer100Km.formatted(.number.precision(.fractionLength(1))))
                                    .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(CitroenTheme.text).monospacedDigit()
                                Text("kWh / 100 km").font(.caption.bold()).foregroundStyle(CitroenTheme.muted)
                            }
                            Text("Daha düşük tüketim, daha verimli sürüş demek")
                                .font(.caption2).foregroundStyle(CitroenTheme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CitroenTheme.divider.opacity(0.6))
                            Capsule().fill(efficiencyTint(summary.kWhPer100Km))
                                .frame(width: max(8, geometry.size.width * min(1, max(0, summary.kWhPer100Km / 12))))
                        }
                    }.frame(height: 6)
                    HStack {
                        Text("Daha verimli")
                        Spacer()
                        Text("Yüksek tüketim")
                    }.font(.system(size: 9, weight: .medium)).foregroundStyle(CitroenTheme.muted)
                }
                HStack(spacing: 9) {
                    efficiencyDetail(icon: "creditcard.fill", value: "\(summary.tlPer100Km.formatted(.number.precision(.fractionLength(0...1)))) TL", title: "100 km tahmini maliyet")
                    efficiencyDetail(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "\(summary.kmPerFullCharge.formatted(.number.precision(.fractionLength(0...1)))) km", title: "Tahmini tam dolu menzil")
                }
                HStack(spacing: 12) {
                    Label("\(summary.tripCount) rota", systemImage: "map")
                    Label("10 km’de %\(summary.percentPer10Km.formatted(.number.precision(.fractionLength(0...1))))", systemImage: "battery.50percent")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(CitroenTheme.muted)
                Text("Araç batarya ölçümlerinden tahmin · maliyet 5 TL/kWh varsayımıyla hesaplanır.")
                    .font(.system(size: 9)).foregroundStyle(CitroenTheme.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "battery.100percent").font(.system(size: 28)).foregroundStyle(CitroenTheme.brand)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("İlk sürüş ölçümü bekleniyor").font(.subheadline.bold()).foregroundStyle(CitroenTheme.text)
                        Text("Tamamlanan bir rotada mesafe ve batarya değişimi kaydedilince verimlilik ve maliyet burada gösterilir.")
                            .font(.caption).foregroundStyle(CitroenTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(red: 0.04, green: 0.20, blue: 0.22), CitroenTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(CitroenTheme.brand.opacity(0.18), lineWidth: 1))
        }
    }

    private func espDriveCard(_ can: AndroidGatewayCANTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VİTES").font(.caption.bold()).foregroundStyle(CitroenTheme.muted)
                    Text(can.gear ?? "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    Text(can.ready == true ? "READY" : "ARAÇ DURUMU").font(.caption).foregroundStyle(CitroenTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(can.batteryPowerKw.map { String(format: "%+.2f kW", $0) } ?? "— kW")
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Batarya güç dengesi").font(.caption).foregroundStyle(CitroenTheme.muted)
                    Text("\(can.batteryPercent.map(String.init) ?? "—")% · \(can.rangeKm.map(String.init) ?? "—") km")
                        .font(.caption.bold()).foregroundStyle(CitroenTheme.brand)
                }
            }
            if let power = can.batteryPowerKw { PowerFlowMeter(powerKw: power) }
            HStack(spacing: 9) {
                infoTile("Sürüş", value: can.sessionTripDistanceKm.map { "\($0.formatted(.number.precision(.fractionLength(1)))) km" } ?? "—", detail: "Bu Android oturumu")
                infoTile("Enerji", value: can.sessionEnergyOutKwh.map { "\($0.formatted(.number.precision(.fractionLength(2)))) kWh" } ?? "—", detail: "Bataryadan çıkış")
            }
            Text("\(gateway.latestIsStale ? "Son alınan ESP verisi" : "ESP CAN canlı") · + çekiş/tüketim adayı · − bataryaya giriş/geri kazanım adayı")
                .font(.caption2).foregroundStyle(CitroenTheme.muted)
        }
        .padding(15)
        .background(LinearGradient(colors: [Color(red: 0.04, green: 0.20, blue: 0.22), CitroenTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }

    private func classicChargeCard(_ estimate: ESPClassicChargeEstimate) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Klasik hesap · son şarj ESP verisi", systemImage: "function")
                .font(.caption.bold()).foregroundStyle(.orange)
            HStack(spacing: 10) {
                infoTile("Batarya", value: "≈ \(Int(estimate.batteryPercent.rounded()))%", detail: "ESP şarj verisinden")
                infoTile("Tahmini menzil", value: "≈ \(Int(estimate.rangeKm.rounded())) km", detail: "Klasik SOC hesabı")
            }
            HStack(spacing: 10) {
                infoTile("Kalan şarj", value: estimate.minutesRemaining.map(chargeMinutesText) ?? "—", detail: estimate.isCharging ? "Süre hesabı" : "Şarj tamamlanmış")
                infoTile("Şarj gücü", value: estimate.lastChargePowerKw.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kW" } ?? "—", detail: "ESP’nin son şarj ölçümü")
            }
            Text("Şarj sırasında kaydedilen ESP batarya yüzdesinden hesaplanır; yeni ESP verisi değildir.")
                .font(.caption2).foregroundStyle(CitroenTheme.muted)
            Text("ESP şarj kaydı: \(estimate.sourceTimestamp)")
                .font(.caption2.monospaced()).foregroundStyle(CitroenTheme.muted)
        }
        .padding(15)
        .background(LinearGradient(colors: [Color(red: 0.22, green: 0.14, blue: 0.04), CitroenTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }

    private func efficiencyTint(_ kWhPer100Km: Double) -> Color {
        kWhPer100Km <= 8.5 ? CitroenTheme.brand : (kWhPer100Km <= 10 ? .orange : CitroenTheme.red)
    }

    private func efficiencyDetail(icon: String, value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.system(size: 9, weight: .medium)).foregroundStyle(CitroenTheme.muted).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(CitroenTheme.brand).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var batteryGauge: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(CitroenTheme.blueGrey.opacity(0.22), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(activeCan?.batteryPercent.map(Double.init) ?? classicCharge?.batteryPercent ?? 0) / 100)
                    .stroke(CitroenTheme.electric, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "battery.100percent").font(.system(size: 17, weight: .semibold)).foregroundStyle(CitroenTheme.text)
            }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                            Text(displayBatteryText).font(.custom("CitroenType-Bold", size: 24)).foregroundStyle(CitroenTheme.brand)
                Text(activeCan == nil ? "Son şarj ESP kaydı · hesap" : "ESP CAN batarya")
                    .font(.caption).foregroundStyle(CitroenTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoTile(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.custom("CitroenType-Bold", size: 17)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var carArtwork: some View {
        if let url = Bundle.main.url(forResource: "topolino-green", withExtension: "png", subdirectory: "assets"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
                .padding(.horizontal, 8)
        } else {
            Image(systemName: "car.side.fill")
                .font(.system(size: 68))
                .foregroundStyle(CitroenTheme.brand)
        }
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(CitroenTheme.brand)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(CitroenTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChargePage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    private var can: AndroidGatewayCANTelemetry? { gateway.liveEspCan }
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }
    private var hasClassicFallback: Bool { classicCharge != nil }
    private var isOffline: Bool {
        can == nil || gateway.latestIsStale || can?.isStale == true
    }
    private var chargeStatus: String {
        if can?.charging == true { return "Şarj oluyor" }
        if can?.charging == false { return "Şarjda değil" }
        if can?.ready == true { return "Araç hazır" }
        if let classicCharge { return classicCharge.isCharging ? "Son ESP şarj verisinden hesaplanıyor" : "Son şarj ESP kaydı" }
        return "ESP şarj verisi bekleniyor"
    }
    private var displayedChargeTime: String {
        guard let minutes = can?.chargeMinutesRemaining ?? classicCharge?.minutesRemaining else { return "—" }
        return minutes == 0 ? "Tamamlandı" : "\(minutes / 60) sa \(minutes % 60) dk"
    }
    private var displayedSOC: Double? { can?.batteryPercent.map(Double.init) ?? classicCharge?.batteryPercent }
    private var displayedRange: Double? { can?.rangeKm.map(Double.init) ?? classicCharge?.rangeKm }
    var body: some View {
        TestPage(title: "Şarj", subtitle: "Batarya durumunu ve şarj tahminini takip edin") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                        Circle().trim(from: 0, to: CGFloat(min(100, max(0, displayedSOC ?? 0)) / 100))
                            .stroke(AngularGradient(colors: [CitroenTheme.brand, Color(hex: 0x8DF5D5)], center: .center),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(CitroenTheme.brand)
                            Text(displayedSOC.map { "\(Int($0.rounded()))%" } ?? "—%")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                            Text(can == nil ? "SON ŞARJ" : "ESP CAN")
                                .font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(CitroenTheme.muted)
                        }
                    }.frame(width: 108, height: 108)
                    VStack(alignment: .leading, spacing: 13) {
                        Label(can == nil ? (hasClassicFallback ? "Son şarj ESP verisinden hesap" : "ESP verisi bekleniyor") : "ESP CAN canlı", systemImage: isOffline ? "clock" : "dot.radiowaves.left.and.right")
                            .font(.caption.bold()).foregroundStyle(isOffline ? Color.orange : CitroenTheme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayedRange.map { "≈ \(Int($0.rounded())) km" } ?? "Menzil bekleniyor").font(.title3.bold())
                            Text("Tahmini kalan menzil").font(.caption).foregroundStyle(CitroenTheme.muted)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayedChargeTime).font(.subheadline.bold())
                            Text("Doluma kalan süre").font(.caption).foregroundStyle(CitroenTheme.muted)
                        }
                    }
                }
                ProgressView(value: min(100, max(0, displayedSOC ?? 0)), total: 100).tint(CitroenTheme.brand)
                HStack(spacing: 8) {
                    Image(systemName: can?.charging == true ? "powerplug.fill" : "battery.0percent")
                    Text(chargeStatus).font(.subheadline.weight(.semibold))
                    Spacer()
                    if isOffline && hasClassicFallback {
                        Text("TAHMİN").font(.caption2.bold()).tracking(1).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.1), in: Capsule())
                    }
                }.foregroundStyle(CitroenTheme.brand)
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color(hex: 0x073D3A), CitroenTheme.surface, Color(hex: 0x101A31)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "bolt.fill").font(.system(size: 100, weight: .black)).rotationEffect(.degrees(14))
                            .foregroundStyle(.white.opacity(0.035)).padding(10)
                    }
            }

            TestCard(title: "Durum güncellemesi") {
                HStack(spacing: 10) {
                    Image(systemName: isOffline ? "clock.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isOffline ? .orange : CitroenTheme.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(can == nil ? (hasClassicFallback ? "Son şarj sırasında kaydedilen ESP verisi kullanılıyor" : "ESP CAN verisi bekleniyor") : "Araçtan güncel ESP bilgisi alınıyor")
                            .font(.subheadline.bold()).foregroundStyle(CitroenTheme.text)
                        Text(can.flatMap { GatewayTimestamp.parse($0.timestamp) }?.formatted(date: .abbreviated, time: .shortened)
                            ?? classicCharge?.sourceTimestamp ?? "Henüz araç verisi alınmadı")
                            .font(.caption).foregroundStyle(CitroenTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                if let can, let power = can.chargePowerKw {
                    valueRow("Anlık şarj gücü", value: "\(power.formatted(.number.precision(.fractionLength(1)))) kW")
                }
                if can == nil, let power = classicCharge?.lastChargePowerKw {
                    valueRow("Şarj sırasında son ESP gücü", value: "\(power.formatted(.number.precision(.fractionLength(1)))) kW")
                }
                if isOffline, hasClassicFallback {
                    Text("ESP canlı değil. Batarya yüzdesi ve kalan süre son şarj ESP örneğinden; menzil klasik SOC formülünden hesaplanıyor.")
                        .font(.caption).foregroundStyle(CitroenTheme.muted)
                }
            }
            TestCard(title: "Şarj geçmişi") {
                if vehicle.chargeSessions.isEmpty {
                    Text("Şarj geçmişin burada görünecek. Araçtan yeterli şarj bilgisi alındığında başlangıç ve bitiş saatleri kaydedilir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(vehicle.chargeSessions.prefix(12)) { session in
                        let sessionIsFresh = session.endedAt == nil &&
                            vehicle.estimateNow.timeIntervalSince(session.lastObservedAt) <= 30
                        let sessionIsEstimated = false
                        let sessionDisplayedEndBattery = session.endBatteryPercent
                        let sessionDisplayedGain: Double? = {
                            guard let start = session.startBatteryPercent,
                                  let end = sessionDisplayedEndBattery else { return nil }
                            return max(0, end - start)
                        }()
                        let sessionIcon = session.endedAt == nil && sessionIsFresh ? "bolt.fill" : "battery.100percent"
                        let sessionTitle: String = {
                            if session.endedAt == nil { return sessionIsFresh ? "Şarj oturumu sürüyor" : "Son şarj kaydı" }
                            return session.endReason ?? "Şarj oturumu sona erdi"
                        }()
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Image(systemName: sessionIcon)
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(CitroenTheme.brand)
                                    .frame(width: 34, height: 34).background(CitroenTheme.brand.opacity(0.13), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sessionTitle).font(.subheadline.bold())
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(chargeSessionDuration(session, now: vehicle.estimateNow, estimatedCompletionAt: nil)).font(.caption.bold()).foregroundStyle(CitroenTheme.brand)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(CitroenTheme.brand.opacity(0.12), in: Capsule())
                            }
                            HStack(spacing: 0) {
                                chargeTimelinePoint(title: "Takıldı", date: session.startedAt, icon: "powerplug.fill", trailing: false)
                                Rectangle().fill(CitroenTheme.brand.opacity(session.endedAt == nil && sessionIsFresh ? 0.35 : 0.75))
                                    .frame(height: 2).frame(maxWidth: .infinity).padding(.horizontal, 8)
                                if let endedAt = session.endedAt {
                                    let endLabel = session.endReason == "Şarj tamamlandı" ? "Doldu" : "Bitti"
                                    chargeTimelinePoint(title: endLabel, date: endedAt, icon: "checkmark", trailing: true)
                                } else {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Label(sessionIsFresh ? "Devam ediyor" : "Son gözlem", systemImage: "clock")
                                            .font(.caption.bold()).foregroundStyle(sessionIsFresh ? .orange : CitroenTheme.muted)
                                        Text(sessionIsFresh ? "Araçtan veri geliyor" : "Güncel durum doğrulanmıyor")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            HStack(spacing: 6) {
                                Text(session.startBatteryPercent.map { "%\(Int($0.rounded()))" } ?? "—")
                                Image(systemName: "arrow.right").font(.caption2)
                                Text(sessionDisplayedEndBattery.map { "\(sessionIsEstimated ? "≈" : "")%\(Int($0.rounded()))" } ?? "—")
                                Text("batarya").foregroundStyle(.secondary)
                                if sessionIsEstimated {
                                    Text("tahmini").foregroundStyle(.orange)
                                }
                                Spacer()
                                if let start = session.startBatteryPercent,
                                   let end = sessionDisplayedEndBattery, end >= start {
                                    let addedRange = estimatedRange(for: end) - estimatedRange(for: start)
                                    Text("+\(addedRange.formatted(.number.precision(.fractionLength(0...1)))) km menzil")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Menzil artışı bekleniyor").foregroundStyle(.secondary)
                                }
                            }.font(.caption)
                            ProgressView(value: min(100, max(0, sessionDisplayedEndBattery ?? session.startBatteryPercent ?? 0)), total: 100)
                                .tint(CitroenTheme.brand)
                            HStack {
                                Label(sessionDisplayedGain.map { "\(sessionIsEstimated ? "≈" : "+")\(Int($0.rounded()))% batarya artışı\(sessionIsEstimated ? " · tahmini" : "")" } ?? "Batarya artışı ölçülemedi", systemImage: "arrow.up.right")
                                Spacer()
                            }.font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            if session.id != vehicle.chargeSessions.prefix(12).last?.id { Divider() }
                        }
                        .padding(13)
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(LinearGradient(colors: [CitroenTheme.brand.opacity(0.09), CitroenTheme.softSurface], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(CitroenTheme.brand.opacity(0.14), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }
}

private struct AlertsPage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    private var can: AndroidGatewayCANTelemetry? { gateway.latestEspCan }
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }
    private var isStale: Bool { can == nil || gateway.latestIsStale || can?.isStale == true }
    private var checks: [(String, String, String)] {
        guard let can, can.canLive != false else { return [] }
        return [
            ("READY", can.ready.map { $0 ? "Hazır" : "Hazır değil" } ?? "Veri yok", "bolt.circle"),
            ("Park freni", can.handbrake.map { $0 ? "Çekili" : "İndirilmiş" } ?? "Veri yok", "parkingsign.circle"),
            ("Çekiş gerilimi", can.voltageV.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "Veri yok", "bolt.fill"),
            ("Sıcaklık 1", can.temperature1C.map { "\($0) °C" } ?? "Veri yok", "thermometer.medium"),
            ("Sıcaklık 2", can.temperature2C.map { "\($0) °C" } ?? "Veri yok", "thermometer.medium")
        ]
    }
    var body: some View {
        TestPage(title: "Araç durumları", subtitle: "ESP CAN üzerinden gelen anlık durum alanları") {
            TestCard(title: "Bağlantı") {
                Label(isStale ? "Son ESP kaydı gösteriliyor" : "ESP CAN canlı", systemImage: isStale ? "clock" : "checkmark.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(isStale ? .orange : CitroenTheme.brand)
                Text(gateway.status).font(.caption).foregroundStyle(.secondary)
                if let can { valueRow("Son paket", value: GatewayTimestamp.parse(can.timestamp)?.formatted(date: .abbreviated, time: .shortened) ?? can.timestamp) }
            }
            TestCard(title: "ESP durum alanları") {
                if checks.isEmpty {
                    if let classicCharge {
                        valueRow("Son şarj ESP kaydı", value: classicCharge.sourceTimestamp)
                        valueRow("Batarya", value: "≈ \(Int(classicCharge.batteryPercent.rounded()))%")
                        valueRow("Tahmini menzil", value: "≈ \(Int(classicCharge.rangeKm.rounded())) km")
                        Text("ESP canlı değil; bu, son şarj ESP örneğinden hesaplanan tahmindir. Üretici arıza kodu değildir.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("ESP CAN durumu ve yerel klasik kayıt bekleniyor. Firmware arıza kodu göndermiyorsa burada gerçek arıza uyarısı üretilemez.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(checks.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Image(systemName: item.2).foregroundStyle(CitroenTheme.brand).frame(width: 24)
                            Text(item.0).font(.subheadline)
                            Spacer()
                            Text(item.1).font(.subheadline.bold()).foregroundStyle(CitroenTheme.text)
                        }
                        .padding(12).background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            TestCard(title: "Uyarı verisinin sınırı") {
                Text("Bu aktarımda üretici arıza kodları veya gerçek arıza bayrakları yok. READY, park freni, gerilim ve sıcaklık bilgilerini arıza uyarısı gibi göstermiyoruz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ServicePage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }
    private var odometer: Double? { gateway.liveEspCan?.odometerKm ?? classicCharge?.odometerKm }
    private var remaining: Double? {
        odometer.map { value in let r = value.truncatingRemainder(dividingBy: 20_000); return r < 0.05 ? 0 : 20_000 - r }
    }
    var body: some View {
        TestPage(title: "Servis ve bakım", subtitle: "ESP CAN kilometre verisine göre yerel bakım hatırlatması") {
            TestCard(title: "Bakım eşiği · 20.000 km") {
                valueRow("Kilometre", value: odometer.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km\(gateway.liveEspCan == nil && classicCharge != nil ? " · son şarj ESP kaydı" : "")" } ?? "ESP verisi bekleniyor")
                valueRow("Kalan", value: remaining.map { $0 == 0 ? "Bakım zamanı" : "\(Int($0)) km" } ?? "—")
                Text("Bu, MyFiat sunucu bakım planı değildir; son ESP CAN kilometresine göre yerel hatırlatmadır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Servis ve bakım")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MorePage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    var body: some View {
        NavigationStack {
            List {
                Section("Araç") {
                    NavigationLink { VehicleInfoPage(vehicle: vehicle, gateway: gateway) } label: { Label("Aracım", systemImage: "car.side") }
                    NavigationLink { ParkedLocationPage(vehicle: vehicle) } label: { Label("Son park konumu", systemImage: "location") }
                    NavigationLink { AndroidGatewaySettingsPage(client: gateway, vehicle: vehicle) } label: {
                        Label("Android araç telefonu", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                Section("Bakım ve destek") {
                    NavigationLink { ServicePage(vehicle: vehicle, gateway: gateway) } label: { Label("Servis ve bakım", systemImage: "wrench.and.screwdriver") }
                }
                Section("Kayıtlar ve tanılama") {
                    NavigationLink { TripsPage(vehicle: vehicle) } label: { Label("Yolculuklar ve rotalar · \(vehicle.savedTrips.count)", systemImage: "map") }
                    NavigationLink { CANPage(gateway: gateway, vehicle: vehicle) } label: { Label("CAN verileri · ESP", systemImage: "waveform.path.ecg") }
                    NavigationLink { DebugPage(vehicle: vehicle, gateway: gateway) } label: { Label("ESP tanılama · CAN çerçeveleri", systemImage: "ant +") }
                }
                Section("Yardım") {
                    Link(destination: URL(string: "tel:4442255")!) { Label("Fiat yol yardım · 444 22 55", systemImage: "phone.fill") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CitroenTheme.canvas)
            .navigationTitle("Diğer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AndroidGatewaySettingsPage: View {
    @ObservedObject var client: AndroidGatewayClient
    @ObservedObject var vehicle: VehicleStore
    @State private var endpoint: String
    @State private var accessKey: String
    @State private var formError: String?

    init(client: AndroidGatewayClient, vehicle: VehicleStore) {
        self.client = client
        self.vehicle = vehicle
        _endpoint = State(initialValue: client.endpoint)
        _accessKey = State(initialValue: client.accessKey)
    }

    var body: some View {
        Form {
            Section("Cloudflare internet rölesi") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Röle adresi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(endpoint)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                SecureField("Android API erişim anahtarı", text: $accessKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Kaydet ve bağlan") {
                    if let error = client.save(accessKey: accessKey) {
                        formError = error
                    } else {
                        formError = nil
                        client.setEnabled(true, vehicle: vehicle)
                    }
                }
                if let formError {
                    Text(formError).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Android verisini kullan", isOn: Binding(
                    get: { client.isEnabled },
                    set: { client.setEnabled($0, vehicle: vehicle) }
                ))
                .disabled(client.endpoint.isEmpty || client.accessKey.isEmpty)
            }

            Section("Araç verisi") {
                Label("ESP32 CAN → Android BLE → iOS rölesi", systemImage: "point.3.connected.trianglepath.dotted")
                Text("Araç göstergeleri ESP32 CAN verisini Android ağ geçidinden alır.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Bağlantı durumu") {
                let hasFreshVehicleData = client.isReachable && client.latestEspCan != nil &&
                    !client.latestIsStale
                Label(
                    hasFreshVehicleData ? "ESP CAN · Android’den canlı veri alınıyor" :
                        (client.latestEspCan != nil ? "ESP CAN · son bilinen veri" :
                            (client.isReachable ? "Röleye ulaşılıyor · ESP verisi bekleniyor" : "Android rölesi bekleniyor")),
                    systemImage: hasFreshVehicleData ? "checkmark.circle.fill" :
                        (client.latestEspCan != nil ? "clock.arrow.circlepath" : "antenna.radiowaves.left.and.right")
                )
                .foregroundStyle(client.latestIsStale ? Color.orange :
                    (hasFreshVehicleData ? Color.mint : Color.secondary))
                Text(client.status).font(.caption).foregroundStyle(.secondary)
                if let lastFetchAt = client.lastFetchAt {
                    LabeledContent("Son istek", value: lastFetchAt.formatted(date: .omitted, time: .shortened))
                }
                if let can = client.latestEspCan {
                    if can.canLive != false {
                        LabeledContent("Vites", value: can.gear ?? "—")
                        LabeledContent("Batarya", value: can.batteryPercent.map { "\($0)%" } ?? "—")
                        LabeledContent("Kalan menzil", value: can.rangeKm.map { "\($0) km" } ?? "—")
                        LabeledContent("Kilometre", value: can.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "—")
                    }
                    LabeledContent("Şarj", value: can.charging.map { $0 ? "Şarj oluyor" : "Şarjda değil" } ?? "—")
                    LabeledContent("Doluma kalan", value: can.chargeMinutesRemaining.map { "\($0 / 60) sa \($0 % 60) dk" } ?? "—")
                    LabeledContent("Paket zamanı", value: GatewayTimestamp.parse(can.timestamp)?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                }
                Button("Şimdi yenile") { client.fetchNow(vehicle: vehicle) }
                    .disabled(!client.isEnabled)
            }


            Section("Veri kullanımı") {
                Text("Android, en son gerçek araç paketini internetteki röleye kaydeder. Yeni paket gelmezse iPhone son bilinen değeri gösterir ve eski veriyi canlı diye işaretlemez. Test HEX’leri ayrı bölümde kalır.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Android telefon ESP32’den yeni CAN verisi aldığında bu röleye gönderir; araç çevrimdışıyken son alınan değerler saklanır. Röle adresi otomatik doldurulur. Android’deki erişim anahtarını bir kez girip kaydet; iki telefon farklı internet ağlarında olabilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CitroenTheme.canvas)
        .navigationTitle("Android ağ geçidi")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

private struct CANPage: View {
    @ObservedObject var gateway: AndroidGatewayClient
    @ObservedObject var vehicle: VehicleStore

    var body: some View {
        TestPage(title: "CAN verileri", subtitle: "ESP CAN · Android araç telefonundan canlı aktarım") {
            TestCard(title: "ESP CAN · tüm araç verileri") {
                HStack(spacing: 8) {
                    Image(systemName: vehicle.gatewayConnected ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(vehicle.gatewayConnected ? CitroenTheme.brand : CitroenTheme.mutedLight)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.gatewayConnected ? "Android ağ geçidi bağlı" : gateway.isEnabled ? "Android rölesinden veri bekleniyor" : "Android ağ geçidi kapalı")
                            .font(.subheadline.bold())
                        Text(gateway.status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !gateway.isEnabled {
                    Button { gateway.setEnabled(true, vehicle: vehicle) } label: {
                        Label("ESP CAN veri bağlantısını etkinleştir", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gateway.accessKey.isEmpty)
                    if gateway.accessKey.isEmpty {
                        NavigationLink {
                            AndroidGatewaySettingsPage(client: gateway, vehicle: vehicle)
                        } label: {
                            Label("Android erişim anahtarını ayarla", systemImage: "key.horizontal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let can = gateway.liveEspCan {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VİTES").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(can.gear ?? "—")
                                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            Text(can.ready == true ? "READY" : "ARAÇ DURUMU").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(can.batteryPercent.map { "\($0)%" } ?? "—%")
                                .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(CitroenTheme.brand)
                            Text(can.rangeKm.map { "\($0) km menzil" } ?? "Menzil —")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(13)
                    .background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 9)], spacing: 9) {
                        if can.canLive != false {
                            canCard("Vites", value: can.gear ?? "—")
                            canCard("READY", value: can.ready.map { $0 ? "Evet" : "Hayır" } ?? "—")
                            canCard("El freni", value: can.handbrake.map { $0 ? "Çekili" : "İndirilmiş" } ?? "—")
                            canCard("Batarya", value: can.batteryPercent.map { "\($0)%" } ?? "—")
                            canCard("Kalan menzil", value: can.rangeKm.map { "\($0) km" } ?? "—")
                            canCard("Kilometre sayacı", value: can.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "—")
                            canCard("Çekiş gerilimi", value: can.voltageV.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "—")
                            canCard("Çekiş akımı", value: can.currentA.map { "\($0.formatted(.number.precision(.fractionLength(1)))) A" } ?? "—")
                            canCard("12 V akü", value: can.battery12V.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "—")
                            canCard("Sıcaklık 1", value: can.temperature1C.map { "\($0) °C" } ?? "—")
                            canCard("Sıcaklık 2", value: can.temperature2C.map { "\($0) °C" } ?? "—")
                        }
                        canCard("Şarj durumu", value: can.charging.map { $0 ? "Şarj oluyor" : "Şarjda değil" } ?? "—")
                        canCard("Şarj süresi", value: can.chargeMinutesRemaining.map(chargeMinutesText) ?? "—")
                        canCard("Şarj gücü", value: can.chargePowerKw.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kW" } ?? "—")
                        canCard("Batarya akışı · işaret adayı", value: can.batteryPowerKw.map { "\($0.formatted(.number.precision(.fractionLength(2)))) kW" } ?? "—")
                        if can.canLive != false, let power = can.batteryPowerKw {
                            PowerFlowMeter(powerKw: power)
                        }
                    }
                    if can.canLive != false {
                        TestCard(title: "Sürüş oturumu ve enerji") {
                            valueRow("Sürüş mesafesi", value: can.sessionTripDistanceKm.map { "\($0.formatted(.number.precision(.fractionLength(2)))) km" } ?? "—")
                            valueRow("Tahmini sürüş enerjisi", value: can.sessionEstimatedDriveEnergyKwh.map { "\($0.formatted(.number.precision(.fractionLength(3)))) kWh" } ?? "—")
                            valueRow("Tahmini tüketim", value: can.sessionEstimatedConsumptionKwhPer100Km.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kWh/100 km" } ?? "—")
                            valueRow("Enerji çıkışı / bataryaya giriş", value: "\(can.sessionEnergyOutKwh?.formatted(.number.precision(.fractionLength(3))) ?? "—") / \(can.sessionEnergyInKwh?.formatted(.number.precision(.fractionLength(3))) ?? "—") kWh")
                            valueRow("Geri kazanım adayı", value: can.sessionRegenCandidateKwh.map { "\($0.formatted(.number.precision(.fractionLength(3)))) kWh" } ?? "—")
                            Text("Güç işareti: + çekiş/tüketim adayı · − bataryaya giriş/geri kazanım adayı. Bu batarya gücüdür; motor çıkış gücü değildir.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TestCard(title: "Canlı CAN çerçeveleri · son \(can.canFrames?.count ?? 0)") {
                        valueRow("Toplam alınan", value: can.canFrameCount.map(String.init) ?? "—")
                        valueRow("ESP çerçeve kanalı", value: can.gattFrameStatus ?? "Durum bilgisi yok")
                        if let frames = can.canFrames, !frames.isEmpty {
                            ForEach(frames) { frame in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(frame.id).font(.caption.bold().monospaced())
                                    Text("DLC \(frame.dlc)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    Text(frame.data).font(.caption.monospaced()).textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            Text("Ham CAN çerçeveleri için ESP’de güncel FDE1/FDE2 BLE firmware’i çalışmalı.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    valueRow("Son CAN paketi", value: GatewayTimestamp.parse(can.timestamp)?.formatted(date: .abbreviated, time: .standard) ?? can.timestamp)
                    valueRow("Veri kaynağı", value: "ESP32 CAN · Android ağ geçidi")
                    valueRow("Paket durumu", value: can.isStale == true || gateway.latestIsStale ? "Son bilinen veri · yeni paket bekleniyor" : "Güncel")
                } else if let classicCharge = gateway.classicChargeEstimate(at: vehicle.estimateNow) {
                    TestCard(title: "Klasik hesap · son şarj ESP kaydı") {
                        valueRow("Şarj ESP örneği", value: classicCharge.sourceTimestamp)
                        valueRow("Batarya", value: "≈ \(Int(classicCharge.batteryPercent.rounded()))%")
                        valueRow("Tahmini menzil", value: "≈ \(Int(classicCharge.rangeKm.rounded())) km")
                        valueRow("Kalan şarj", value: classicCharge.minutesRemaining.map(chargeMinutesText) ?? "—")
                        valueRow("Şarj sırasında son güç", value: classicCharge.lastChargePowerKw.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kW" } ?? "—")
                        valueRow("Paket gerilimi", value: classicCharge.voltageV.map { "\($0.formatted(.number.precision(.fractionLength(1)))) V" } ?? "—")
                        valueRow("Paket akımı", value: classicCharge.currentA.map { "\($0.formatted(.number.precision(.fractionLength(1)))) A" } ?? "—")
                        valueRow("Kilometre", value: classicCharge.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "—")
                        Text("ESP canlı değil. Batarya yüzdesi ve menzil son şarj örneğinden, klasik menzil formülüyle hesaplandı.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("ESP CAN verisi henüz gelmedi ve klasik yerel kayıt bulunamadı. Android araç telefonunda ağ geçidini başlat; kayıtlı sürüş verisi geldikçe klasik hesap da kullanılabilir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let temperature = gateway.latestTemperature {
                    valueRow("Ortam sıcaklığı", value: "\(temperature.celsius.formatted(.number.precision(.fractionLength(1)))) °C · \(temperature.isStale == true ? "son ölçüm" : "canlı")")
                }
            }
        }
        .navigationTitle("CAN verileri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func canCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(CitroenTheme.brandBright).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chargeMinutesText(_ minutes: Int) -> String {
        minutes == 0 ? "Tamamlandı" : "\(minutes / 60) sa \(minutes % 60) dk"
    }

}

private struct DebugPage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    private var can: AndroidGatewayCANTelemetry? { gateway.latestEspCan }
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }
    var body: some View {
        TestPage(title: "ESP tanılama", subtitle: "Android ağ geçidi, canlı CAN alanları ve ham çerçeveler") {
            TestCard(title: "Bağlantı") {
                valueRow("Ağ geçidi", value: gateway.status)
                valueRow("Röle", value: gateway.isReachable ? "Erişilebilir" : "Erişilemiyor")
                valueRow("ESP CAN", value: can == nil ? "Veri yok" : (gateway.latestIsStale ? "Son kayıt" : "Canlı"))
                valueRow("Son istek", value: gateway.lastFetchAt?.formatted(date: .omitted, time: .standard) ?? "—")
                valueRow("CAN zaman damgası", value: can?.timestamp ?? "—")
            }
            if can == nil, let classicCharge {
                TestCard(title: "Son şarj ESP örneği · klasik hesap") {
                    valueRow("Örnek zamanı", value: classicCharge.sourceTimestamp)
                    valueRow("Batarya", value: "≈ \(Int(classicCharge.batteryPercent.rounded()))%")
                    valueRow("Klasik menzil", value: "≈ \(Int(classicCharge.rangeKm.rounded())) km")
                    valueRow("Tahmini süre", value: classicCharge.minutesRemaining.map { $0 == 0 ? "Tamamlandı" : "\($0 / 60) sa \($0 % 60) dk" } ?? "—")
                    valueRow("Örnek gerilim / akım", value: "\(classicCharge.voltageV?.formatted(.number.precision(.fractionLength(1))) ?? "—") V / \(classicCharge.currentA?.formatted(.number.precision(.fractionLength(1))) ?? "—") A")
                }
            }
            TestCard(title: "Ham CAN") {
                valueRow("Toplam çerçeve", value: can?.canFrameCount.map(String.init) ?? "—")
                valueRow("Çerçeve kanalı", value: can?.gattFrameStatus ?? "—")
                if let frames = can?.canFrames, !frames.isEmpty {
                    ForEach(frames) { frame in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(frame.id).font(.caption.bold().monospaced())
                                Text("DLC \(frame.dlc)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                if frame.extended == true { Text("EXT").font(.caption2.bold()).foregroundStyle(CitroenTheme.brand) }
                                Spacer()
                                Text(frame.timestamp ?? "").font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(frame.data).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                } else {
                    Text("Ham çerçeve yok. ESP firmware’inin FDE1/FDE2 çerçeve yayınını açtığını doğrula.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ParkedLocationPage: View {
    @ObservedObject var vehicle: VehicleStore
    var body: some View {
        TestPage(title: "Araç konumu", subtitle: "Son park noktası telefonun GPS’inden kaydedilir") {
            TestCard(title: "Son park") {
                if let point = vehicle.lastParkedLocation {
                    valueRow("Koordinat", value: String(format: "%.5f, %.5f", point.latitude, point.longitude))
                    valueRow("GPS doğruluğu", value: "±\(Int(point.horizontalAccuracyMeters.rounded())) m")
                    valueRow("Park zamanı", value: vehicle.lastParkedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    TripRoutePreview(points: [point])
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topLeading) {
                            Label("Son park noktası", systemImage: "mappin.and.ellipse")
                                .font(.caption.bold()).padding(8)
                                .background(.ultraThinMaterial, in: Capsule()).padding(10)
                        }
                    if let url = URL(string: "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                        Link(destination: url) {
                            Label("Harita’da yol tarifi al", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                                .background(CitroenTheme.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    Text("Park noktası henüz yok. Araç durduğunda GPS izni açıksa kaydedilir.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Araç konumu")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TripsPage: View {
    @ObservedObject var vehicle: VehicleStore
    @State private var tripToDelete: VehicleTrip?
    private var trips: [VehicleTrip] { vehicle.savedTrips.sorted { $0.startedAt > $1.startedAt } }
    private var totalDistance: Double {
        trips.compactMap(tripDistanceValue).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Yolculukların").font(.custom("CitroenType-Bold", size: 26)).foregroundStyle(CitroenTheme.text)
                    Text("Sürüşlerin ve rotaların burada saklanır.").font(.subheadline).foregroundStyle(CitroenTheme.muted)
                }
                HStack(spacing: 10) {
                    routeOverviewMetric(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "\(trips.count)", title: "Kayıtlı yolculuk")
                    routeOverviewMetric(icon: "map.fill", value: totalDistance > 0 ? "\(totalDistance.formatted(.number.precision(.fractionLength(0...1)))) km" : "—", title: "Toplam mesafe")
                }
                if trips.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "map.circle.fill").font(.system(size: 52)).foregroundStyle(CitroenTheme.brand)
                        Text("İlk rotan burada görünecek").font(.headline).foregroundStyle(CitroenTheme.text)
                        Text("Bluetooth ve konum açıkken araçla yapılan sürüşler otomatik kaydedilir. Yolculuk bitince rota ve sürüş özeti burada görünür.")
                            .font(.subheadline).foregroundStyle(CitroenTheme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(22)
                    .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    ForEach(trips) { trip in
                        tripCard(trip)
                    }
                }
            }
            .padding(18)
        }
        .background(CitroenTheme.canvas)
        .navigationTitle("Yolculuklar")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Yolculuk silinsin mi?", isPresented: Binding(
            get: { tripToDelete != nil },
            set: { if !$0 { tripToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Yolculuğu sil", role: .destructive) {
                if let tripToDelete { vehicle.deleteSavedTrip(id: tripToDelete.id) }
                tripToDelete = nil
            }
            Button("Vazgeç", role: .cancel) { tripToDelete = nil }
        } message: {
            Text("Bu yolculuğun rota ve ölçüm bilgileri bu telefondan kaldırılır.")
        }
    }

    private func routeOverviewMetric(icon: String, value: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(CitroenTheme.brand)
                .frame(width: 38, height: 38).background(CitroenTheme.brand.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(CitroenTheme.text).lineLimit(1).minimumScaleFactor(0.75)
                Text(title).font(.caption2).foregroundStyle(CitroenTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tripCard(_ trip: VehicleTrip) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.subheadline.bold()).foregroundStyle(CitroenTheme.text)
                    Text(trip.endedAt.map { "Bitti · \($0.formatted(date: .omitted, time: .shortened))" } ?? "Yolculuk devam ediyor")
                        .font(.caption).foregroundStyle(CitroenTheme.muted)
                }
                Spacer()
                Button {
                    tripToDelete = trip
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CitroenTheme.muted)
                        .frame(width: 34, height: 34)
                        .background(CitroenTheme.softSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bu yolculuğu sil")
                Label(trip.endedAt == nil ? "Devam ediyor" : "Tamamlandı", systemImage: trip.endedAt == nil ? "car.side" : "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(CitroenTheme.brand)
                    .padding(.horizontal, 9).padding(.vertical, 6).background(CitroenTheme.brand.opacity(0.12), in: Capsule())
            }
            if let first = trip.points.first, let last = trip.points.last {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Başlangıç", systemImage: "circle.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(CitroenTheme.muted)
                        Text(coordinateText(first)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(CitroenTheme.text).lineLimit(1).minimumScaleFactor(0.75)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(CitroenTheme.brand)
                    VStack(alignment: .trailing, spacing: 3) {
                        Label("Varış", systemImage: "mappin.and.ellipse").font(.system(size: 9, weight: .semibold)).foregroundStyle(CitroenTheme.muted)
                        Text(coordinateText(last)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(CitroenTheme.text).lineLimit(1).minimumScaleFactor(0.75)
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                }
                TripRoutePreview(points: trip.points)
                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                    if trip.points.count > 1,
                       let url = URL(string: "https://maps.apple.com/?saddr=\(first.latitude),\(first.longitude)&daddr=\(last.latitude),\(last.longitude)") {
                        Link(destination: url) {
                            Label("Rotayı haritada aç", systemImage: "arrow.up.right.square.fill")
                                .font(.caption.bold()).frame(maxWidth: .infinity).padding(11)
                                .background(CitroenTheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }.tint(CitroenTheme.brand)
                    }
            } else {
                Label("Bu yolculukta konum kaydı alınmamış.", systemImage: "location.slash")
                    .font(.caption).foregroundStyle(CitroenTheme.muted)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            TripStatsGrid(trip: trip)
            TripBatteryBars(start: trip.startBatteryPercent, end: trip.endBatteryPercent)
        }
        .padding(15).background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.23), CitroenTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(CitroenTheme.brand.opacity(0.12), lineWidth: 1))
        }
    }
}

private func tripDistanceValue(_ trip: VehicleTrip) -> Double? {
    if let start = trip.startOdometerKm, let end = trip.endOdometerKm, end > start { return end - start }
    let gps = tripDistanceKm(trip.points)
    return gps > 0 ? gps : nil
}

private struct TripStatsGrid: View {
    let trip: VehicleTrip
    private var odometerDistance: Double? {
        guard let start = trip.startOdometerKm, let end = trip.endOdometerKm, end >= start else { return nil }
        return end - start
    }
    private var distance: Double? {
        if let odometerDistance, odometerDistance > 0 { return odometerDistance }
        let gps = tripDistanceKm(trip.points)
        return gps > 0 ? gps : nil
    }
    private var batteryUsed: Double? {
        guard let start = trip.startBatteryPercent, let end = trip.endBatteryPercent,
              start > end, start <= 100, end >= 0 else { return nil }
        return start - end
    }
    private var energyUsedKWh: Double? {
        guard let batteryUsed else { return nil }
        return batteryUsed / 100 * topolinoBatteryCapacityKWh
    }
    private var routeCostTL: Double? {
        energyUsedKWh.map { $0 * homeElectricityPricePerKWh }
    }
    private var costPer100Km: Double? {
        guard let distance, distance > 0, let routeCostTL else { return nil }
        return routeCostTL / distance * 100
    }
    private var efficiencyLabel: String? {
        guard let distance, distance > 0, let energyUsedKWh else { return nil }
        return efficiencyRating(energyUsedKWh / distance * 100)
    }
    private func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
            stat("Başlangıç", value: number(trip.startOdometerKm), unit: "km sayacı")
            stat("Bitiş", value: number(trip.endOdometerKm), unit: "km sayacı")
            stat("Mesafe", value: number(distance), unit: "km")
            stat("İlk batarya", value: trip.startBatteryPercent.map { "%\(Int($0.rounded()))" } ?? "—", unit: "")
            stat("Son batarya", value: trip.endBatteryPercent.map { "%\(Int($0.rounded()))" } ?? "—", unit: "")
            stat("Süre", value: tripDuration(trip), unit: "")
            stat("Enerji tüketimi", value: number(energyUsedKWh), unit: energyUsedKWh == nil ? "Batarya verisi yok" : "kWh · tahmini")
            stat("Yolculuk maliyeti", value: routeCostTL.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) TL" } ?? "—", unit: "tahmini")
            stat("100 km maliyeti", value: costPer100Km.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) TL" } ?? "—", unit: efficiencyLabel ?? "Ölçüm bekleniyor")
        }
        .accessibilityElement(children: .contain)
    }
    private func stat(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(CitroenTheme.muted).lineLimit(1).minimumScaleFactor(0.72)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(CitroenTheme.text).lineLimit(1).minimumScaleFactor(0.7)
            if !unit.isEmpty { Text(unit).font(.system(size: 9, weight: .medium)).foregroundStyle(CitroenTheme.muted).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(CitroenTheme.softSurface, in: RoundedRectangle(cornerRadius: 10))
    }
}

private func coordinateText(_ point: TripLocationPoint) -> String {
    String(format: "%.5f, %.5f", point.latitude, point.longitude)
}

private func tripDuration(_ trip: VehicleTrip) -> String {
    let seconds = max(0, (trip.endedAt ?? .now).timeIntervalSince(trip.startedAt))
    let minutes = Int(seconds / 60)
    let hours = minutes / 60
    return hours > 0 ? "\(hours) sa \(minutes % 60) dk" : "\(minutes) dk"
}

private func chargeSessionDuration(_ session: ChargeSession, now: Date = .now,
                                  estimatedCompletionAt: Date? = nil) -> String {
    let isFresh = now.timeIntervalSince(session.lastObservedAt) <= 30
    let activeEnd = estimatedCompletionAt.map { min(now, $0) } ?? (isFresh ? now : session.lastObservedAt)
    let end = session.endedAt ?? activeEnd
    let minutes = max(0, Int(end.timeIntervalSince(session.startedAt) / 60))
    return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
}

private func estimatedRange(for batteryPercent: Double) -> Double {
    max(0, 18 + (batteryPercent - 27) * (11.0 / 14.0))
}

private func chargeBatteryGain(_ session: ChargeSession) -> Double? {
    guard let start = session.startBatteryPercent, let end = session.endBatteryPercent else { return nil }
    return max(0, end - start)
}

private func chargeTimelinePoint(title: String, date: Date, icon: String, trailing: Bool) -> some View {
    VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
        Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(CitroenTheme.brand)
        Text(date.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }.fixedSize(horizontal: true, vertical: false)
}

private struct TripBatteryBars: View {
    let start: Double?
    let end: Double?
    private let segments = 6

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<segments, id: \.self) { index in
                    Capsule().fill(segmentColor(index)).frame(height: 7)
                }
            }
            .accessibilityLabel("Varış batarya seviyesi \(end.map { "yüzde \(Int($0.rounded()))" } ?? "bilinmiyor")")
            if let start, let end {
                Text("%\(Int(start.rounded())) → %\(Int(end.rounded()))")
                    .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("Batarya ölçümü yok").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func segmentColor(_ index: Int) -> Color {
        guard let end else { return CitroenTheme.divider }
        let filled = Int(ceil(min(100, max(0, end)) / 100 * Double(segments)))
        guard index < filled else { return CitroenTheme.divider }
        return end <= 20 ? CitroenTheme.red : CitroenTheme.brand
    }
}

private struct ChargeEfficiencySummary {
    let kmPerFullCharge: Double
    let percentPer10Km: Double
    let kWhPer100Km: Double
    let tlPer100Km: Double
    let efficiencyLabel: String
    let tripCount: Int
}

private func chargeEfficiencySummary(for trips: [VehicleTrip]) -> ChargeEfficiencySummary? {
    let measured = trips.compactMap { trip -> (distance: Double, percent: Double)? in
        guard trip.endedAt != nil,
              let start = trip.startBatteryPercent, let end = trip.endBatteryPercent,
              start > end, start <= 100, end >= 0 else { return nil }
        let odometerDistance: Double? = {
            guard let a = trip.startOdometerKm, let b = trip.endOdometerKm, b > a else { return nil }
            return b - a
        }()
        let distance = odometerDistance ?? tripDistanceKm(trip.points)
        guard distance > 0.05 else { return nil }
        return (distance, start - end)
    }
    guard !measured.isEmpty else { return nil }
    let distance = measured.reduce(0) { $0 + $1.distance }
    let percent = measured.reduce(0) { $0 + $1.percent }
    guard distance > 0, percent > 0 else { return nil }
    let kWhPer100Km = percent / 100 * topolinoBatteryCapacityKWh / distance * 100
    return ChargeEfficiencySummary(kmPerFullCharge: distance / percent * 100,
                                   percentPer10Km: percent / distance * 10,
                                   kWhPer100Km: kWhPer100Km,
                                   tlPer100Km: kWhPer100Km * homeElectricityPricePerKWh,
                                   efficiencyLabel: efficiencyRating(kWhPer100Km),
                                   tripCount: measured.count)
}

private let topolinoBatteryCapacityKWh = 5.4
private let homeElectricityPricePerKWh = 5.0

private func efficiencyRating(_ kWhPer100Km: Double) -> String {
    if kWhPer100Km <= 7.2 { return "Çok verimli" }
    if kWhPer100Km <= 8.5 { return "Verimli" }
    if kWhPer100Km <= 10 { return "İyi" }
    return "Yüksek tüketim"
}

private func tripDistanceKm(_ points: [TripLocationPoint]) -> Double {
    guard points.count > 1 else { return 0 }
    return zip(points, points.dropFirst()).reduce(0.0) { total, pair in
        let distance = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        return total + (distance < 1000 ? distance : 0)
    } / 1000
}

private struct TripRoutePreview: View {
    let points: [TripLocationPoint]
    var body: some View {
        Group {
            if #available(iOS 17.0, *) { modernMap }
            else { canvasRoute }
        }
    }

    @available(iOS 17.0, *)
    private var modernMap: some View {
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let displayCoordinates = smoothedRouteCoordinates(points)
        let center = coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let minLat = displayCoordinates.map(\.latitude).min() ?? center.latitude
        let maxLat = displayCoordinates.map(\.latitude).max() ?? center.latitude
        let minLon = displayCoordinates.map(\.longitude).min() ?? center.longitude
        let maxLon = displayCoordinates.map(\.longitude).max() ?? center.longitude
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.003, (maxLat - minLat) * 1.5),
                                  longitudeDelta: max(0.003, (maxLon - minLon) * 1.5))
        )
        return Map(initialPosition: .region(region)) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: displayCoordinates).stroke(Color.mint, lineWidth: 4)
                Annotation("Başlangıç", coordinate: coordinates[0]) {
                    Circle().fill(.white).frame(width: 11, height: 11).overlay(Circle().stroke(Color.mint, lineWidth: 2))
                }
                Annotation("Varış", coordinate: coordinates[coordinates.count - 1]) {
                    Circle().fill(Color.mint).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            } else if let point = coordinates.first {
                Annotation("Kayıtlı GPS noktası", coordinate: point) {
                    Circle().fill(Color.mint).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("GPS rotası harita üzerinde")
    }

    private var canvasRoute: some View {
        Canvas { context, size in
            guard !points.isEmpty,
                  let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
                  let minLon = points.map(\.longitude).min(), let maxLon = points.map(\.longitude).max() else { return }
            let latSpan = max(maxLat - minLat, 0.00001)
            let lonSpan = max(maxLon - minLon, 0.00001)
            let pad: CGFloat = 16
            let rect = CGRect(x: pad, y: pad, width: max(1, size.width - 2 * pad), height: max(1, size.height - 2 * pad))
            let coordinates = smoothedRouteCoordinates(points).map { point in
                CGPoint(x: rect.minX + CGFloat((point.longitude - minLon) / lonSpan) * rect.width,
                        y: rect.maxY - CGFloat((point.latitude - minLat) / latSpan) * rect.height)
            }
            var path = Path()
            path.move(to: coordinates[0])
            for point in coordinates.dropFirst() { path.addLine(to: point) }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14),
                         with: .color(Color(red: 0.08, green: 0.13, blue: 0.22)))
            context.stroke(path, with: .color(Color.mint), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            for (index, point) in [coordinates.first, coordinates.last].compactMap({ $0 }).enumerated() {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                             with: .color(index == 0 ? .white : Color.mint))
            }
        }
        .accessibilityLabel("GPS rota çizgisi · \(points.count) nokta")
    }
}

// Smooth only the rendered path; stored GPS points and trip-distance calculations remain unchanged.
private func smoothedRouteCoordinates(_ points: [TripLocationPoint]) -> [CLLocationCoordinate2D] {
    let source = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    guard source.count > 2 else { return source }

    var smoothed = source
    for _ in 0..<3 {
        var next = [smoothed[0]]
        next.reserveCapacity(smoothed.count * 2)
        for (start, end) in zip(smoothed, smoothed.dropFirst()) {
            next.append(CLLocationCoordinate2D(
                latitude: start.latitude * 0.75 + end.latitude * 0.25,
                longitude: start.longitude * 0.75 + end.longitude * 0.25
            ))
            next.append(CLLocationCoordinate2D(
                latitude: start.latitude * 0.25 + end.latitude * 0.75,
                longitude: start.longitude * 0.25 + end.longitude * 0.75
            ))
        }
        next.append(smoothed[smoothed.count - 1])
        smoothed = next
    }
    return smoothed
}

private struct VehicleInfoPage: View {
    @ObservedObject var vehicle: VehicleStore
    @ObservedObject var gateway: AndroidGatewayClient
    private var can: AndroidGatewayCANTelemetry? { gateway.liveEspCan }
    private var classicCharge: ESPClassicChargeEstimate? { gateway.classicChargeEstimate(at: vehicle.estimateNow) }
    var body: some View {
        TestPage(title: "Belgeler", subtitle: "ESP CAN araç bilgileri ve ağ geçidi durumu") {
            TestCard(title: "Araç teknik bilgileri") {
                valueRow("Model", value: "Topolino")
                valueRow("Kilometre sayacı", value: (can?.odometerKm ?? classicCharge?.odometerKm).map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km\(can == nil && classicCharge != nil ? " · son şarj ESP kaydı" : "")" } ?? "Veri bekleniyor")
                valueRow("Batarya", value: can?.batteryPercent.map { "\($0)%" } ?? classicCharge.map { "≈ \(Int($0.batteryPercent.rounded()))%" } ?? "Veri bekleniyor")
                valueRow("Kalan menzil", value: can?.rangeKm.map { "\($0) km" } ?? classicCharge.map { "≈ \(Int($0.rangeKm.rounded())) km" } ?? "Veri bekleniyor")
                valueRow("Vites", value: can?.gear ?? "Veri bekleniyor")
                valueRow("Son araç verisi", value: can?.timestamp ?? classicCharge?.sourceTimestamp ?? "Henüz kayıt yok")
            }
            TestCard(title: "Araç bağlantısı") {
                valueRow("Durum", value: can != nil ? "ESP CAN canlı · Android ağ geçidi" : classicCharge != nil ? "Son şarj ESP kaydı · klasik hesap" : "ESP verisi bekleniyor")
                Text(gateway.status).font(.subheadline).foregroundStyle(.secondary)
            }
            TestCard(title: "Yol yardım") {
                Link(destination: URL(string: "tel:4442255")!) {
                    Label("Fiat yol yardım · 444 22 55", systemImage: "phone.fill")
                }
            }
        }
    }
}
private struct TestPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.custom("CitroenType-Bold", size: 24))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                content
            }.padding(18)
        }
        .background(CitroenTheme.canvas)
    }
}

private struct TestCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PowerFlowMeter: View {
    let powerKw: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("ANLIK GÜÇ DENGESİ").font(.caption.bold()).foregroundStyle(CitroenTheme.muted)
                Spacer()
                Text("\(powerKw.formatted(.number.precision(.fractionLength(2)))) kW")
                    .font(.system(.callout, design: .rounded).bold()).monospacedDigit()
            }
            HStack {
                Text("−\nGeri kazanım").font(.caption2.bold()).multilineTextAlignment(.center).foregroundStyle(.blue)
                GeometryReader { geometry in
                    let middle = geometry.size.width / 2
                    let barWidth = max(3, min(middle - 2, abs(powerKw) / 15 * (middle - 2)))
                    ZStack {
                        Capsule().fill(Color.secondary.opacity(0.22)).frame(height: 6)
                        Rectangle().fill(powerKw < 0 ? Color.blue : Color.teal)
                            .frame(width: barWidth, height: 8)
                            .position(x: middle + (powerKw < 0 ? -barWidth / 2 : barWidth / 2), y: geometry.size.height / 2)
                        Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 14)
                            .position(x: middle, y: geometry.size.height / 2)
                    }
                }
                .frame(height: 18)
                Text("+\nÇekiş").font(.caption2.bold()).multilineTextAlignment(.center).foregroundStyle(.teal)
            }
            Text("+ çekiş/tüketim adayı · − bataryaya giriş/geri kazanım adayı. Bu, motor çıkışı değil batarya gücüdür.")
                .font(.caption2).foregroundStyle(CitroenTheme.muted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anlık güç dengesi \(powerKw.formatted(.number.precision(.fractionLength(2)))) kilovat. Artı çekiş adayı, eksi bataryaya giriş ve geri kazanım adayı.")
    }
}

private func valueRow(_ title: String, value: String) -> some View {
    HStack {
        Text(title).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(value).multilineTextAlignment(.trailing).fontWeight(.medium)
    }
    .font(.subheadline)
    .padding(.vertical, 3)
}

private extension View {
    func cardStyle() -> some View {
        background(CitroenTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
