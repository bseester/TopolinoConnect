# CAN signal notes and confidence

This document records which vehicle values are decoded from CAN and where the public descriptions disagree. It does not treat every decoded value as independently confirmed for every vehicle model or year.

## Known frame IDs

| CAN ID | Fields used by the app | Confidence note |
|---|---|---|
| `0x580` | Battery voltage, current, state of charge | SOC byte is layout-dependent; charging frames can use another layout. The decoder guards against known false SOC interpretations. |
| `0x581` | Odometer, speed | Speed is the final data byte in the current CAN map; the Android/iOS UI intentionally hides speed. |
| `0x582` | Charge-time value | Public sources disagree about byte order and units; treat as a candidate. |
| `0x593` | 12 V battery voltage | Scale and range are checked before displaying. |
| `0x594` | Battery temperatures | Byte positions are candidate interpretations. |
| `0x713` | Gear, remaining range, READY | Public descriptions disagree on some bit positions. Preserve raw values and candidate labels. |
| `0x714` | Parking-brake state | Candidate mapping; confirm against a live vehicle display. |

## Decoder rules

- Only parse standard frames with the expected identifier and data length.
- Unknown identifiers and malformed frames remain raw; never coerce them into a vehicle signal.
- A plausible value is not proof of a correct mapping. Confirm candidate signals with repeated captures and the vehicle display under the same conditions.
- Firmware compilation and synthetic test frames verify software paths only; they do not confirm a signal's real-world meaning.

## References

- Community AMI/Rocks-e CAN descriptions are linked from [`research_sources.md`](research_sources.md).
- The ESP implementation and its hardware settings are maintained in the separate [TopolinoInfoDisplay firmware project](https://github.com/servicemensch/TopolinoInfoDisplay).
