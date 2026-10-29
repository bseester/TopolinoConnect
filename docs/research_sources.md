# CAN research sources

This page records the public references used to interpret CAN frames. Community sources are useful evidence, not a replacement for confirming a value against the specific vehicle and model year.

## Public references

- [AMI-Display CAN information](https://github.com/flrahe/AMI-Display/blob/main/CAN_information/Ami_Rocks-e.dbc): community DBC with message and signal candidates for Ami/Rocks-e vehicles.
- [TopolinoInfoDisplay](https://github.com/servicemensch/TopolinoInfoDisplay): ESP32 + MCP2515 CAN display project for Topolino/Ami/Rocks-e, including source and wiring context.
- [GoingElectric Ami/Rocks-e CAN discussion](https://www.goingelectric.de/forum/viewtopic.php?lang=en&t=90628): community observations about message IDs and possible field layouts.

These sources do not agree on every bit position or scale. The app preserves uncertain fields as candidates; compare live raw frames with the vehicle display before treating an interpretation as confirmed.

## Verification checklist for a new signal

1. Record several frames with the expected CAN identifier and data length.
2. Note the vehicle display value and timestamp alongside each frame.
3. Repeat while changing one vehicle state at a time.
4. Check byte order, bit numbering, scaling, endianness and sentinel values against the source.
5. Add a decoder rule only when the observations repeat; keep a test for the raw frame and decoded result.
