package local.topolinoconnect.gateway

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

/** Android's local BLE CAN monitor, based on the Mac CAN monitor's live view. */
// The app ships Turkish-only; these compact connection-state labels are intentionally Turkish.
@SuppressLint("SetTextI18n")
class MainActivity : Activity() {
    private lateinit var root: LinearLayout
    private lateinit var status: TextView
    private lateinit var readouts: TextView
    private lateinit var transferStatus: TextView
    private lateinit var modeStatus: TextView
    private lateinit var modeChoices: RadioGroup
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
        ClassicRangeEstimateStore.initialize(this)
        buildMonitor()
        handler.post(refresh)
    }

    override fun onResume() {
        super.onResume()
        if (GatewayConfig.shouldAutoStart(this) &&
            GatewayConfig.inputMode(this) == GatewayConfig.InputMode.BLUETOOTH &&
            hasBluetoothPermission()) startMonitor()
    }

    override fun onDestroy() {
        handler.removeCallbacks(refresh)
        super.onDestroy()
    }

    private fun buildMonitor() {
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(18), dp(16), dp(32))
            setBackgroundColor(0xFF090F20.toInt())
        }
        setContentView(ScrollView(this).apply { addView(root) })
        root.addView(label("TOPOLINO · CAN MONİTÖRÜ", 23, true))
        status = label("ESP BLE bağlantısı bekleniyor", 14, true).apply { setTextColor(0xFF49D7C5.toInt()) }
        root.addView(status)

        dashboard = TopolinoDashboardView(this)
        root.addView(dashboard, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(235)
        ).apply { topMargin = dp(10); bottomMargin = dp(10) })

        root.addView(card().apply {
            addView(label("CAN’DEN ÇÖZÜLEN ARAÇ VERİLERİ", 13, true))
            readouts = label("Vites, batarya ve güç dengesi bekleniyor", 15)
            addView(readouts)
        }, margin())
        root.addView(card().apply {
            addView(label("BAĞLANTI MODU", 13, true))
            addView(label("Tek seferde bir kaynak kullanılır. Mod değiştirirken mevcut bağlantı kapatılır.", 12)
                .apply { setTextColor(0xFF9BAAC0.toInt()) })
            modeStatus = label("Mod seçilmedi", 14, true)
            addView(modeStatus)
            val choices = RadioGroup(this@MainActivity).apply {
                orientation = RadioGroup.HORIZONTAL
                val bluetooth = RadioButton(this@MainActivity).apply {
                    id = MODE_BLUETOOTH
                    text = "Bluetooth"
                    setTextColor(0xFFF1F5F8.toInt())
                }
                val usb = RadioButton(this@MainActivity).apply {
                    id = MODE_USB
                    text = "USB-OTG"
                    setTextColor(0xFFF1F5F8.toInt())
                }
                addView(bluetooth, RadioGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(usb, RadioGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }
            modeChoices = choices
            when (GatewayConfig.inputMode(this@MainActivity)) {
                GatewayConfig.InputMode.BLUETOOTH -> choices.check(MODE_BLUETOOTH)
                GatewayConfig.InputMode.USB_OTG -> choices.check(MODE_USB)
                GatewayConfig.InputMode.NONE -> Unit
            }
            choices.setOnCheckedChangeListener { _, selected ->
                when (selected) {
                    MODE_BLUETOOTH -> requestBlePermissions()
                    MODE_USB -> openUsbMode()
                }
            }
            addView(choices)
            addView(action("Bluetooth bağlantısını durdur", false) {
            GatewayConfig.setAutoStart(this@MainActivity, false)
            GatewayConfig.setInputMode(this@MainActivity, GatewayConfig.InputMode.NONE)
            startService(Intent(this@MainActivity, GatewayService::class.java).setAction(GatewayService.ACTION_STOP))
                modeChoices.clearCheck()
                modeStatus.text = "Bağlantı durduruldu"
            })
            addView(action("Bluetooth’u başlat / yeniden dene", true) { requestBlePermissions() })
        }, margin())
        root.addView(action("Tüm CAN çerçeveleri ve ölçümler", false) {
            startActivity(Intent(this, EspCanActivity::class.java))
        }, margin())
        root.addView(action("Tanılama ve hata ayıklama", false) {
            startActivity(Intent(this, GatewayDebugActivity::class.java))
        }, margin())
        root.addView(action("Tam ekran gösterge", false) {
            startActivity(Intent(this, TopolinoGaugeActivity::class.java))
        })
        root.addView(card().apply {
            addView(label("iOS’A CANLI AKTARIM", 13, true))
            transferStatus = label(AndroidRelayClient.statusText(this@MainActivity), 13)
            addView(transferStatus)
            addView(Switch(this@MainActivity).apply {
                text = "ESP verilerini iOS’a gönder"
                setTextColor(0xFFF1F5F8.toInt())
                isChecked = AndroidRelayClient.isEnabled(this@MainActivity)
                setOnCheckedChangeListener { _, enabled ->
                    AndroidRelayClient.setEnabled(this@MainActivity, enabled)
                    transferStatus.text = AndroidRelayClient.statusText(this@MainActivity)
                }
            })
            addView(action("iOS erişim anahtarını kopyala", false) {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("X-Topolino-Key", AndroidRelayClient.accessKey(this@MainActivity)))
                Toast.makeText(this@MainActivity, "Anahtar kopyalandı · iOS Android araç telefonu ayarına yapıştır", Toast.LENGTH_LONG).show()
            })
            addView(label("iOS’ta Diğer → Android araç telefonu bölümüne anahtarı yapıştırıp Kaydet ve bağlan’a bas. Aktarım internet üzerinden yapılır.", 12)
                .apply { setTextColor(0xFF8797AD.toInt()) })
        }, margin())
    }

    private fun requestBlePermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) needed += Manifest.permission.BLUETOOTH_SCAN
            if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) needed += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) needed += Manifest.permission.ACCESS_FINE_LOCATION
            if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) needed += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            needed += Manifest.permission.POST_NOTIFICATIONS
        }
        if (needed.isEmpty()) startMonitor() else requestPermissions(needed.toTypedArray(), REQUEST_BLE_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLE_PERMISSIONS) return
        if (hasBluetoothPermission()) startMonitor() else {
            GatewayConfig.setInputMode(this, GatewayConfig.InputMode.NONE)
            modeChoices.clearCheck()
            status.text = "Bluetooth izni verilmedi · ESP’ye bağlanılamıyor"
        }
    }

    private fun hasBluetoothPermission(): Boolean = if (Build.VERSION.SDK_INT >= 31) {
        checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    } else checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED &&
        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun startMonitor() {
        GatewayConfig.setInputMode(this, GatewayConfig.InputMode.BLUETOOTH)
        GatewayConfig.setAutoStart(this, true)
        val intent = Intent(this, GatewayService::class.java).setAction(GatewayService.ACTION_START)
        startForegroundService(intent)
        status.text = "ESP BLE aranıyor…"
        if (::modeStatus.isInitialized) modeStatus.text = "Bluetooth · ESP aranıyor"
    }

    private fun openUsbMode() {
        GatewayConfig.setAutoStart(this, false)
        GatewayConfig.setInputMode(this, GatewayConfig.InputMode.USB_OTG)
        startService(Intent(this, GatewayService::class.java).setAction(GatewayService.ACTION_STOP))
        modeStatus.text = "USB-OTG · Bluetooth kapalı"
        startActivity(Intent(this, UsbCanActivity::class.java))
    }

    private fun render() {
        if (!::dashboard.isInitialized) return
        status.text = GatewayRuntime.status
        if (::modeStatus.isInitialized) modeStatus.text = when (GatewayConfig.inputMode(this)) {
            GatewayConfig.InputMode.BLUETOOTH -> "Bluetooth · ${GatewayRuntime.status}"
            GatewayConfig.InputMode.USB_OTG -> "USB-OTG · Bluetooth kapalı"
            GatewayConfig.InputMode.NONE -> "Bağlantı durduruldu"
        }
        if (::transferStatus.isInitialized) transferStatus.text = AndroidRelayClient.statusText(this)
        status.setTextColor(if (GatewayRuntime.vehicleSnapshot?.simulation == true) 0xFFFFB74D.toInt() else 0xFF49D7C5.toInt())
        dashboard.refreshFromRuntime()
        val can = GatewayRuntime.espCan
        val liveRange = can?.optDouble("rangeKm", Double.NaN)?.takeIf { it.isFinite() && it > 0.0 }
        val useLiveRange = GatewayRuntime.hasFreshTelemetry() && can?.optBoolean("canLive", true) == true && liveRange != null
        val classicRange = ClassicRangeEstimateStore.estimate(this)
        val rangeText = if (useLiveRange) "${liveRange!!.toInt()} km" else
            classicRange?.let { "≈ ${it.rangeKm.toInt()} km · klasik hesap" } ?: (liveRange?.let { "${it.toInt()} km" } ?: "— km")
        readouts.text = if (can == null) {
            classicRange?.let { "ESP araç verisi yok · Tahmini menzil ≈ ${it.rangeKm.toInt()} km · klasik hesap" }
                ?: "ESP’den araç verisi bekleniyor"
        } else buildString {
            append("Vites ${value(can, "gear")} · READY ${boolean(can, "ready")}\n")
            append("Batarya ${metric(can, "batteryPercent", "%")} · Menzil $rangeText · ODO ${metric(can, "odometerKm", "km")}\n")
            append("Güç ${metric(can, "batteryPowerKw", "kW")} · Akım ${metric(can, "currentA", "A")} · Gerilim ${metric(can, "voltageV", "V")}\n")
            append("Şarj ${boolean(can, "charging")} · Kalan ${metric(can, "chargeMinutesRemaining", "dk")} · 12 V ${metric(can, "battery12V", "V")}\n")
            append("Batarya sıcaklıkları ${metric(can, "temperature1C", "°C")} / ${metric(can, "temperature2C", "°C")}")
        }
    }

    private fun value(json: JSONObject, key: String): String =
        if (json.has(key) && !json.isNull(key)) json.optString(key) else "—"

    private fun metric(json: JSONObject, key: String, unit: String): String =
        if (json.has(key) && !json.isNull(key)) "${json.opt(key)} $unit" else "— $unit"

    private fun boolean(json: JSONObject, key: String): String =
        if (!json.has(key) || json.isNull(key)) "—" else if (json.optBoolean(key)) "Evet" else "Hayır"

    private fun label(text: String, size: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size.toFloat()
        setTextColor(if (bold) 0xFFF1F5F8.toInt() else 0xFFD3DCE8.toInt())
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, dp(5), 0, dp(5))
    }

    private fun card() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(14), dp(11), dp(14), dp(11))
        background = android.graphics.drawable.GradientDrawable().apply {
            setColor(0xFF121D34.toInt())
            cornerRadius = dp(16).toFloat()
            setStroke(dp(1), 0xFF202E49.toInt())
        }
    }

    private fun action(text: String, primary: Boolean, run: () -> Unit) = Button(this).apply {
        this.text = text
        isAllCaps = false
        setOnClickListener { run() }
        if (primary) setTextColor(0xFF052B2B.toInt())
    }

    private fun margin() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(8); bottomMargin = dp(5) }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val REQUEST_BLE_PERMISSIONS = 706
        private const val MODE_BLUETOOTH = 8001
        private const val MODE_USB = 8002
    }
}
