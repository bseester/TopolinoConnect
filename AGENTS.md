# Agent notes for Topolino Connect

Read [`docs/AI_AGENT_GUIDE.md`](docs/AI_AGENT_GUIDE.md) first. It is the short project map, safety boundary, and validation guide. Read only the app-specific README and source files relevant to the assigned task; consult protocol research docs only when decoding changes.

Core invariants:

- Android input has exactly one active source: `BLUETOOTH`, `USB_OTG`, or `NONE`. Never collect BLE and USB serial concurrently.
- CAN IDs are not BLE payloads. Do not infer a signal from correlation alone; preserve unknown values as unknown and keep raw frames available.
- Do not expose Android/iOS speed; it is intentionally Mac-only.
- Do not add raw drive captures, device identifiers, GPS history, credentials, build caches, generated binaries, or nested upstream Git metadata to source control.
- Prefer focused changes and shared data/decoder helpers. Keep connection lifecycle out of UI rendering code where possible.
- Test hardware-specific claims on real ESP/phone hardware; a local build does not prove radio timing, OTG compatibility, or vehicle signal accuracy.
