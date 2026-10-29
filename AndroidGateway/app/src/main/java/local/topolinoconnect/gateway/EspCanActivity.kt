package local.topolinoconnect.gateway

import android.app.Activity
import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/** Full CAN dashboard, live telemetry, trip estimates, and raw frames from the ESP GATT stream. */
// The app ships Turkish-only; live CAN readouts are intentionally assembled in Turkish.
@SuppressLint("SetTextI18n")
class EspCanActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var values: TextView
    private lateinit var session: TextView
    private lateinit var frames: TextView
    private lateinit var dashboard: TopolinoDashboardView
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 100)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(20, 24, 20, 28)
            setBackgroundColor(0xFF091020.toInt())
        }
        setContentView(ScrollView(this).apply { addView(layout) })
        layout.addView(label("ESP CAN · ARAÇ VERİLERİ", 23, true))
        status = label("ESP BLE yayını bekleniyor", 15)
        layout.addView(status)

        dashboard = TopolinoDashboardView(this)
        layout.addView(dashboard, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = 14
            bottomMargin = 12
        })

        layout.addView(label("Canlı araç ve batarya verileri", 17, true))
        values = label("Henüz ESP CAN verisi alınmadı", 14)
        layout.addView(values)

        layout.addView(label("Bu oturum", 17, true).apply { setPadding(0, dp(18), 0, 0) })
        session = label("Oturum verileri bekleniyor", 14)
        layout.addView(session)
        layout.addView(button("Oturum ölçümlerini sıfırla", false) { GatewayRuntime.resetSessionMetrics(); render() })

        layout.addView(label("CAN çerçeveleri · ${GatewayRuntime.gattFrameStatus}", 17, true).apply { setPadding(0, dp(18), 0, 0) })
        frames = label("Ham CAN çerçeve kanalı bekleniyor", 12)
        frames.typeface = android.graphics.Typeface.MONOSPACE
        layout.addView(frames)

        layout.addView(button("ESP BLE taramasını başlat", true) { requestScanPermissionsAndStart() })
        layout.addView(button("Göstergeyi tam ekran aç", false) {
            startActivity(Intent(this, TopolinoGaugeActivity::class.java))
        })
        layout.addView(label("Ham çerçeveler, ESP’nin FDE1/FDE2 BLE kanalından gelir. Bu kanal için güncel ESP yazılımı gerekir.", 13))
        handler.post(refresh)
    }

    private fun startGateway() {
        GatewayConfig.setInputMode(this, GatewayConfig.InputMode.BLUETOOTH)
        GatewayConfig.setAutoStart(this, true)
        val intent = Intent(this, GatewayService::class.java).setAction(GatewayService.ACTION_START)
        startForegroundService(intent)
    }

    private fun requestScanPermissionsAndStart() {
        val required = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) required += Manifest.permission.BLUETOOTH_SCAN
            if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) required += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) required += Manifest.permission.ACCESS_FINE_LOCATION
            if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) required += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        if (required.isNotEmpty()) requestPermissions(required.toTypedArray(), REQUEST_SCAN_PERMISSIONS) else startGateway()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SCAN_PERMISSIONS) return
        val granted = if (Build.VERSION.SDK_INT >= 31) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (granted) startGateway() else status.text = "ESP taraması için Bluetooth izni gerekli"
    }

    private fun render() {
        dashboard.refreshFromRuntime()
        val can = GatewayRuntime.espCan
        status.text = buildString {
            append(GatewayRuntime.status)
            GatewayRuntime.espCanRssi?.let { append(" · $it dBm") }
        }
        if (can == null) {
            values.text = ClassicRangeEstimateStore.estimate(this)?.let {
                "Araç verisi yok · son güvenilir ESP batarya örneğinden tahmini menzil ≈ ${it.rangeKm.toInt()} km (klasik hesap)"
            } ?: "ESP CAN verisi bekleniyor. ESP açık, BLE yayını etkin ve MCP2515’ten CAN verisi geliyor olmalı."
        } else {
            val canLive = can.optBoolean("canLive", true)
            val liveRange = can.optDouble("rangeKm", Double.NaN).takeIf {
                canLive && it.isFinite() && it > 0.0
            }
            val classicRange = ClassicRangeEstimateStore.estimate(this)
            val rangeText = liveRange?.let { "${it.toInt()} km" }
                ?: classicRange?.let { "≈ ${it.rangeKm.toInt()} km · klasik hesap" }
                ?: can.nullableText("rangeKm").let { "$it km" }
            values.text = buildString {
                if (!canLive) append("Araç çevrim dışı · yalnızca mevcut şarj alanları gösteriliyor\n")
                append("Vites: ${can.nullableText("gear")} · READY: ${can.booleanText("ready")} · El freni: ${can.booleanText("handbrake")}\n")
                append("Batarya: ${can.nullableText("batteryPercent")}% · Menzil: $rangeText · ODO: ${can.nullableNumber("odometerKm")} km\n")
                append("Batarya: ${can.nullableNumber("voltageV")} V · ${can.nullableNumber("currentA")} A · Güç dengesi: ${can.nullableNumber("batteryPowerKw")} kW\n")
                append("Güç işareti: + çekiş/tüketim adayı · − bataryaya giriş/geri kazanım adayı\n")
                append("12 V akü: ${can.nullableNumber("battery12V")} V · Sıcaklıklar: ${can.nullableText("temperature1C")} / ${can.nullableText("temperature2C")} °C\n")
                append("Mac çözücü adayları · akım DBC ${can.nullableNumber("currentDbcCandidateA")} A · 12 V DBC ham ${can.nullableNumber("battery12VDbcCandidate")} · sıcaklık DBC ham ${can.nullableText("temperature1DbcRaw")} / ${can.nullableText("temperature2DbcRaw")} · şarj süresi ham ${can.nullableText("chargeTimeRawDbc")} sn · READY ${can.nullableText("readyStateText")}\n")
                append("Şarj: ${when { can.isNull("charging") -> "—"; can.optBoolean("charging") -> "Şarj oluyor"; else -> "Şarjda değil" }}")
                if (!can.isNull("chargeMinutesRemaining")) append(" · Doluma kalan: ${can.optInt("chargeMinutesRemaining") / 60} sa ${can.optInt("chargeMinutesRemaining") % 60} dk")
                append(" · Şarj gücü: ${can.nullableNumber("chargePowerKw")} kW\n")
                append("Kaynak: ${can.optString("source", "Topolino ESP CAN BLE")} · Paket: ${can.optString("timestamp", "—")}")
            }
        }

        session.text = buildString {
            append("Mesafe: ${fmt(GatewayRuntime.sessionTripDistanceKm)} km · Tüketim enerjisi: ${fmt(GatewayRuntime.sessionEnergyOutKwh)} kWh\n")
            append("Tahmini sürüş enerjisi: ${fmtOrDash(GatewayRuntime.sessionEstimatedDriveEnergyKwh)} kWh · Tahmini tüketim: ${fmtOrDash(GatewayRuntime.sessionEstimatedConsumptionKwhPer100Km)} kWh/100 km\n")
            append("Bataryaya giren enerji: ${fmt(GatewayRuntime.sessionEnergyInKwh)} kWh · Hareket hâlinde geri kazanım adayı: ${fmt(GatewayRuntime.sessionRegenCandidateKwh)} kWh")
        }
        val frameList = GatewayRuntime.canFrames
        frames.text = buildString {
            append("${GatewayRuntime.gattFrameStatus}\n")
            append("Toplam ${GatewayRuntime.canFrameCount} · Çözülen ${GatewayRuntime.resolvedFrameCount} · Ham ${GatewayRuntime.unresolvedFrameCount}\n")
            if (GatewayRuntime.canFrameLogPath.isNotBlank()) append("Kayıt: ${GatewayRuntime.canFrameLogPath}\n")
            if (frameList.length() == 0) append("Henüz ham çerçeve alınmadı")
            else for (index in 0 until minOf(frameList.length(), 32)) {
                val frame = frameList.optJSONObject(index) ?: continue
                append("${if (frame.optBoolean("simulation")) "[TEST] " else ""}${frame.optString("id")}  DLC ${frame.optInt("dlc")}  ${frame.optString("data")}  ${if (frame.optBoolean("resolved")) "Mac CAN decode" else "Ham · eşleşme yok"}\n")
            }
        }
    }

    private fun fmt(value: Double) = String.format(Locale.US, "%.2f", value)
    private fun fmtOrDash(value: Double?) = value?.let(::fmt) ?: "—"
    private fun JSONObject.nullableText(key: String): String = if (isNull(key)) "—" else optString(key)
    private fun JSONObject.nullableNumber(key: String): String = if (isNull(key)) "—" else String.format(Locale.US, "%.1f", optDouble(key))
    private fun JSONObject.booleanText(key: String): String = if (isNull(key)) "—" else if (optBoolean(key)) "Evet" else "Hayır"

    private fun label(text: String, size: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size.toFloat()
        setTextColor(if (bold) 0xFFF3F6FC.toInt() else 0xFFB8C5D7.toInt())
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, dp(7), 0, dp(7))
    }

    private fun button(text: String, primary: Boolean, action: () -> Unit) = Button(this).apply {
        this.text = text
        setOnClickListener { action() }
        if (primary) setTextColor(0xFF08211F.toInt())
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        handler.removeCallbacks(refresh)
        super.onDestroy()
    }

    companion object { private const val REQUEST_SCAN_PERMISSIONS = 1001 }
}
