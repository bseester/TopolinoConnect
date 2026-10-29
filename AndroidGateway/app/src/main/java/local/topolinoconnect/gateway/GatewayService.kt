package local.topolinoconnect.gateway

import android.annotation.SuppressLint
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

/** Direct ESP32 BLE receiver. No location, cloud, HTTP API or garage-control work runs here. */
class GatewayService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var scanCallback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var lastSeenDevice: BluetoothDevice? = null
    private var reconnectAttempt = 0
    private var lastBleResultAt = 0L
    private var lastNotificationAt = 0L
    private var wakeLock: PowerManager.WakeLock? = null

    private val retryScan = Runnable { startScan() }
    private val checkScanHealth = object : Runnable {
        override fun run() {
            if (scanCallback != null && gatt == null &&
                System.currentTimeMillis() - lastBleResultAt >= SCAN_SILENCE_RESTART_MS) {
                stopScan()
                GatewayRuntime.status = "BLE yayını sessiz · ESP yeniden aranıyor"
                updateNotification(GatewayRuntime.status, true)
                scheduleScanRetry()
            }
            handler.postDelayed(this, SCAN_HEALTH_CHECK_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ClassicRangeEstimateStore.initialize(this)
        createNotificationChannel()
        enterForeground("ESP CAN BLE aranıyor")
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            GatewayConfig.setAutoStart(this, false)
            stopReceiver()
            stopSelf()
            return START_NOT_STICKY
        }
        if (GatewayConfig.inputMode(this) != GatewayConfig.InputMode.BLUETOOTH) {
            GatewayRuntime.status = "Bluetooth modu seçili değil"
            stopSelf()
            return START_NOT_STICKY
        }
        startScan()
        handler.removeCallbacks(checkScanHealth)
        handler.postDelayed(checkScanHealth, SCAN_HEALTH_CHECK_MS)
        return START_STICKY
    }

    private fun enterForeground(text: String) {
        val notification = notification(text)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else startForeground(NOTIFICATION_ID, notification)
    }

    @SuppressLint("MissingPermission")
    private fun startScan() {
        if (scanCallback != null || gatt != null) return
        if (!hasBluetoothPermission()) {
            GatewayRuntime.status = "Bluetooth izni gerekli"
            updateNotification(GatewayRuntime.status, true)
            return
        }
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = manager.adapter?.bluetoothLeScanner
        if (scanner == null) {
            GatewayRuntime.status = "Bluetooth LE kapalı"
            updateNotification(GatewayRuntime.status, true)
            scheduleScanRetry()
            return
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                lastBleResultAt = System.currentTimeMillis()
                reconnectAttempt = 0
                handleAdvertisement(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                if (results.isNotEmpty()) lastBleResultAt = System.currentTimeMillis()
                results.forEach(::handleAdvertisement)
            }

            override fun onScanFailed(errorCode: Int) {
                scanCallback = null
                GatewayRuntime.status = "BLE tarama hatası · $errorCode"
                updateNotification(GatewayRuntime.status, true)
                scheduleScanRetry()
            }
        }
        scanCallback = callback
        lastBleResultAt = System.currentTimeMillis()
        try {
            // Some Android/OEM BLE controllers silently return zero results
            // for service-data offload filters. Scan unfiltered and only accept
            // the ESP's FDE0 service data in handleAdvertisement().
            scanner.startScan(null, ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setReportDelay(0)
                .build(), callback)
            GatewayRuntime.status = "ESP Topolino BLE yayını aranıyor"
            GatewayRuntime.gattFrameStatus = "Ham CAN çerçeveleri Android’de çözümlenecek"
            updateNotification(GatewayRuntime.status, true)
        } catch (error: Exception) {
            scanCallback = null
            GatewayRuntime.status = "BLE taraması başlatılamadı · ${error.localizedMessage ?: "tekrar denenecek"}"
            updateNotification(GatewayRuntime.status, true)
            scheduleScanRetry()
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleAdvertisement(result: ScanResult) {
        val record = result.scanRecord ?: return
        val entry = record.serviceData?.entries?.firstOrNull {
            it.key.uuid.toString().equals(ESP_CAN_UUID, ignoreCase = true)
        }
        val sample = entry?.value?.let(TopolinoCanDecoder::decodeAdvertisement)
        val advertisesFrameService = record.serviceUuids?.any {
            it.uuid.toString().equals(UUID_FRAME_SERVICE.toString(), ignoreCase = true)
        } == true
        // Some Android/OEM stacks expose the scan-response name on the device
        // object rather than ScanRecord.deviceName.
        val deviceName = record.deviceName ?: runCatching { result.device.name }.getOrNull()
        val isTopolino = deviceName.equals(ESP_DEVICE_NAME, ignoreCase = true)
        if (isTopolino || advertisesFrameService || entry != null) {
            Log.i("TopolinoBLE", "ESP advertisement candidate: name=$deviceName, FDE0=${entry?.value?.size ?: 0}B, FDE1=$advertisesFrameService, RSSI=${result.rssi}")
        }
        if (sample == null && !advertisesFrameService && !isTopolino) return

        lastSeenDevice = result.device
        if (sample != null) {
            acceptSample(sample, result.rssi)
        } else {
            GatewayRuntime.status = "Topolino ESP bulundu · ham CAN bağlantısı kuruluyor"
            GatewayRuntime.espCanRssi = result.rssi
            updateNotification(GatewayRuntime.status, true)
        }
        if (gatt == null) connectForFrames(result.device)
    }

    private fun acceptSample(sample: VehicleSnapshot, rssi: Int? = null) {
        // FDE0 v1-v3 cannot identify the charging-layout SOC byte. v4 is
        // produced by firmware that only publishes SOC from verified B6=0x13.
        val advVersion = sample.source.substringAfter("FDE0 v", "").toIntOrNull()
        val untrustedChargingAdvertisement = sample.charging == true && advVersion != null && advVersion < 4
        val safeSample = if (untrustedChargingAdvertisement) sample.copy(batteryPercent = null) else sample
        val merged = GatewayRuntime.vehicleSnapshot?.merge(safeSample) ?: safeSample
        ClassicRangeEstimateStore.capture(this, merged, safeSample.batteryPercent != null)
        GatewayRuntime.vehicleSnapshot = merged
        val now = Instant.now().toString()
        val json = merged.toJson().put("timestamp", now)
        GatewayRuntime.espCan = json
        GatewayRuntime.espCanAt = now
        if (rssi != null) GatewayRuntime.espCanRssi = rssi
        GatewayRuntime.lastTelemetryAt = now
        GatewayRuntime.acceptCanSample(json)
        AndroidRelayClient.publishIfEnabled(this, json)
        GatewayRuntime.status = if (merged.simulation) "⚠ TEST VERİSİ · ESP simülasyonu · gerçek araç CAN’i değil" else "ESP CAN canlı${GatewayRuntime.espCanRssi?.let { " · $it dBm" } ?: ""}"
        updateNotification(GatewayRuntime.status)
    }

    @Suppress("MissingPermission")
    private fun connectForFrames(device: BluetoothDevice) {
        if (!hasBluetoothPermission() || gatt != null) return
        stopScan()
        GatewayRuntime.gattFrameStatus = "ESP’ye BLE CAN çerçeve bağlantısı kuruluyor"
        gatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    @SuppressLint("MissingPermission")
    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(client: BluetoothGatt, status: Int, newState: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                GatewayRuntime.gattFrameStatus = "ESP BLE bağlı · CAN çerçeve kanalı açılıyor"
                // Match the display project's 100 ms live telemetry cadence as
                // closely as Android allows while its raw GATT stream is open.
                runCatching { client.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH) }
                runCatching { client.discoverServices() }.onFailure {
                    GatewayRuntime.gattFrameStatus = "ESP CAN servisi bulunamadı"
                    client.disconnect()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (gatt === client) gatt = null
                runCatching { client.close() }
                GatewayRuntime.gattFrameStatus = "BLE bağlantısı koptu · ESP tekrar aranıyor"
                handler.postDelayed({ if (gatt == null) startScan() }, RECONNECT_DELAY_MS)
            }
        }

        override fun onServicesDiscovered(client: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                GatewayRuntime.gattFrameStatus = "ESP CAN servisi okunamadı · $status"
                client.disconnect()
                return
            }
            val characteristic = client.getService(UUID_FRAME_SERVICE)?.getCharacteristic(UUID_FRAME_CHARACTERISTIC)
            if (characteristic == null) {
                GatewayRuntime.gattFrameStatus = "ESP yazılımında FDE2 ham CAN kanalı yok"
                client.disconnect()
                return
            }
            enableFrameNotifications(client, characteristic)
        }

        override fun onDescriptorWrite(client: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (descriptor.uuid != UUID_CCCD) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                GatewayRuntime.gattFrameStatus = "CAN çerçeveleri BLE’den canlı · Android çözümlüyor"
            } else {
                GatewayRuntime.gattFrameStatus = "CAN BLE bildirimi açılamadı · $status"
                client.disconnect()
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            acceptFrameNotification(characteristic.uuid, characteristic.value ?: return)
        }

        override fun onCharacteristicChanged(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            acceptFrameNotification(characteristic.uuid, value)
        }
    }

    @SuppressLint("MissingPermission")
    private fun enableFrameNotifications(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        val enabled = runCatching { client.setCharacteristicNotification(characteristic, true) }.getOrDefault(false)
        val descriptor = characteristic.getDescriptor(UUID_CCCD)
        if (!enabled || descriptor == null) {
            GatewayRuntime.gattFrameStatus = "FDE2 bildirim ayarı başarısız"
            client.disconnect()
            return
        }
        val started = if (Build.VERSION.SDK_INT >= 33) {
            client.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            client.writeDescriptor(descriptor)
        }
        if (!started) {
            GatewayRuntime.gattFrameStatus = "FDE2 CAN bildirimi başlatılamadı"
            client.disconnect()
        }
    }

    private fun acceptFrameNotification(uuid: UUID, bytes: ByteArray) {
        val wireVersion = if (bytes.isNotEmpty()) u8(bytes, 0) else return
        val simulation = (wireVersion and 0x80) != 0
        if (uuid != UUID_FRAME_CHARACTERISTIC || bytes.size != FRAME_RECORD_SIZE || (wireVersion and 0x7f) != 1) return
        val extended = (u8(bytes, 1) and 1) != 0
        val identifier = u32(bytes, 2)
        val dlc = u8(bytes, 6).coerceIn(0, 8)
        val payload = ByteArray(dlc) { bytes[7 + it] }
        val dataText = payload.joinToString(" ") { "%02X".format(it.toInt() and 0xff) }
        val entry = JSONObject()
            .put("id", "0x${identifier.toString(16).uppercase().padStart(if (extended) 8 else 3, '0')}")
            .put("extended", extended)
            .put("dlc", dlc)
            .put("data", dataText)
            .put("timestampUs", u32(bytes, 15))
            .put("timestamp", Instant.now().toString())
            .put("simulation", simulation)
        val decoded = TopolinoCanDecoder.decodeFrame(identifier, payload, GatewayRuntime.vehicleSnapshot, extended)
        // Record before publishing telemetry so an Android→iOS relay packet
        // contains this newest CAN frame rather than ending one frame behind.
        GatewayRuntime.addCanFrame(entry, decoded != null)
        CanFrameRecorder.record(this, entry)
        if (decoded != null) acceptSample(decoded.copy(simulation = simulation,
            source = if (simulation) "ESP SIMÜLASYON TESTİ · BLE CAN · 0x${identifier.toString(16).uppercase()}" else decoded.source))
        else {
            if (simulation) GatewayRuntime.status = "⚠ TEST VERİSİ · ESP simülasyonu · gerçek araç CAN’i değil"
            else AndroidRelayClient.publishRawFrameUpdate(this)
        }
        GatewayRuntime.gattFrameStatus = if (simulation) "TEST CAN BLE · sentetik veri · çözülen ${GatewayRuntime.resolvedFrameCount} · ham ${GatewayRuntime.unresolvedFrameCount}" else "CAN BLE canlı · çözülen ${GatewayRuntime.resolvedFrameCount} · ham ${GatewayRuntime.unresolvedFrameCount}"
    }

    private fun u8(bytes: ByteArray, index: Int) = bytes[index].toInt() and 0xff
    private fun u32(bytes: ByteArray, index: Int): Long =
        (u8(bytes, index).toLong() shl 24) or (u8(bytes, index + 1).toLong() shl 16) or
            (u8(bytes, index + 2).toLong() shl 8) or u8(bytes, index + 3).toLong()

    private fun scheduleScanRetry() {
        handler.removeCallbacks(retryScan)
        val delay = (1_000L shl reconnectAttempt.coerceAtMost(5)).coerceAtMost(MAX_RETRY_MS)
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(5)
        handler.postDelayed(retryScan, delay)
    }

    @Suppress("MissingPermission")
    private fun stopScan() {
        val callback = scanCallback ?: return
        if (hasBluetoothPermission()) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            runCatching { manager.adapter?.bluetoothLeScanner?.stopScan(callback) }
        }
        scanCallback = null
    }

    @Suppress("MissingPermission")
    private fun stopGatt() {
        val client = gatt
        gatt = null
        if (client != null) {
            runCatching { client.disconnect() }
            runCatching { client.close() }
        }
    }

    private fun acquireWakeLock() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TopolinoMonitor:BleCAN").apply {
            setReferenceCounted(false)
            acquire(30 * 60 * 1000L)
        }
    }

    private fun stopReceiver() {
        handler.removeCallbacks(retryScan)
        handler.removeCallbacks(checkScanHealth)
        stopScan()
        stopGatt()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        GatewayRuntime.status = "ESP BLE CAN durduruldu"
        GatewayRuntime.gattFrameStatus = "Bağlantı durduruldu"
    }

    private fun hasBluetoothPermission(): Boolean = if (Build.VERSION.SDK_INT >= 31) {
        checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    } else checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun createNotificationChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "Topolino CAN bağlantısı", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun notification(text: String): Notification {
        val openApp = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = Notification.Builder(this, CHANNEL_ID)
        return builder.setContentTitle("Topolino CAN Monitor")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastNotificationAt < NOTIFICATION_INTERVAL_MS) return
        lastNotificationAt = now
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(text))
    }

    override fun onDestroy() {
        stopReceiver()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "local.topolinoconnect.gateway.START"
        const val ACTION_STOP = "local.topolinoconnect.gateway.STOP"
        private const val ESP_DEVICE_NAME = "Topolino ESP"
        private const val ESP_CAN_UUID = "0000fde0-0000-1000-8000-00805f9b34fb"
        private val UUID_FRAME_SERVICE = UUID.fromString("0000fde1-0000-1000-8000-00805f9b34fb")
        private val UUID_FRAME_CHARACTERISTIC = UUID.fromString("0000fde2-0000-1000-8000-00805f9b34fb")
        private val UUID_CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val FRAME_RECORD_SIZE = 19
        private const val SCAN_HEALTH_CHECK_MS = 10_000L
        private const val SCAN_SILENCE_RESTART_MS = 30_000L
        private const val RECONNECT_DELAY_MS = 1_000L
        private const val MAX_RETRY_MS = 30_000L
        private const val NOTIFICATION_INTERVAL_MS = 1_000L
        private const val CHANNEL_ID = "topolino_can_monitor"
        private const val NOTIFICATION_ID = 2705
    }
}
