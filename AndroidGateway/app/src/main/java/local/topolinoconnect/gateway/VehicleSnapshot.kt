package local.topolinoconnect.gateway

import org.json.JSONObject
import java.time.Instant

/** One normalized vehicle state shared by BLE, the dashboard, history and phone API. */
data class VehicleSnapshot(
    val canLive: Boolean = false,
    val speedKmh: Double? = null,
    val odometerKm: Double? = null,
    val batteryPercent: Double? = null,
    val rangeKm: Double? = null,
    val voltageV: Double? = null,
    val currentA: Double? = null,
    val currentDbcCandidateA: Double? = null,
    val batteryPowerKw: Double? = null,
    val powerSampleFresh: Boolean = false,
    val battery12V: Double? = null,
    val battery12VDbcCandidate: Double? = null,
    val temperature1C: Double? = null,
    val temperature2C: Double? = null,
    val temperature1DbcRaw: Int? = null,
    val temperature2DbcRaw: Int? = null,
    val gear: String? = null,
    val ready: Boolean? = null,
    val handbrake: Boolean? = null,
    val charging: Boolean? = null,
    val chargeMinutesRemaining: Int? = null,
    val chargeTimeRawDbc: Int? = null,
    val chargePowerKw: Double? = null,
    val simulation: Boolean = false,
    val source: String = "Topolino ESP CAN BLE",
    val readyStateText: String? = null,
    val timestamp: String = Instant.now().toString()
) {
    /** Only non-null fields from a newer CAN frame replace the previous known value. */
    fun merge(newer: VehicleSnapshot): VehicleSnapshot = copy(
        canLive = canLive || newer.canLive,
        speedKmh = newer.speedKmh ?: speedKmh,
        odometerKm = newer.odometerKm ?: odometerKm,
        batteryPercent = newer.batteryPercent ?: batteryPercent,
        rangeKm = newer.rangeKm ?: rangeKm,
        voltageV = newer.voltageV ?: voltageV,
        currentA = newer.currentA ?: currentA,
        currentDbcCandidateA = newer.currentDbcCandidateA ?: currentDbcCandidateA,
        batteryPowerKw = newer.batteryPowerKw ?: batteryPowerKw,
        powerSampleFresh = newer.powerSampleFresh,
        battery12V = newer.battery12V ?: battery12V,
        battery12VDbcCandidate = newer.battery12VDbcCandidate ?: battery12VDbcCandidate,
        temperature1C = newer.temperature1C ?: temperature1C,
        temperature2C = newer.temperature2C ?: temperature2C,
        temperature1DbcRaw = newer.temperature1DbcRaw ?: temperature1DbcRaw,
        temperature2DbcRaw = newer.temperature2DbcRaw ?: temperature2DbcRaw,
        gear = newer.gear ?: gear,
        ready = newer.ready ?: ready,
        handbrake = newer.handbrake ?: handbrake,
        charging = newer.charging ?: charging,
        chargeMinutesRemaining = newer.chargeMinutesRemaining ?: chargeMinutesRemaining,
        chargeTimeRawDbc = newer.chargeTimeRawDbc ?: chargeTimeRawDbc,
        chargePowerKw = newer.chargePowerKw ?: chargePowerKw,
        simulation = newer.simulation,
        source = newer.source,
        readyStateText = newer.readyStateText ?: readyStateText,
        timestamp = newer.timestamp
    )

    fun toJson(): JSONObject = JSONObject()
        .put("canLive", canLive)
        .putNullable("speedKmh", speedKmh)
        .putNullable("odometerKm", odometerKm)
        .putNullable("batteryPercent", batteryPercent)
        .putNullable("rangeKm", rangeKm)
        .putNullable("remainingRangeKm", rangeKm)
        .putNullable("voltageV", voltageV)
        .putNullable("currentA", currentA)
        .putNullable("currentDbcCandidateA", currentDbcCandidateA)
        .putNullable("batteryPowerKw", batteryPowerKw)
        .put("powerSampleFresh", powerSampleFresh)
        .putNullable("battery12V", battery12V)
        .putNullable("battery12VDbcCandidate", battery12VDbcCandidate)
        .putNullable("temperature1C", temperature1C)
        .putNullable("temperature2C", temperature2C)
        .putNullable("temperature1DbcRaw", temperature1DbcRaw)
        .putNullable("temperature2DbcRaw", temperature2DbcRaw)
        .putNullable("gear", gear)
        .putNullable("ready", ready)
        .putNullable("handbrake", handbrake)
        .putNullable("charging", charging)
        .putNullable("chargeMinutesRemaining", chargeMinutesRemaining)
        .putNullable("chargeTimeRawDbc", chargeTimeRawDbc)
        .putNullable("chargePowerKw", chargePowerKw)
        .put("simulation", simulation)
        .put("source", source)
        .putNullable("readyStateText", readyStateText)
        .put("timestamp", timestamp)

    companion object {
        fun fromJson(json: JSONObject): VehicleSnapshot = VehicleSnapshot(
            canLive = json.optBoolean("canLive", true),
            speedKmh = json.numberOrNull("speedKmh"),
            odometerKm = json.numberOrNull("odometerKm"),
            batteryPercent = json.numberOrNull("batteryPercent"),
            rangeKm = json.numberOrNull("rangeKm"),
            voltageV = json.numberOrNull("voltageV"),
            currentA = json.numberOrNull("currentA"),
            currentDbcCandidateA = json.numberOrNull("currentDbcCandidateA"),
            batteryPowerKw = json.numberOrNull("batteryPowerKw"),
            powerSampleFresh = json.optBoolean("powerSampleFresh", false),
            battery12V = json.numberOrNull("battery12V"),
            battery12VDbcCandidate = json.numberOrNull("battery12VDbcCandidate"),
            temperature1C = json.numberOrNull("temperature1C"),
            temperature2C = json.numberOrNull("temperature2C"),
            temperature1DbcRaw = json.numberOrNull("temperature1DbcRaw")?.toInt(),
            temperature2DbcRaw = json.numberOrNull("temperature2DbcRaw")?.toInt(),
            gear = json.stringOrNull("gear"),
            ready = json.booleanOrNull("ready"),
            handbrake = json.booleanOrNull("handbrake"),
            charging = json.booleanOrNull("charging"),
            chargeMinutesRemaining = json.numberOrNull("chargeMinutesRemaining")?.toInt(),
            chargeTimeRawDbc = json.numberOrNull("chargeTimeRawDbc")?.toInt(),
            chargePowerKw = json.numberOrNull("chargePowerKw"),
            simulation = json.optBoolean("simulation", false),
            source = json.optString("source", "Topolino ESP CAN BLE"),
            readyStateText = json.stringOrNull("readyStateText"),
            timestamp = json.optString("timestamp", Instant.now().toString())
        )
    }
}

private fun JSONObject.putNullable(key: String, value: Any?): JSONObject = put(key, value ?: JSONObject.NULL)
private fun JSONObject.numberOrNull(key: String): Double? =
    if (!has(key) || isNull(key)) null else optDouble(key).takeIf(Double::isFinite)
private fun JSONObject.stringOrNull(key: String): String? =
    if (!has(key) || isNull(key)) null else optString(key).takeIf { it.isNotBlank() && it != "null" }
private fun JSONObject.booleanOrNull(key: String): Boolean? =
    if (!has(key) || isNull(key)) null else optBoolean(key)
