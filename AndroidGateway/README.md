# Topolino Gateway for Android

Android companion for the Topolino ESP32 + MCP2515 CAN reader. The app supports two manually selected input sources: Bluetooth LE and USB-OTG serial. Only one source can be active at a time.

## Home screen

Use the **Bağlantı modu** selector:

- **Bluetooth** requests the required permissions, starts the foreground BLE service and scans for the Topolino ESP. Screen-off use requires the Android foreground notification to remain enabled.
- **USB-OTG** turns off BLE autostart, stops the BLE service and opens the USB host reader. Connect the ESP32 USB serial bridge through a USB-C OTG adapter. If Android asks to open the app for the device, grant access.
- Select Bluetooth again explicitly after leaving USB mode. The app will not silently re-enable BLE while OTG is selected.

CAN frames and vehicle measurements open in **Tüm CAN çerçeveleri ve ölçümler**. **Tanılama ve hata ayıklama** shows the connection source, permission state, last telemetry age, frame counts, capture path and relay status. It can copy a diagnostic summary for a bug report.

## Data and decoder

BLE discovery uses the ESP FDE0 advertisement and live frames from FDE1/FDE2. OTG reads the Mac-compatible serial stream at 115200 baud: `CAN 11-bit ID=... DLC=... DATA=... TS_US=...`, plus compact telemetry JSON. Common CP210x, CH340, FTDI and CDC/ACM serial interfaces are supported by the USB serial library. The phone connects to the ESP32 USB serial bridge.

The CAN decoder maps IDs `0x580`, `0x581`, `0x582`, `0x593`, `0x594`, `0x713`, and `0x714`. Unknown frames are retained as raw data. The decoder mirrors the Mac CAN interpretation and records candidate/raw fields when the DBC meaning has not been validated on this vehicle. Android intentionally does not display speed; speed remains in the Mac monitor.

Vehicle values, stale-sample handling, classic range estimate and energy estimates live outside the views. New power/energy calculations should use only fresh samples. Frame capture is stored in app-private storage; inspect and redact before sharing.

## BLE and firmware rate

Firmware BLE advertisements are approximately 100–200 ms; compact telemetry refresh is 100 ms. Raw notification caps are 20 frames/s for the speed CAN ID and 20 frames/s for other IDs. Android requests high GATT connection priority during streaming. Android and ESP negotiate the real connection interval; UI changes cannot guarantee a specific interval across phone firmware.

## Optional iOS relay

Relay forwarding can be toggled on the home screen. The app sends the latest values and recent raw frames to the configured HTTPS Worker. Local worker tests do not deploy worker changes. Before using relay on a release, deploy and verify the matching Cloudflare Worker schema.

To pair with the iOS test app, enable **ESP verilerini iOS’a gönder**, copy the Android access key, and paste it in iOS **Diğer → Android araç telefonu**. Do not publish this key or include it in screenshots/bug reports.

## Build and checks

Use Android Studio or Java 17/21 with the Gradle wrapper:

```sh
./gradlew testDebugUnitTest lintDebug assembleDebug
```

The debug APK is written to `app/build/outputs/apk/debug/` and is intentionally ignored by Git. See [`../docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md), [`../docs/DEBUG_AND_TESTING.md`](../docs/DEBUG_AND_TESTING.md), and [`../docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md).

## Permissions and background work

Android 12+ requires Bluetooth Scan and Connect. Older versions require location permission for BLE scanning. Android 13+ may request notification permission so the foreground connection state is visible. USB host permission is requested by Android per attached device. Battery-optimization settings are device-dependent; Xiaomi/MIUI background policy must be tested on the actual Note 10.

## Current release status

Development/debug APK only. The mode-switching logic and decoders can be unit-tested, but real BLE timing, Xiaomi screen-off behavior, USB adapter compatibility, car signal interpretation, release signing and hosted Worker deployment require separate verification. This is not a Play Store release yet.
