# Debug and test guide

## Android diagnostics screen

Open **Tanılama ve hata ayıklama** from the home screen. It reports app/device version, selected input, Bluetooth permissions, current status, telemetry age, resolved/raw frame counts, capture location and relay state. **Tanılama özetini kopyala** copies this diagnostic summary; inspect it before sharing because it includes device model and local capture path.

Open **Tüm CAN çerçeveleri ve ölçümler** for decoded values and the newest raw CAN frames. Frames with no confirmed mapping remain visible as raw data. For USB serial problems, check the USB status in the OTG page and confirm that the ESP emits the Mac-compatible serial format at 115200 baud.

## Phone test sequence

Use a real phone and current ESP firmware; simulator tests cannot validate Bluetooth, USB host or screen-off behavior.

1. Select Bluetooth and verify the ESP status changes from searching to connected; confirm frames increment.
2. Lock the phone for at least five minutes; check notification, connection state, telemetry age and frame count after unlocking.
3. Return to the home screen, select USB-OTG, grant Android USB permission and check that BLE stops before serial reading begins.
4. Unplug/replug OTG; verify the screen reports a clear state, no crash, and no BLE service restart while OTG remains selected.
5. Return and explicitly select Bluetooth; verify OTG is no longer the active source and only BLE frames increment.
6. Compare CAN IDs, raw bytes and decoded values with the Mac monitor under the same vehicle condition. Note time, source and value for any mismatch.
7. Toggle relay forwarding separately and inspect its status/error. Do not treat a locally passing worker test as proof that the hosted Worker is deployed.

## Regression checks

- 8-bit/extended CAN IDs and invalid DLC must not be misdecoded.
- Unavailable sentinel bytes remain unavailable; stale power samples are not integrated repeatedly.
- Unknown frame IDs remain recorded as raw frames.
- Switching to OTG disables `start_after_reboot`; BLE cannot restart from a sticky service start while the selected mode is OTG.
- USB parser accepts valid `CAN ...` rows and compact telemetry JSON, and discards malformed lines without crashing.
- Relay accepts raw frames with no known signals and returns a precise validation error for malformed samples.

## Bug report template

Share: phone model + Android version; app version; selected mode; whether the car/ESP/MCP were connected; exact status/error text; approximate time; whether the screen was locked; CAN IDs and values that stopped updating; and a redacted diagnostic summary. Never send VIN, access key, GPS history, or raw logs publicly.
