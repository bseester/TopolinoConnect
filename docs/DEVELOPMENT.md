# Development setup

## Android Gateway

Requirements: Android Studio/SDK, Java 17 or 21 (match the installed Gradle environment), and network access for first-time Gradle dependency resolution. Open `AndroidGateway/` as a standalone Gradle project. `local.properties` is generated per computer and is ignored.

```sh
cd AndroidGateway
./gradlew testDebugUnitTest lintDebug assembleDebug
```

The debug APK is generated under `app/build/outputs/apk/debug/`; install it on a Xiaomi Note 10 or another Android 8+ phone for BLE and OTG verification. USB-OTG reads the ESP32 USB serial bridge; the phone does not connect directly to the MCP2515 module.

## Relay worker

The worker is under `AndroidGateway/relay/cloudflare/`. Run local schema tests with `npm test` from `AndroidGateway/relay/`. Deployment requires the authorized Cloudflare account and worker configuration; source changes do not update the hosted endpoint by themselves. Never publish relay credentials.

## Swift shared package

Requirements: Swift 5.9 or newer.

```sh
swift test
```

## Mac CAN Monitor

The monitor reads ESP serial lines at 115200 baud. Connect the ESP USB serial port, select it in the app, and compare live signal age and values with the dashboard/vehicle. The generated `.app` is a local artifact and is ignored by Git. The Mac app has the speed panel and is the diagnostic reference for the raw serial path; it does not prove an Android BLE radio interval.

## iOS / widget / watch test app

Open `MyCitroenPort/MyCitroenPort.xcodeproj`. Select the `MyCitroenPort` scheme for iOS or `MyCitroenPortWatch` for watchOS. Device signing, bundle identifiers, widget entitlements, Bluetooth permissions and relay URL must be checked before distribution.

## Firmware

Clone the paired [TopolinoInfoDisplay firmware repository](https://github.com/servicemensch/TopolinoInfoDisplay), open its `source/` folder with PlatformIO, and build the intended environment from `platformio.ini`. Build output belongs in `.pio/`. The project has a private `config/config.h`; use `config/config_example.h` as the public template and never commit local credentials. Confirm the board target and pinout before flashing; compile success does not confirm hardware wiring or CAN reception.
