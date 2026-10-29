# Topolino Connect — short project memory

This file is a concise handoff index. It replaces a long chronological scratchpad; use topic documents for detail.

## Current product shape

- `AndroidGateway/`: Android monitor; user selects one source at a time: Bluetooth LE or USB-OTG serial. `GatewayConfig.InputMode` is the mode invariant. BLE autostart must stay off in OTG mode.
- `MacApp/` + `Sources/`: Mac serial monitor and CAN decoder. Speed display is Mac-only.
- `MyCitroenPort/`: separate iOS, widget and watch test app; optional Android HTTPS relay.
- Separate paired repository `servicemensch/TopolinoInfoDisplay`: ESP32 + MCP2515 firmware and BLE/USB serial outputs.
- `AmiTopolinoMacCAN/`: separate alternative monitor/firmware experiment.

## Signal confidence

CAN IDs `0x580`, `0x581`, `0x582`, `0x593`, `0x594`, `0x713`, and `0x714` are decoded from the ESP CAN path. Some DBC bit placements remain candidate interpretations. Keep unknown values null/raw and preserve evidence labels. Android uses exactly one ESP input at a time: BLE or USB-OTG.

## Data / release rules

Live CAN/BLE JSONL, audit CSV, trip GPS and device identifiers are local/private. Keep them ignored and redact before sharing. Do not commit build folders, APK/IPA/firmware binaries, signing credentials, SDK paths or nested `.git` metadata. Publish binaries as versioned GitHub Releases.

The enclosing local checkout may have an unrelated Git remote. Verify that the selected remote belongs to the Topolino project before pushing.

## Fast references

- Start with [`AGENTS.md`](AGENTS.md) and [`docs/AI_AGENT_GUIDE.md`](docs/AI_AGENT_GUIDE.md) for short agent context.
- Full path/data flow: [`docs/PROJECT_MAP.md`](docs/PROJECT_MAP.md).
- Build commands: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
- Phone/debug checklist: [`docs/DEBUG_AND_TESTING.md`](docs/DEBUG_AND_TESTING.md).
- GitHub/release requirements: [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md).
- Signal evidence and research: [`docs/protocol_hypotheses.md`](docs/protocol_hypotheses.md), [`docs/research_sources.md`](docs/research_sources.md).

## Commands

Android (`AndroidGateway/`): `./gradlew testDebugUnitTest lintDebug assembleDebug`

Relay (`AndroidGateway/relay/`): `npm test`

Swift package: `swift test`
