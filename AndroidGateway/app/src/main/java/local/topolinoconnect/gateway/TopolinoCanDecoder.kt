package local.topolinoconnect.gateway

import java.time.Instant

/** Decodes ESP advertisements and raw CAN using AmiTopolinoMacCAN's AmiCANDecoder mappings. */
object TopolinoCanDecoder {
    fun decodeAdvertisement(bytes: ByteArray): VehicleSnapshot? {
        val wireVersion = bytes.firstOrNull()?.toInt()?.and(0xff) ?: return null
        val simulation = (wireVersion and 0x80) != 0
        val version = wireVersion and 0x7f
        if ((version == 1 && bytes.size != 20) || (version in 2..4 && bytes.size != 24) || version !in 1..4) return null
        fun u8(i: Int) = bytes[i].toInt() and 0xff
        fun u16(i: Int) = (u8(i) shl 8) or u8(i + 1)
        fun u32(i: Int) = (u8(i).toLong() shl 24) or (u8(i + 1).toLong() shl 16) or
            (u8(i + 2).toLong() shl 8) or u8(i + 3).toLong()
        val speed = u8(1).takeUnless { it == 255 }?.toDouble()
        val odometer = u32(2).takeUnless { it == 0xffffffffL }?.div(10.0)
        val soc = u8(6).takeIf { it <= 100 }?.toDouble()
        val range = u16(7).takeUnless { it == 0xffff }?.toDouble()
        val voltage = u16(9).takeUnless { it == 0xffff }?.div(10.0)
        val currentWord = u16(11)
        val current = if (currentWord == 0x8000) null else (if (currentWord >= 0x8000) currentWord - 0x10000 else currentWord) / 10.0
        val temp1 = bytes[15].toInt().takeUnless { it == -99 }?.toDouble()
        val temp2 = bytes[16].toInt().takeUnless { it == -99 }?.toDouble()
        val gear = when (u8(17)) { 0 -> "R"; 1 -> "N"; 2 -> "D"; else -> null }
        val canLive = version < 3 || listOf(
            speed, odometer, soc, range, voltage, current, temp1, temp2, gear,
            u16(13).takeUnless { it == 0xffff }, u8(18).takeUnless { it == 255 },
            u8(19).takeUnless { it == 255 }
        ).any { it != null }
        val chargeState = if (version >= 2) u8(20) else 255
        val chargeMinutes = if (version >= 2) u16(21).takeUnless { it == 0xffff } else null
        val chargePower = if (version >= 2) u8(23).takeUnless { it == 255 }?.div(10.0) else null
        return VehicleSnapshot(
            canLive = canLive,
            speedKmh = speed,
            odometerKm = odometer,
            batteryPercent = soc,
            rangeKm = range,
            voltageV = voltage,
            currentA = current,
            batteryPowerKw = if (voltage != null && current != null) -voltage * current / 1000.0 else null,
            battery12V = u16(13).takeUnless { it == 0xffff }?.div(10.0),
            temperature1C = temp1,
            temperature2C = temp2,
            gear = gear,
            ready = u8(18).takeUnless { it == 255 }?.let { it == 1 },
            handbrake = u8(19).takeUnless { it == 255 }?.let { it == 1 },
            charging = chargeState.takeUnless { it == 255 }?.let { it == 1 },
            chargeMinutesRemaining = chargeMinutes,
            chargePowerKw = chargePower,
            simulation = simulation,
            source = if (simulation) "ESP SIMÜLASYON TESTİ · FDE0 v$version" else "Topolino ESP CAN BLE · FDE0 v$version"
        )
    }

    fun decodeFrame(identifier: Long, data: ByteArray, previous: VehicleSnapshot?, extended: Boolean = false): VehicleSnapshot? {
        if (extended) return null
        if (data.size < 2) return null
        fun u8(i: Int) = data[i].toInt() and 0xff
        fun u16le(i: Int) = u8(i) or (u8(i + 1) shl 8)
        fun i16le(i: Int): Int = u16le(i).let { if (it >= 0x8000) it - 0x10000 else it }
        val patch = when (identifier) {
            0x580L -> {
                if (data.size != 8) return null
                val currentRaw = i16le(0)
                val current = currentRaw.takeUnless { it == -1 }?.div(10.0)
                val currentUnsigned = u16le(0)
                val dbcCurrentCandidate = currentUnsigned * 0.1 - 6553.5
                val rawVoltage = u16le(2)
                val voltage = rawVoltage.takeIf { it != 0xffff && it <= 8000 }?.div(100.0)
                VehicleSnapshot(
                    canLive = true,
                    currentA = current,
                    currentDbcCandidateA = dbcCurrentCandidate.takeIf { it.isFinite() && kotlin.math.abs(it) <= 700 },
                    voltageV = voltage,
                    powerSampleFresh = voltage != null && current != null,
                    // B5 is a verified SOC candidate only for B6=0x13.
                    // Charging layouts (B6=0x36/0x6C) use different fields.
                    batteryPercent = if (u8(6) == 0x13) u8(5).takeIf { it <= 100 }?.toDouble() else null,
                    batteryPowerKw = if (voltage != null && current != null) -voltage * current / 1000.0 else null,
                    source = "Android raw CAN · 0x580"
                )
            }
            0x581L -> {
                if (data.size != 8) return null
                val odometerTenths = u8(4).toLong() or (u8(5).toLong() shl 8) or (u8(6).toLong() shl 16)
                VehicleSnapshot(canLive = true,
                    odometerKm = odometerTenths.takeUnless { it == 0x00ff_ffffL }?.div(10.0),
                    speedKmh = u8(7).takeUnless { it == 0xff }?.toDouble(), source = "Android raw CAN · 0x581")
            }
            0x582L -> {
                if (data.size != 8) return null
                val rawSeconds = u16le(0)
                val minutes = rawSeconds.takeIf { it <= 36_000 }?.div(60)
                val current = previous?.currentA
                val voltage = previous?.voltageV
                VehicleSnapshot(canLive = true, charging = current?.let { it > 0 },
                    chargeMinutesRemaining = minutes,
                    chargeTimeRawDbc = rawSeconds,
                    chargePowerKw = if (current != null && voltage != null && current > 0) current * voltage / 1000.0 else null,
                    source = "Android raw CAN · 0x582")
            }
            0x593L -> {
                if (data.size != 8) return null
                val rawVoltage = u16le(0)
                VehicleSnapshot(canLive = true,
                    battery12V = rawVoltage.takeIf { it != 0xffff && it <= 2000 }?.div(100.0),
                    battery12VDbcCandidate = rawVoltage.takeUnless { it == 0xffff }?.toDouble(),
                    source = "Android raw CAN · 0x593")
            }
            0x594L -> {
                if (data.size < 4) return null
                if (data.size != 8) return null
                VehicleSnapshot(canLive = true, temperature1C = data[0].toByte().toInt().toDouble(),
                    temperature2C = data[3].toInt().toByte().toInt().toDouble(),
                    temperature1DbcRaw = u16le(0), temperature2DbcRaw = u16le(3),
                    source = "Android raw CAN · 0x594")
            }
            0x713L -> {
                if (data.size != 7) return null
                val gearIndex = (((u8(1) and 1) shl 1) or ((u8(0) ushr 7) and 1))
                val readyBits = u8(2) and 7
                val ready = (u8(2) and 0x04) != 0
                val range = (u8(0) and 0x7f).takeIf { it < 0x7f }?.toDouble()
                val readyValue = when (readyBits) { 0b101 -> true; 0b011 -> false; else -> null }
                val readyText = when (readyValue) { true -> "Hazır"; false -> "Hazır değil"; null -> "Belirsiz ($readyBits)" }
                VehicleSnapshot(canLive = true, gear = if (ready) arrayOf("R", "N", "D", "—")[gearIndex] else "—",
                    rangeKm = range,
                    ready = readyValue,
                    readyStateText = readyText,
                    handbrake = ((u8(3) ushr 5) and 1) == 1,
                    source = "Android raw CAN · 0x713")
            }
            0x714L -> {
                if (data.size != 2) return null
                val value = u8(0)
                VehicleSnapshot(canLive = true, handbrake = value == 1, source = "Android raw CAN · 0x714")
            }
            else -> return null
        }.copy(timestamp = Instant.now().toString())
        return previous?.merge(patch) ?: patch
    }
}
