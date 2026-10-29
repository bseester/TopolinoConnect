package local.topolinoconnect.gateway

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.time.Instant

/** User-facing diagnostics for connection, permission, freshness, and capture checks. */
// The app ships Turkish-only; this diagnostic summary is intentionally Turkish.
@SuppressLint("SetTextI18n")
class GatewayDebugActivity : Activity() {
    private lateinit var report: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(28))
            setBackgroundColor(0xFF090F20.toInt())
        }
        setContentView(ScrollView(this).apply { addView(content) })
        content.addView(TextView(this).apply {
            text = "Bağlantı tanılaması"
            textSize = 24f
            setTextColor(0xFFF1F5F8.toInt())
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        })
        content.addView(TextView(this).apply {
            text = "Sorun bildirirken bu özeti ve CAN çerçeveleri ekranındaki son kayıtları paylaş."
            textSize = 14f
            setTextColor(0xFFAAB8CC.toInt())
        })
        report = TextView(this).apply {
            textSize = 14f
            setTextColor(0xFFE0E8F2.toInt())
            typeface = android.graphics.Typeface.MONOSPACE
            setPadding(dp(14), dp(14), dp(14), dp(14))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(0xFF121D34.toInt())
                cornerRadius = dp(16).toFloat()
            }
        }
        content.addView(report, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(16)
        })
        content.addView(Button(this).apply {
            text = "Tanılama özetini kopyala"
            isAllCaps = false
            setOnClickListener {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("Topolino tanılama", report.text))
            }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(12)
        })
        content.addView(Button(this).apply {
            text = "Yenile"
            isAllCaps = false
            setOnClickListener { render() }
        })
        render()
    }

    override fun onResume() {
        super.onResume()
        if (::report.isInitialized) render()
    }

    private fun render() {
        val blePermissions = if (Build.VERSION.SDK_INT >= 31) {
            granted(Manifest.permission.BLUETOOTH_SCAN) && granted(Manifest.permission.BLUETOOTH_CONNECT)
        } else granted(Manifest.permission.ACCESS_FINE_LOCATION) && granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        val usbConnected = GatewayConfig.inputMode(this) == GatewayConfig.InputMode.USB_OTG &&
            GatewayRuntime.status.contains("USB", ignoreCase = true)
        val ageMs = GatewayRuntime.lastTelemetryAt?.let {
            runCatching { java.time.Duration.between(Instant.parse(it), Instant.now()).toMillis() }.getOrNull()
        }
        report.text = buildString {
            appendLine("Uygulama: Topolino Gateway 0.4.10")
            appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("Cihaz: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Seçili kaynak: ${when (GatewayConfig.inputMode(this@GatewayDebugActivity)) {
                GatewayConfig.InputMode.BLUETOOTH -> "Bluetooth LE"
                GatewayConfig.InputMode.USB_OTG -> "USB-OTG seri"
                GatewayConfig.InputMode.NONE -> "Durduruldu / seçilmedi"
            }}")
            appendLine("Bluetooth izinleri: ${if (blePermissions) "verildi" else "eksik"}")
            appendLine("Bağlantı durumu: ${GatewayRuntime.status}")
            appendLine("USB seri: ${if (usbConnected) "etkin" else "etkin değil / görünmüyor"}")
            appendLine("Son telemetri: ${ageMs?.let { "${it.coerceAtLeast(0) / 1000} sn önce" } ?: "henüz yok"}")
            appendLine("CAN kareleri: ${GatewayRuntime.canFrameCount} toplam · ${GatewayRuntime.resolvedFrameCount} çözülen · ${GatewayRuntime.unresolvedFrameCount} ham")
            appendLine("Kare kanalı: ${GatewayRuntime.gattFrameStatus}")
            appendLine("Kayıt dosyası: ${GatewayRuntime.canFrameLogPath.ifBlank { "henüz oluşturulmadı" }}")
            appendLine("iOS aktarımı: ${AndroidRelayClient.statusText(this@GatewayDebugActivity)}")
        }
    }

    private fun granted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
