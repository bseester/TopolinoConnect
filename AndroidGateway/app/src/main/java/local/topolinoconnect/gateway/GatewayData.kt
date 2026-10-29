package local.topolinoconnect.gateway

import org.json.JSONObject
import org.json.JSONArray
import java.time.Duration
import java.time.Instant

object GatewayRuntime {
    @Volatile var lastTelemetryAt: String? = null
    @Volatile var espCan: JSONObject? = null
    @Volatile var vehicleSnapshot: VehicleSnapshot? = null
    @Volatile var espCanAt: String? = null
    @Volatile var status: String = "Henüz tarama başlatılmadı"
    @Volatile var espCanRssi: Int? = null
    @Volatile var gattFrameStatus: String = "CAN çerçeve yayını bekleniyor"
    @Volatile var iosRelayStatus: String = "Açık · ESP verisi bekleniyor"
    @Volatile var canFrameCount: Long = 0
    @Volatile var resolvedFrameCount: Long = 0
    @Volatile var unresolvedFrameCount: Long = 0
    @Volatile var canFrameLogPath: String = ""
    @Volatile var canFrames: JSONArray = JSONArray()
    @Volatile var sessionTripDistanceKm = 0.0
    @Volatile var sessionMaxSpeedKmh: Double? = null
    @Volatile var sessionAverageSpeedKmh: Double? = null
    @Volatile var sessionEnergyOutKwh = 0.0
    @Volatile var sessionEnergyInKwh = 0.0
    @Volatile var sessionRegenCandidateKwh = 0.0
    @Volatile var sessionEstimatedDriveEnergyKwh: Double? = null
    @Volatile var sessionEstimatedConsumptionKwhPer100Km: Double? = null

    private var lastSessionOdometerKm: Double? = null
    private var sessionSpeedIntegral = 0.0
    private var sessionSpeedSeconds = 0.0
    private var lastPowerFrameAtMs: Long? = null
    private var lastSpeedFrameAtMs: Long? = null
    private var smoothedCanPowerKw: Double? = null
    private var estimatedTripActive = false
    private var estimatedTripStartOdometerKm: Double? = null
    private var estimatedTripStartSoc: Double? = null

    @Synchronized
    fun acceptCanSample(sample: JSONObject, nowMs: Long = System.currentTimeMillis()) {
        val odometer = sample.optFiniteDouble("odometerKm")
        val speed = sample.optFiniteDouble("speedKmh")
        val isPackFrame = sample.optString("source").endsWith("0x580")
        val isSpeedFrame = sample.optString("source").endsWith("0x581")
        val rawPowerKw = sample.optFiniteDouble("batteryPowerKw")
        val powerKw = if (isPackFrame && sample.optBoolean("powerSampleFresh") && rawPowerKw != null) {
            smoothedCanPowerKw = smoothedCanPowerKw?.let { 0.2 * it + 0.8 * rawPowerKw } ?: rawPowerKw
            sample.put("batteryPowerKw", smoothedCanPowerKw)
            smoothedCanPowerKw
        } else rawPowerKw
        val previousOdometer = lastSessionOdometerKm
        if (odometer != null && previousOdometer != null) {
            val delta = odometer - previousOdometer
            if (delta in 0.0..0.5) sessionTripDistanceKm += delta
        }
        if (odometer != null) lastSessionOdometerKm = odometer
        if (speed != null) sessionMaxSpeedKmh = maxOf(sessionMaxSpeedKmh ?: speed, speed)

        val ready = sample.optBoolean("ready", false) && !sample.isNull("ready")
        if (ready && !estimatedTripActive) {
            estimatedTripActive = true
            estimatedTripStartOdometerKm = odometer
            estimatedTripStartSoc = sample.optFiniteDouble("batteryPercent")
            sessionEstimatedDriveEnergyKwh = null
            sessionEstimatedConsumptionKwhPer100Km = null
        } else if (!ready) {
            estimatedTripActive = false
        }
        if (ready) {
            if (estimatedTripStartOdometerKm == null) estimatedTripStartOdometerKm = odometer
            if (estimatedTripStartSoc == null) estimatedTripStartSoc = sample.optFiniteDouble("batteryPercent")
            val startSoc = estimatedTripStartSoc
            val soc = sample.optFiniteDouble("batteryPercent")
            val startOdometer = estimatedTripStartOdometerKm
            if (startSoc != null && soc != null) {
                sessionEstimatedDriveEnergyKwh = ((startSoc - soc).coerceAtLeast(0.0)) * 0.06
            }
            if (startOdometer != null && odometer != null && sessionEstimatedDriveEnergyKwh != null) {
                val distance = odometer - startOdometer
                if (distance >= 0.1) sessionEstimatedConsumptionKwhPer100Km = sessionEstimatedDriveEnergyKwh!! / distance * 100.0
            }
        }

        if (isSpeedFrame && speed != null) {
            lastSpeedFrameAtMs?.let { previousAt ->
                val elapsedSeconds = ((nowMs - previousAt).coerceIn(0L, 2_000L)) / 1_000.0
                if (elapsedSeconds > 0) {
                    sessionSpeedIntegral += speed * elapsedSeconds
                    sessionSpeedSeconds += elapsedSeconds
                    sessionAverageSpeedKmh = sessionSpeedIntegral / sessionSpeedSeconds
                }
            }
            lastSpeedFrameAtMs = nowMs
        }
        if (isPackFrame && powerKw != null) {
            lastPowerFrameAtMs?.let { previousAt ->
                val elapsedSeconds = ((nowMs - previousAt).coerceIn(0L, 2_000L)) / 1_000.0
                if (elapsedSeconds > 0) {
                    val energyKwh = powerKw * elapsedSeconds / 3_600.0
                    if (energyKwh >= 0) sessionEnergyOutKwh += energyKwh else {
                        sessionEnergyInKwh += -energyKwh
                        if ((speed ?: 0.0) > 0.5) sessionRegenCandidateKwh += -energyKwh
                    }
                }
            }
            lastPowerFrameAtMs = nowMs
        }
    }

    @Synchronized
    fun addCanFrame(frame: JSONObject, resolved: Boolean) {
        canFrameCount += 1
        if (resolved) resolvedFrameCount += 1 else unresolvedFrameCount += 1
        frame.put("resolved", resolved)
        val next = JSONArray()
        next.put(frame)
        val limit = 120
        val previous = canFrames
        for (index in 0 until minOf(previous.length(), limit - 1)) {
            previous.optJSONObject(index)?.let { next.put(JSONObject(it.toString())) }
        }
        canFrames = next
    }

    @Synchronized
    fun resetSessionMetrics() {
        sessionTripDistanceKm = 0.0
        sessionMaxSpeedKmh = null
        sessionAverageSpeedKmh = null
        sessionEnergyOutKwh = 0.0
        sessionEnergyInKwh = 0.0
        sessionRegenCandidateKwh = 0.0
        sessionEstimatedDriveEnergyKwh = null
        sessionEstimatedConsumptionKwhPer100Km = null
        sessionSpeedIntegral = 0.0
        sessionSpeedSeconds = 0.0
        lastPowerFrameAtMs = null
        lastSpeedFrameAtMs = null
        smoothedCanPowerKw = null
        lastSessionOdometerKm = espCan?.optFiniteDouble("odometerKm")
        estimatedTripActive = false
        estimatedTripStartOdometerKm = null
        estimatedTripStartSoc = null
    }

    fun hasFreshTelemetry(): Boolean {
        val sample = espCan
        val hasVehicleData = sample?.optBoolean("canLive", true) == true
        val hasChargeData = sample?.has("charging") == true && !sample.isNull("charging")
        return (hasVehicleData || hasChargeData) && lastTelemetryAt?.let { timestamp ->
            runCatching {
                val age = Duration.between(Instant.parse(timestamp), Instant.now()).toMillis()
                age in -3_000..LIVE_DATA_MAX_AGE_MS
            }.getOrDefault(false)
        } ?: false
    }

    private const val LIVE_DATA_MAX_AGE_MS = 45_000L
}

private fun JSONObject.optFiniteDouble(key: String): Double? =
    if (!has(key) || isNull(key)) null else optDouble(key).takeIf { it.isFinite() }
