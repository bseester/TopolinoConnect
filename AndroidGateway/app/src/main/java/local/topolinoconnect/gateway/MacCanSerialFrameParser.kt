package local.topolinoconnect.gateway

import org.json.JSONObject
import java.time.Instant
/** Parses the exact CAN line format emitted by the Mac monitor's ESP32 firmware. */
data class MacCanSerialFrame(
    val identifier: Long,
    val extended: Boolean,
    val dlc: Int,
    val data: ByteArray,
    val timestampUs: Long?
)

object MacCanSerialFrameParser {
    private val framePattern = Regex("CAN (11|29)-bit ID=0x([0-9A-Fa-f]+) DLC=(\\d+) DATA=([0-9A-Fa-f ]*)(?: TS_US=(\\d+))?")

    fun parse(line: String): MacCanSerialFrame? {
        val match = framePattern.matchEntire(line.trim()) ?: return null
        val extended = match.groupValues[1] == "29"
        val identifier = match.groupValues[2].toLongOrNull(16) ?: return null
        val maxId = if (extended) 0x1fff_ffffL else 0x7ffL
        if (identifier !in 0..maxId) return null
        val dlc = match.groupValues[3].toIntOrNull()?.takeIf { it in 0..8 } ?: return null
        val data = match.groupValues[4].trim().split(Regex("\\s+")).filter(String::isNotBlank)
            .map { it.toIntOrNull(16)?.takeIf { value -> value in 0..255 } ?: return null }
        if (data.size != dlc) return null
        val timestampText = match.groupValues[5]
        val timestamp = if (timestampText.isEmpty()) null else {
            val value = timestampText.toLongOrNull() ?: return null
            value.takeIf { it in 0..0xffff_ffffL } ?: return null
        }
        return MacCanSerialFrame(identifier, extended, dlc, ByteArray(data.size) { data[it].toByte() }, timestamp)
    }

    /** Parses the same optional JSON telemetry line that the Mac monitor consumes. */
    fun decodeTelemetry(line: String, previous: VehicleSnapshot?): VehicleSnapshot? {
        if (!line.startsWith("{\"type\":\"telemetry\"")) return null
        val packet = runCatching { JSONObject(line) }.getOrNull() ?: return null
        if (packet.optString("type") != "telemetry") return null
        fun number(key: String): Double? = if (!packet.has(key) || packet.isNull(key)) null
            else packet.optDouble(key).takeIf(Double::isFinite)
        val current = number("current_a")
        val voltage = number("voltage_v")
        val soc = number("soc_pct")?.takeIf { it in 0.0..100.0 }
        val range = number("range_km")?.takeIf { it >= 0.0 }
        val readyRaw = number("ready")?.toInt()
        val ready = when (readyRaw) { 1 -> true; 0 -> false; else -> null }
        val readyText = when (ready) { true -> "Hazır"; false -> "Hazır değil"; null -> null }
        val minutes = number("remaining_min")?.toInt()?.takeIf { it in 0..600 }
        val temp1 = number("temp1_c")?.takeIf { it > -90.0 }
        val temp2 = number("temp2_c")?.takeIf { it > -90.0 }
        val patch = VehicleSnapshot(
            canLive = packet.optBoolean("can", false),
            speedKmh = number("speed_kmh")?.takeIf { it >= 0.0 },
            odometerKm = number("odometer_km")?.takeIf { it >= 0.0 },
            batteryPercent = soc,
            rangeKm = range,
            voltageV = voltage,
            currentA = current,
            batteryPowerKw = if (voltage != null && current != null) -voltage * current / 1000.0 else null,
            battery12V = number("battery_12v")?.takeIf { it >= 0.0 },
            temperature1C = temp1,
            temperature2C = temp2,
            gear = packet.optString("gear").takeIf { it.isNotBlank() && it != "?" && it != "null" },
            ready = ready,
            handbrake = number("handbrake")?.takeIf { it == 0.0 || it == 1.0 }?.let { it == 1.0 },
            charging = if (minutes != null) current?.let { it > 0.0 } else null,
            chargeMinutesRemaining = minutes,
            source = "ESP USB serial telemetry",
            readyStateText = readyText,
            timestamp = Instant.now().toString()
        )
        return previous?.merge(patch) ?: patch
    }
}
