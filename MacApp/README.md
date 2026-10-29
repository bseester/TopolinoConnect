# Topolino Mac CAN Monitor

SwiftUI/macOS monitor for CAN frames read from the ESP32 serial bridge. It displays the CAN-derived speed sample, freshness, decoded metrics, expected frame IDs, raw traffic and ESP diagnostic messages.

## Data path

USB serial at 115200 baud → `Sources/MCP2515SerialMonitor.swift` → `Sources/AmiCANDecoder.swift` → `MacApp/TopolinoConnectMac.swift` UI. It sends no CAN/vehicle commands. Unknown frames and candidate interpretations should remain distinguishable from validated values.

## Build and hardware test

Open the shared Xcode project/scheme on a Mac with Xcode and macOS SDK. Connect the ESP USB data port, select its serial device and compare frame IDs/values against Android USB-OTG in the same conditions. A compile or parser test alone does not validate the physical CAN wiring or speed mapping. See [`../docs/DEBUG_AND_TESTING.md`](../docs/DEBUG_AND_TESTING.md).
