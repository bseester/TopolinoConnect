package local.topolinoconnect.gateway

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/** Persists a verified ESP SOC sample so the dashboard can estimate range offline. */
object ClassicRangeEstimateStore {
    data class Estimate(
        val batteryPercent: Double,
        val rangeKm: Double,
        val minutesRemaining: Int?,
        val sourceTimestampMs: Long
    ) {
        val ageMinutes: Int
            get() = max(0, ((System.currentTimeMillis() - sourceTimestampMs) / 60_000L).toInt())
    }

    private const val PREFERENCES = "topolino_classic_range"
    private const val SAMPLE_KEY = "last_verified_esp_soc"
    private const val MAX_CAPTURE_AGE_MS = 24L * 60 * 60 * 1_000
    private val seedWorker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "topolino-range-seed").apply { isDaemon = true }
    }
    @Volatile private var seedStarted = false

    @Synchronized
    fun initialize(context: Context) {
        if (seedStarted) return
        seedStarted = true
        val app = context.applicationContext
        seedWorker.execute { seedFromCapturesIfNeeded(app) }
    }

    @Synchronized
    fun capture(context: Context, sample: VehicleSnapshot, trustedBatteryPercent: Boolean) {
        if (sample.simulation) return
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val previous = read(prefs.getString(SAMPLE_KEY, null))

        if (!trustedBatteryPercent || sample.batteryPercent == null) {
            if (sample.charging == false && previous?.charging == true) {
                val stopped = previous.json().put("charging", false).put("chargeMinutesRemaining", JSONObject.NULL)
                prefs.edit().putString(SAMPLE_KEY, stopped.toString()).apply()
            }
            return
        }

        val now = System.currentTimeMillis()
        val soc = sample.batteryPercent.coerceIn(0.0, 100.0)
        val charging = sample.charging == true
        val minutes = sample.chargeMinutesRemaining?.coerceIn(0, 600)
        val unchanged = previous != null &&
            kotlin.math.abs(previous.batteryPercent - soc) < 0.5 &&
            previous.charging == charging && previous.minutesRemaining == minutes
        if (unchanged && now - previous!!.timestampMs < 60_000L) return

        val saved = JSONObject()
            .put("batteryPercent", soc)
            .put("timestampMs", now)
            .put("charging", charging)
            .put("chargeMinutesRemaining", minutes ?: JSONObject.NULL)
        prefs.edit().putString(SAMPLE_KEY, saved.toString()).apply()
    }

    fun estimate(context: Context, nowMs: Long = System.currentTimeMillis()): Estimate? {
        val prefs = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val sample = read(prefs.getString(SAMPLE_KEY, null)) ?: return null
        val initialMinutes = sample.minutesRemaining?.takeIf { sample.charging && it > 0 }
        val elapsed = initialMinutes?.let {
            min(it.toDouble(), max(0.0, (nowMs - sample.timestampMs) / 60_000.0))
        } ?: 0.0
        val soc = initialMinutes?.let {
            min(100.0, sample.batteryPercent + (100.0 - sample.batteryPercent) * elapsed / it)
        } ?: sample.batteryPercent
        val remaining = initialMinutes?.let { max(0, it - elapsed.toInt()) }
        // Match the established Topolino classic estimate: 27% ≈ 18 km,
        // then scale linearly using the observed 27% / 18 km reference point.
        val range = max(0.0, 18.0 + (soc - 27.0) * (11.0 / 14.0))
        return Estimate(soc, range, remaining, sample.timestampMs)
    }

    private fun seedFromCapturesIfNeeded(context: Context) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (read(prefs.getString(SAMPLE_KEY, null)) != null) return
        val now = System.currentTimeMillis()
        var latest: SavedSample? = null
        val captures = File(context.filesDir, "captures")
        captures.listFiles()?.filter { it.isFile && it.extension == "jsonl" }
            ?.sortedBy { it.lastModified() }
            ?.forEach { file ->
                runCatching {
                    file.useLines { lines ->
                        lines.forEach { line ->
                            runCatching {
                                val frame = JSONObject(line)
                                if (frame.optString("id") != "0x580" || frame.optBoolean("simulation")) return@runCatching
                                val bytes = frame.optString("data").trim().split(Regex("\\s+"))
                                    .mapNotNull { it.toIntOrNull(16) }
                                if (bytes.size != 8 || bytes[6] != 0x13 || bytes[5] !in 0..100) return@runCatching
                                val timestamp = runCatching { Instant.parse(frame.optString("timestamp")).toEpochMilli() }
                                    .getOrElse { file.lastModified() }
                                if (now - timestamp !in 0..MAX_CAPTURE_AGE_MS) return@runCatching
                                if (latest == null || timestamp > latest!!.timestampMs) {
                                    latest = SavedSample(bytes[5].toDouble(), timestamp, false, null)
                                }
                            }
                        }
                    }
                }
            }
        latest?.let { prefs.edit().putString(SAMPLE_KEY, it.json().toString()).apply() }
    }

    private data class SavedSample(
        val batteryPercent: Double,
        val timestampMs: Long,
        val charging: Boolean,
        val minutesRemaining: Int?
    ) {
        fun json() = JSONObject()
            .put("batteryPercent", batteryPercent)
            .put("timestampMs", timestampMs)
            .put("charging", charging)
            .put("chargeMinutesRemaining", minutesRemaining ?: JSONObject.NULL)
    }

    private fun read(json: String?): SavedSample? = runCatching {
        val value = JSONObject(json ?: return null)
        SavedSample(
            batteryPercent = value.getDouble("batteryPercent").coerceIn(0.0, 100.0),
            timestampMs = value.getLong("timestampMs"),
            charging = value.optBoolean("charging"),
            minutesRemaining = if (value.isNull("chargeMinutesRemaining")) null
                else value.optInt("chargeMinutesRemaining").coerceIn(0, 600)
        )
    }.getOrNull()
}
