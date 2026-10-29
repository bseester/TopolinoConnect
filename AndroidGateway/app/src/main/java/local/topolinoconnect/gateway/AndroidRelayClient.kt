package local.topolinoconnect.gateway

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.roundToInt

/** Optional Cloudflare relay used by the iOS app to read the Android ESP stream. */
object AndroidRelayClient {
    const val ENDPOINT = "https://topolino-gateway-relay.88doruk55.workers.dev"
    private const val PREFERENCES = "topolino_ios_relay"
    private const val ACCESS_KEY = "access_key"
    private const val ENABLED = "enabled"
    private const val POST_INTERVAL_MS = 1_000L

    private val random = SecureRandom()
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "topolino-ios-relay").apply { isDaemon = true }
    }
    private val gate = Any()
    private var lastQueuedAt = 0L
    private var pendingPayload: ByteArray? = null
    private var workerRunning = false

    fun accessKey(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        prefs.getString(ACCESS_KEY, null)?.let { return it }
        val bytes = ByteArray(32).also(random::nextBytes)
        val generated = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        prefs.edit().putString(ACCESS_KEY, generated).apply()
        return generated
    }

    // The Android gateway exists to forward this vehicle stream to iOS. Keep
    // forwarding enabled on first install while respecting an explicit opt-out.
    fun isEnabled(context: Context): Boolean = context.applicationContext
        .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(ENABLED, true)

    fun statusText(context: Context): String = if (isEnabled(context)) {
        GatewayRuntime.iosRelayStatus
    } else {
        "Kapalı · araç verisi Android’de kalıyor"
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(ENABLED, enabled).apply()
        GatewayRuntime.iosRelayStatus = if (enabled) "Açık · ESP verisi bekleniyor" else "iOS aktarımı kapalı"
    }

    fun publishIfEnabled(context: Context, can: JSONObject) {
        val appContext = context.applicationContext
        if (!isEnabled(appContext) || can.optBoolean("simulation", false)) return

        val now = android.os.SystemClock.elapsedRealtime()
        synchronized(gate) {
            if (now - lastQueuedAt < POST_INTERVAL_MS) return
            lastQueuedAt = now
            pendingPayload = buildEnvelope(can).toByteArray(Charsets.UTF_8)
            if (workerRunning) return
            workerRunning = true
            worker.execute { drainPending(appContext) }
        }
    }

    /** Sends unresolved raw frames too, using the relay's frame-only envelope shape. */
    fun publishRawFrameUpdate(context: Context) {
        val sample = GatewayRuntime.espCan?.let { JSONObject(it.toString()) } ?: JSONObject()
            .put("canLive", false)
            .put("source", "Android raw CAN frames")
        sample.put("timestamp", java.time.Instant.now().toString())
        publishIfEnabled(context, sample)
    }

    private fun buildEnvelope(can: JSONObject): String {
        val latestFrames = GatewayRuntime.canFrames
        val frameTail = JSONArray()
        for (i in 0 until min(10, latestFrames.length())) {
            latestFrames.optJSONObject(i)?.let { frameTail.put(JSONObject(it.toString())) }
        }

        val telemetry = JSONObject(can.toString())
        // These fields are Int in the iOS Codable model; normalize Android's
        // Double-backed snapshot values before sending the shared JSON packet.
        listOf("batteryPercent", "rangeKm", "temperature1C", "temperature2C").forEach { key ->
            if (!telemetry.isNull(key)) {
                telemetry.optDouble(key).takeIf { it.isFinite() }?.let { telemetry.put(key, it.roundToInt()) }
            }
        }
        // Speed stays on the Mac monitor; do not forward it from Android to iOS.
        telemetry.remove("speedKmh")
        telemetry.remove("sessionMaxSpeedKmh")
        telemetry.remove("sessionAverageSpeedKmh")
        telemetry
            .put("sessionTripDistanceKm", GatewayRuntime.sessionTripDistanceKm)
            .put("sessionEnergyOutKwh", GatewayRuntime.sessionEnergyOutKwh)
            .put("sessionEnergyInKwh", GatewayRuntime.sessionEnergyInKwh)
            .put("sessionRegenCandidateKwh", GatewayRuntime.sessionRegenCandidateKwh)
            .putNullable("sessionEstimatedDriveEnergyKwh", GatewayRuntime.sessionEstimatedDriveEnergyKwh)
            .putNullable("sessionEstimatedConsumptionKwhPer100Km", GatewayRuntime.sessionEstimatedConsumptionKwhPer100Km)
            .put("canFrameCount", GatewayRuntime.canFrameCount)
            .put("gattFrameStatus", GatewayRuntime.gattFrameStatus)
            .put("canFrames", frameTail)
        return JSONObject().put("espCan", telemetry).toString()
    }

    private fun drainPending(context: Context) {
        while (true) {
            val payload = synchronized(gate) {
                val next = pendingPayload
                pendingPayload = null
                if (next == null) workerRunning = false
                next
            } ?: return

            val result = post(context, payload)
            GatewayRuntime.iosRelayStatus = result
        }
    }

    private fun post(context: Context, payload: ByteArray): String {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$ENDPOINT/api/v1/vehicle/latest").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5_000
                readTimeout = 5_000
                doOutput = true
                useCaches = false
                setRequestProperty("X-Topolino-Key", accessKey(context))
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                setFixedLengthStreamingMode(payload.size)
            }
            connection.outputStream.use { it.write(payload) }
            val status = connection.responseCode
            if (status in 200..299) {
                runCatching { connection.inputStream.bufferedReader().use { it.readText() } }
                "iOS aktarımı canlı · Cloudflare rölesine gönderildi"
            } else {
                val detail = runCatching { connection.errorStream?.bufferedReader()?.use { it.readText() } }
                    .getOrNull()?.take(120).orEmpty()
                if (status == 401) "iOS aktarımı · erişim anahtarı reddedildi"
                else if (status == 400) {
                    val code = runCatching { JSONObject(detail).optString("error") }.getOrDefault("")
                    when (code) {
                        "invalid_request" -> "iOS aktarımı · röle CAN/araç paketi biçimini reddetti · Worker güncellemesi gerekli"
                        "invalid_vehicle_sample" -> "iOS aktarımı · bu pakette geçerli araç verisi veya CAN çerçevesi yok"
                        "payload_too_large" -> "iOS aktarımı · röle paketi çok büyük"
                        else -> "iOS aktarımı · röle HTTP 400${if (detail.isNotBlank()) " · $detail" else ""}"
                    }
                }
                else "iOS aktarımı · röle HTTP $status${if (detail.isNotBlank()) " · $detail" else ""}"
            }
        } catch (error: Exception) {
            "iOS aktarımı başarısız · ${error.localizedMessage ?: error.javaClass.simpleName}"
        } finally {
            connection?.disconnect()
        }
    }

    private fun JSONObject.putNullable(key: String, value: Any?): JSONObject = put(key, value ?: JSONObject.NULL)
}
