# Project map

## Repository contents

This repository contains the Android Gateway, Mac CAN monitor, iOS/watch app, optional relay, Swift CAN helpers and project documentation. The separate `futboldata` repository in the parent folder is unrelated and must not be added here. ESP firmware remains maintained separately in the TopolinoInfoDisplay firmware repository.

## Data path

```text
Vehicle CAN bus → MCP2515 listen-only → ESP32
  ├─ BLE snapshot and raw CAN notifications → Android Gateway
  ├─ USB serial at 115200 baud → Android Gateway (OTG)
  └─ USB serial at 115200 baud → Mac CAN Monitor

Android Gateway → optional HTTPS relay → iOS app
```

Android input selection is exclusive: Bluetooth or USB-OTG. Both paths feed the same CAN decoder and vehicle snapshot. The iOS app receives data through the optional relay.

## Component ownership

| Path | Responsibility |
|---|---|
| `AndroidGateway/app/src/main` | Android UI, BLE service, OTG serial reader, CAN decoder and capture |
| `AndroidGateway/app/src/test` | Decoder and serial line parser tests |
| `AndroidGateway/relay/cloudflare` | Worker, D1 schema/migrations and worker tests |
| `Sources/AmiCANDecoder.swift` | Swift CAN frame interpretation helpers |
| `Sources/MCP2515SerialMonitor.swift` | Mac serial port and CAN frame stream |
| `MacApp` | Mac monitor UI |
| `MyCitroenPort` | iOS, watch and widget application; Android relay client |
| `docs/BEGINNER_GUIDE.md` | Pin wiring and first-use instructions |

## Change guide

- CAN signal interpretation belongs in Android `TopolinoCanDecoder.kt` and Swift `AmiCANDecoder.swift`. Update matching fixtures when the evidence supports a change.
- USB serial line parsing belongs in `MacCanSerialFrameParser.kt` and `MCP2515SerialMonitor.swift`.
- Android BLE connection lifecycle belongs in `GatewayService.kt`; USB lifecycle belongs in `UsbCanActivity.kt`.
- iOS relay compatibility spans `AndroidRelayClient.kt`, the Worker and `MyCitroenPort/Sources/AndroidGatewayClient.swift`.
- Keep decoding math out of UI views. Keep unknown values null/raw and retain candidate labels for uncertain CAN fields.

## Generated and private files

Build folders, local signing data, device identifiers, credentials, raw vehicle captures and GPS trip logs must not enter Git. See `.gitignore` and `RELEASE_CHECKLIST.md` before publishing.
