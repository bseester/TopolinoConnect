package local.topolinoconnect.gateway

import android.app.Activity
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import org.json.JSONObject
import java.time.Instant
import java.util.Locale

/** Reads the same 115200-baud ESP32/MCP2515 serial stream used by the Mac monitor. */
// The app ships Turkish-only; USB connection states and CAN readouts are intentionally Turkish.
@SuppressLint("SetTextI18n")
class UsbCanActivity : Activity(), SerialInputOutputManager.Listener {
    private lateinit var usbManager: UsbManager
    private lateinit var status: TextView
    private lateinit var readouts: TextView
    private lateinit var frames: TextView
    private lateinit var deviceList: LinearLayout
    private var port: UsbSerialPort? = null
    private var connection: android.hardware.usb.UsbDeviceConnection? = null
    private var ioManager: SerialInputOutputManager? = null
    private var usbWakeLock: PowerManager.WakeLock? = null
    private val lineAccumulator = SerialLineAccumulator()
    private val recentLines = ArrayDeque<String>()
    private val refreshReadouts = object : Runnable {
        override fun run() {
            renderReadouts()
            window.decorView.postDelayed(this, 250)
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_USB_PERMISSION) return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val device = usbDeviceExtra(intent) ?: return
            if (granted) openDevice(device) else status.text = "USB izni verilmedi"
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        GatewayConfig.setInputMode(this, GatewayConfig.InputMode.USB_OTG)
        GatewayConfig.setAutoStart(this, false)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(permissionReceiver, filter, RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(permissionReceiver, filter)
        buildUi()
        GatewayConfig.setAutoStart(this, false)
        startService(Intent(this, GatewayService::class.java).setAction(GatewayService.ACTION_STOP))
        showDevices()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(18), dp(16), dp(28))
            setBackgroundColor(0xFF090F20.toInt())
        }
        setContentView(ScrollView(this).apply { addView(root) })
        root.addView(label("USB-OTG · CAN MONİTÖRÜ", 22, true))
        root.addView(label("ESP32’yi USB-OTG adaptörüyle telefona bağla. Seri hız 115200 baud.", 14))
        root.addView(Button(this).apply {
            text = "Mod seçimine dön"
            isAllCaps = false
            setOnClickListener { finish() }
        })
        status = label("USB seri cihazı aranıyor", 15, true).apply { setTextColor(0xFF49D7C5.toInt()) }
        root.addView(status)
        root.addView(Button(this).apply { text = "USB cihazlarını yenile"; setOnClickListener { showDevices() } })
        deviceList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(deviceList)
        root.addView(label("ARAÇ VERİLERİ", 15, true))
        readouts = label("Araç CAN verisi bekleniyor", 15)
        root.addView(readouts)
        root.addView(label("CAN ÇERÇEVELERİ", 15, true))
        frames = label("USB’den çerçeve bekleniyor", 12).apply {
            typeface = android.graphics.Typeface.MONOSPACE
        }
        root.addView(frames)
        window.decorView.post(refreshReadouts)
    }

    private fun renderReadouts() {
        val can = GatewayRuntime.espCan ?: return
        readouts.text = buildString {
            append("Vites ${can.optString("gear", "—")} · Batarya ${can.nullableNumber("batteryPercent")} % · Menzil ${can.nullableNumber("rangeKm")} km\n")
            append("Gerilim ${can.nullableNumber("voltageV")} V · Akım ${can.nullableNumber("currentA")} A · Güç ${can.nullableNumber("batteryPowerKw")} kW\n")
            append("12 V ${can.nullableNumber("battery12V")} V · Sıcaklık ${can.nullableNumber("temperature1C")} / ${can.nullableNumber("temperature2C")} °C\n")
            append("DBC adayları · Akım ${can.nullableNumber("currentDbcCandidateA")} A · 12 V ham ${can.nullableNumber("battery12VDbcCandidate")} · Şarj ham ${can.nullableNumber("chargeTimeRawDbc")} sn · READY ${can.optString("readyStateText", "—")}\n")
            append("Şarj ${can.nullableBoolean("charging")} · Doluma kalan ${can.nullableNumber("chargeMinutesRemaining")} dk · Güncelleme ${can.optString("timestamp", "—")}")
        }
    }

    private fun showDevices() {
        deviceList.removeAllViews()
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (drivers.isEmpty()) {
            status.text = if (usbManager.deviceList.isEmpty()) "USB cihazı yok · OTG kablosu ve telefonun USB host desteğini kontrol et"
            else "USB aygıtı görüldü ama seri dönüştürücü tanınmadı"
            return
        }
        status.text = "${drivers.size} USB seri cihazı bulundu · ESP32’yi seç"
        drivers.forEach { driver ->
            val device = driver.device
            val title = "${device.productName ?: device.deviceName} · VID ${device.vendorId.toString(16)} / PID ${device.productId.toString(16)}"
            deviceList.addView(Button(this).apply {
                text = title
                isAllCaps = false
                setOnClickListener {
                    if (usbManager.hasPermission(device)) openDevice(device)
                    else {
                        val permission = PendingIntent.getBroadcast(
                            this@UsbCanActivity, device.deviceId,
                            Intent(ACTION_USB_PERMISSION).setPackage(packageName),
                            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                        )
                        usbManager.requestPermission(device, permission)
                    }
                }
            })
        }
    }

    private fun openDevice(device: UsbDevice) {
        val driver = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
            .firstOrNull { it.device.deviceId == device.deviceId }
        if (driver == null) {
            status.text = "USB seri sürücüsü bulunamadı"
            return
        }
        try {
            val usbConnection = usbManager.openDevice(device) ?: error("USB cihazı açılamadı")
            val serialPort = driver.ports.firstOrNull() ?: error("Seri port bulunamadı")
            serialPort.open(usbConnection)
            serialPort.setParameters(115200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            connection = usbConnection
            port = serialPort
            usbWakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:UsbCanReader")
                .apply { setReferenceCounted(false); acquire(30 * 60 * 1000L) }
            ioManager = SerialInputOutputManager(serialPort, this).also { it.start() }
            status.text = "USB seri bağlı · 115200 baud · CAN akışı bekleniyor"
        } catch (error: Exception) {
            status.text = "USB bağlantı hatası · ${error.localizedMessage ?: error.javaClass.simpleName}"
            closePort()
        }
    }

    override fun onNewData(data: ByteArray) {
        lineAccumulator.append(data).forEach(::handleLine)
    }

    private fun handleLine(line: String) {
        if (line.isBlank()) return
        if (line.startsWith("{\"type\":\"telemetry\"")) {
            acceptTelemetryLine(line)
            return
        }
        if (!line.startsWith("CAN ")) {
            val message = line.take(160)
            runOnUiThread { status.text = message }
            return
        }
        val parsed = MacCanSerialFrameParser.parse(line) ?: return
        val extended = parsed.extended
        val identifier = parsed.identifier
        val dlc = parsed.dlc
        val bytes = parsed.data
        val now = Instant.now().toString()
        val dataText = bytes.joinToString(" ") { "%02X".format(it.toInt() and 0xff) }
        val entry = JSONObject().put("id", "0x${identifier.toString(16).uppercase(Locale.US).padStart(if (extended) 8 else 3, '0')}")
            .put("extended", extended).put("dlc", dlc).put("data", dataText).put("timestampUs", parsed.timestampUs ?: JSONObject.NULL)
            .put("timestamp", now).put("simulation", false)
        val decoded = if (extended) null else TopolinoCanDecoder.decodeFrame(identifier, bytes, GatewayRuntime.vehicleSnapshot)
        GatewayRuntime.addCanFrame(entry, decoded != null)
        CanFrameRecorder.record(this, entry)
        if (decoded != null) {
            val merged = GatewayRuntime.vehicleSnapshot?.merge(decoded) ?: decoded
            ClassicRangeEstimateStore.capture(this, merged, decoded.batteryPercent != null)
            GatewayRuntime.vehicleSnapshot = merged
            val json = merged.toJson().put("timestamp", now)
            GatewayRuntime.espCan = json
            GatewayRuntime.espCanAt = now
            GatewayRuntime.lastTelemetryAt = now
            GatewayRuntime.acceptCanSample(json)
            AndroidRelayClient.publishIfEnabled(this, json)
        } else AndroidRelayClient.publishRawFrameUpdate(this)
        GatewayRuntime.gattFrameStatus = "USB-OTG CAN canlı · 115200 baud"
        GatewayRuntime.status = "ESP32 USB-OTG CAN canlı"
        recentLines.addFirst("${entry.optString("id")}  DLC $dlc  $dataText  ${if (decoded != null) "Mac CAN decode" else "Ham · eşleşme yok"}")
        while (recentLines.size > 32) recentLines.removeLast()
        val frameText = recentLines.joinToString("\n")
        runOnUiThread {
            status.text = "ESP32 USB-OTG CAN canlı · ${entry.optString("id")}"
            frames.text = frameText
        }
    }

    private fun acceptTelemetryLine(line: String) {
        val packet = runCatching { JSONObject(line) }.getOrNull() ?: return
        val canLive = packet.optBoolean("can", false)
        val patch = MacCanSerialFrameParser.decodeTelemetry(line, null) ?: return
        val decoded = (GatewayRuntime.vehicleSnapshot?.merge(patch) ?: patch).copy(canLive = canLive)
        GatewayRuntime.vehicleSnapshot = decoded
        ClassicRangeEstimateStore.capture(this, decoded, patch.batteryPercent != null)
        val now = Instant.now().toString()
        val json = decoded.toJson().put("timestamp", now)
        GatewayRuntime.espCan = json
        GatewayRuntime.espCanAt = now
        if (canLive) GatewayRuntime.lastTelemetryAt = now
        GatewayRuntime.acceptCanSample(json)
        AndroidRelayClient.publishIfEnabled(this, json)
        GatewayRuntime.status = if (canLive) "ESP USB-OTG telemetrisi canlı" else "ESP USB-OTG bağlı · araç CAN çerçevesi bekleniyor"
    }

    override fun onRunError(error: Exception) {
        runOnUiThread {
            status.text = "USB okuma durdu · ${error.localizedMessage ?: error.javaClass.simpleName}"
            closePort()
        }
    }

    override fun onDestroy() {
        window.decorView.removeCallbacks(refreshReadouts)
        closePort()
        runCatching { unregisterReceiver(permissionReceiver) }
        super.onDestroy()
    }

    private fun closePort() {
        ioManager?.listener = null
        runCatching { ioManager?.stop() }
        ioManager = null
        runCatching { port?.close() }
        port = null
        runCatching { connection?.close() }
        connection = null
        runCatching { if (usbWakeLock?.isHeld == true) usbWakeLock?.release() }
        usbWakeLock = null
    }

    private fun label(text: String, size: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size.toFloat()
        setTextColor(if (bold) 0xFFF3F6FC.toInt() else 0xFFB8C5D7.toInt())
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, dp(7), 0, dp(7))
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun JSONObject.nullableNumber(key: String): String =
        if (!has(key) || isNull(key)) "—" else String.format(Locale.US, "%.1f", optDouble(key))

    private fun JSONObject.nullableBoolean(key: String): String =
        if (!has(key) || isNull(key)) "—" else if (optBoolean(key)) "açık" else "kapalı"

    private fun usbDeviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)

    companion object {
        private const val ACTION_USB_PERMISSION = "local.topolinoconnect.gateway.USB_PERMISSION"
    }
}
