# MyCitroën Port (Topolino test app)

This is a separate SwiftUI test target for iPhone, WidgetKit, and Apple Watch. It is not the ESP firmware or Android app. The iOS target presents vehicle data from its local BLE components and can receive data forwarded by Android through the HTTPS relay.

## Main components

- `MyCitroenPortApp.swift`: iOS screens, tabs, settings, vehicle, charge and diagnostic flows.
- `Sources/BLEModel.swift`: Bluetooth state and local BLE observation.
- `Sources/AndroidGatewayClient.swift`: authenticated HTTPS snapshot receiver for Android relay data.
- `Sources/WatchSnapshotBridge.swift`, `Sources/WatchVehicleSnapshot.swift`: shared snapshot handoff and watch model.
- `WidgetExtension/`: home/lock-screen widget backed by the shared snapshot store.
- `WatchApp/`: watch companion entry point and assets.
- `project.yml`: XcodeGen project description; `MyCitroenPort.xcodeproj/` is the generated Xcode project.

## Build

Open `MyCitroenPort.xcodeproj` and choose the iOS or watch scheme. A signed install/archive requires the owner’s Apple team and provisioning. Use a local, ignored DerivedData path. Check [`../docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md) before distribution.

The relay access key and local vehicle data are private. Do not add them to issue reports or source control. The iOS port is a test build and has not been released through the App Store.
