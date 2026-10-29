# UI and interaction guide

## Goal

Show the few decisions a driver needs on the first screen. Keep connection choice, live vehicle values, diagnostics and engineering details visually separate.

## Visual hierarchy

- Use a calm dark navy base with high-contrast text and one mint/teal active-state accent across Android, Mac and iOS.
- First screen: connection state, key vehicle readouts and the input source. Do not put raw CAN dumps or protocol candidates above the primary values.
- Keep secondary actions in simple named destinations; do not make every engineering control a primary button.
- Use consistent card spacing, short labels and tabular digits for changing numbers. Preserve native platform navigation and controls.
- Keep empty, connecting, stale and disconnected states explicit. Mark candidate/estimated values as such.

## Input selection

Android shows Bluetooth and USB-OTG as an explicit single-choice mode selector. The selected source is persistent, but switching sources closes the previous collector. OTG must not activate BLE autostart. Returning from OTG does not implicitly start BLE; the user chooses it.

## Diagnostics

- Android: **Tanılama ve hata ayıklama** for source/permission/freshness/relay summary; **Tüm CAN çerçeveleri ve ölçümler** for raw frames and candidates.
- Mac: serial diagnostics, CAN ID traffic, field freshness and raw frame log are the engineering view.
- iOS: keep BLE/GATT and Android relay details in its diagnostics/settings flow, not the primary vehicle dashboard.

Diagnostic screens are for user testing, so explain each state in plain language and provide a safe copyable summary. Warn before sharing fields that might identify a phone, vehicle or local file.

## Accessibility and review

Support dynamic text where the native framework allows it, provide touch targets of at least 44–48 dp/pt, do not use color as the only status indicator, and retain labels for VoiceOver/TalkBack. Review screenshots on a phone-sized viewport and larger display before calling a UI release-ready.

No connected-device visual review has been completed for the current Android changes; confirm the layout and MIUI dialogs on the Xiaomi Note 10.
