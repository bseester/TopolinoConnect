package local.topolinoconnect.gateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TopolinoCanDecoderTest {
    @Test fun usbLineAccumulatorReassemblesPartialAndMultipleReads() {
        val accumulator = SerialLineAccumulator()
        assertEquals(emptyList<String>(), accumulator.append("CAN 11-bit ID=0x581 ".toByteArray()))
        assertEquals(listOf("CAN 11-bit ID=0x581 DLC=8", "{\"type\":\"telemetry\"}"),
            accumulator.append("DLC=8\n{\"type\":\"telemetry\"}\n".toByteArray()))
    }

    @Test fun usbLineAccumulatorDropsOversizedLineButRecoversAtNewline() {
        val accumulator = SerialLineAccumulator(maxLineLength = 8)
        assertEquals(emptyList<String>(), accumulator.append("123456789bad\n".toByteArray()))
        assertEquals(listOf("OK"), accumulator.append("OK\n".toByteArray()))
    }

    @Test fun packFrameUsesMacLayoutAndVerifiedSocMarker() {
        val frame = bytes(0xD8, 0xFE, 0x58, 0x1B, 0, 78, 0x13, 0)
        val decoded = TopolinoCanDecoder.decodeFrame(0x580, frame, null)!!
        assertEquals(-29.6, decoded.currentA!!, 0.001)
        assertEquals(70.0, decoded.voltageV!!, 0.001)
        assertEquals(78.0, decoded.batteryPercent!!, 0.001)
        assertEquals("Android raw CAN · 0x580", decoded.source)

        val chargingLayout = bytes(0xD8, 0xFE, 0x58, 0x1B, 0, 0, 0x36, 0)
        assertNull(TopolinoCanDecoder.decodeFrame(0x580, chargingLayout, null)!!.batteryPercent)
        val unavailable = TopolinoCanDecoder.decodeFrame(0x580, bytes(0xFF, 0xFF, 0xFF, 0xFF, 0, 55, 0x13, 0), null)!!
        assertNull(unavailable.currentA)
        assertNull(unavailable.voltageV)
        assertFalse(unavailable.powerSampleFresh)
    }

    @Test fun odometerAndSpeedUnavailableSentinelsStayNull() {
        val decoded = TopolinoCanDecoder.decodeFrame(0x581, bytes(0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF), null)!!
        assertNull(decoded.odometerKm)
        assertNull(decoded.speedKmh)
    }

    @Test fun chargeTimeKeepsRawValueButRejectsOutOfRangeMinuteCandidate() {
        val valid = TopolinoCanDecoder.decodeFrame(0x582, bytes(0x08, 0x07, 0, 0, 0, 0, 0, 0), null)!!
        assertEquals(1800, valid.chargeTimeRawDbc)
        assertEquals(30, valid.chargeMinutesRemaining)
        val unavailable = TopolinoCanDecoder.decodeFrame(0x582, bytes(0xFF, 0xFF, 0, 0, 0, 0, 0, 0), null)!!
        assertEquals(65535, unavailable.chargeTimeRawDbc)
        assertNull(unavailable.chargeMinutesRemaining)
    }

    @Test fun temperaturesUseSignedBytesAndExposeDbcRawWords() {
        val decoded = TopolinoCanDecoder.decodeFrame(0x594, bytes(0xFE, 0, 0, 0x80, 0, 0, 0, 0), null)!!
        assertEquals(-2.0, decoded.temperature1C!!, 0.001)
        assertEquals(-128.0, decoded.temperature2C!!, 0.001)
        assertEquals(0x00FE, decoded.temperature1DbcRaw)
        assertEquals(0x0080, decoded.temperature2DbcRaw)
    }

    @Test fun gearRequiresReadyBitAndRangeUsesMacSevenBitField() {
        val ready = TopolinoCanDecoder.decodeFrame(0x713, bytes(58, 1, 5, 0x20, 0, 0, 0), null)!!
        assertEquals("D", ready.gear)
        assertEquals(58.0, ready.rangeKm!!, 0.001)
        assertEquals(true, ready.ready)
        assertEquals(true, ready.handbrake)

        val unknown = TopolinoCanDecoder.decodeFrame(0x713, bytes(0xFF, 0, 2, 0, 0, 0, 0), null)!!
        assertEquals("—", unknown.gear)
        assertNull(unknown.rangeKm)
        assertNull(unknown.ready)
        assertTrue(unknown.readyStateText!!.startsWith("Belirsiz"))
    }

    @Test fun unknownIdentifiersAndWrongDlcAreNotDecoded() {
        assertNull(TopolinoCanDecoder.decodeFrame(0x123, bytes(1, 2, 3, 4, 5, 6, 7, 8), null))
        assertNull(TopolinoCanDecoder.decodeFrame(0x580, bytes(1, 2, 3, 4, 5, 6, 0x13, 8), null, extended = true))
        assertNull(TopolinoCanDecoder.decodeFrame(0x580, bytes(1, 2, 3), null))
        val parking = TopolinoCanDecoder.decodeFrame(0x714, bytes(1, 0), null)!!
        assertTrue(parking.handbrake!!)
        val unset = TopolinoCanDecoder.decodeFrame(0x714, bytes(2, 0), null)!!
        assertFalse(unset.handbrake!!)
    }

    @Test fun usbParserAcceptsMacMonitorFormatAndRejectsMalformedRows() {
        val parsed = MacCanSerialFrameParser.parse("CAN 11-bit ID=0x580 DLC=8 DATA=D8 FE 58 1B 00 4E 13 00 TS_US=4294967295")!!
        assertEquals(0x580L, parsed.identifier)
        assertFalse(parsed.extended)
        assertEquals(8, parsed.dlc)
        assertEquals(0xD8.toByte(), parsed.data[0])
        assertEquals(4_294_967_295L, parsed.timestampUs)
        assertTrue(MacCanSerialFrameParser.parse("CAN 11-bit ID=0x800 DLC=1 DATA=00") == null)
        assertTrue(MacCanSerialFrameParser.parse("CAN 11-bit ID=0x580 DLC=2 DATA=00") == null)
        assertTrue(MacCanSerialFrameParser.parse("CAN 29-bit ID=0x20000000 DLC=0 DATA=") == null)
        assertTrue(MacCanSerialFrameParser.parse("CAN 11-bit ID=0x580 DLC=0 DATA= TS_US=4294967296") == null)
    }

    @Test fun usbParserHandlesMacTelemetryAndInvalidSentinels() {
        val decoded = MacCanSerialFrameParser.decodeTelemetry(
            "{\"type\":\"telemetry\",\"can\":true,\"frames\":7,\"speed_kmh\":25,\"odometer_km\":12.3,\"soc_pct\":78,\"range_km\":58,\"voltage_v\":70,\"current_a\":-29.6,\"battery_12v\":12.6,\"temp1_c\":29,\"temp2_c\":31,\"remaining_min\":30,\"gear\":\"D\",\"ready\":1,\"handbrake\":0}",
            null
        )!!
        assertTrue(decoded.canLive)
        assertEquals(78.0, decoded.batteryPercent!!, 0.001)
        assertEquals(58.0, decoded.rangeKm!!, 0.001)
        assertEquals("D", decoded.gear)
        assertEquals(30, decoded.chargeMinutesRemaining)
        assertEquals(false, decoded.handbrake)
        val stale = MacCanSerialFrameParser.decodeTelemetry(
            "{\"type\":\"telemetry\",\"can\":false,\"temp1_c\":-99,\"soc_pct\":255}", null
        )!!
        assertNull(stale.temperature1C)
        assertNull(stale.batteryPercent)
        assertNull(MacCanSerialFrameParser.decodeTelemetry("not json", null))
    }

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }
}
