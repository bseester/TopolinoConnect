# AI agent quick guide

Low-token orientation for coding agents. Start with this page, then read only the relevant app README and source files.

## One-minute context

- This repository contains the Topolino CAN monitoring apps and relay.
- Android: `AndroidGateway/`; choose one input source: BLE or USB-OTG serial.
- Mac: `MacApp/` and `Sources/MCP2515SerialMonitor.swift`; USB serial monitor with a Mac-only speed panel.
- iOS: `MyCitroenPort/`; receives optional data from Android through the relay.
- ESP32 firmware is maintained in the separate TopolinoInfoDisplay firmware repository.
- The parent `futboldata` project and its generated artifacts are unrelated; do not include them.

## Invariants

1. Android has one active input at a time. Switching to OTG stops BLE; BLE restarts only after the user selects it.
2. CAN frames and decoded values are separate layers. Unknown or disputed signals remain raw/candidate values.
3. Android and iOS do not expose vehicle speed. The Mac speed display is experimental and retains source/freshness context.
4. Do not commit vehicle captures, identifiers, GPS trips, credentials, local SDK paths, build output or distributable binaries.
5. A firmware build does not prove physical wiring, radio timing or live vehicle signal accuracy.

## Fast validation

Android (`cd AndroidGateway`):

```sh
./gradlew testDebugUnitTest lintDebug assembleDebug
```

Relay (`cd AndroidGateway/relay`):

```sh
npm test
```

For iOS/macOS targets, use Xcode and a matching Apple SDK. See [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Relevant documents

- [`PROJECT_MAP.md`](PROJECT_MAP.md): data flow and source ownership.
- [`protocol_hypotheses.md`](protocol_hypotheses.md): CAN signal confidence and known disagreements.
- [`BEGINNER_GUIDE.md`](BEGINNER_GUIDE.md): wiring and first-use guide.
- [`DEBUG_AND_TESTING.md`](DEBUG_AND_TESTING.md): diagnostics and hardware checks.
- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md): versioning, privacy and publishing.

Avoid scanning the whole repository by default. Use `rg` for targeted searches and read protocol evidence only when a decoding change requires it.
