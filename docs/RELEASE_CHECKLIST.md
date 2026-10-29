# GitHub and package readiness

## Before a source push

- [ ] Push the standalone Topolino project to a dedicated repository. Verify the selected remote is the intended Topolino repository before pushing; the surrounding workspace may have an unrelated remote.
- [ ] Review `git status --short` and `git check-ignore` for generated files, credentials, private captures, GPS trip history and local configuration.
- [ ] Keep firmware source and a public config example; keep private `config/config.h`, SDK paths and local config out of commits.
- [ ] Verify third-party licenses and attribution. `TopolinoInfoDisplay_Firmware/source/LICENSE` and dependencies remain governed by their upstream licenses.
- [ ] Do not include the nested upstream `.git` folder from the TopolinoInfoDisplay checkout.
- [ ] Run Android tests/lint/build, relay tests, Swift tests, and the relevant Xcode/firmware builds.
- [ ] Review the changes on a clean checkout to prove the instructions are reproducible.

## Before a user release

- [ ] Choose a version; align Android `versionCode`/`versionName` and release notes.
- [ ] Build Android release with the owner’s signing key outside the repository. Never commit keystores or passwords.
- [ ] Build iOS/macOS with the correct bundle IDs, signing team, entitlements, privacy usage text and distribution profile.
- [ ] Build firmware for the documented ESP32 board, verify CAN controller wiring and run the real-car/bench test checklist.
- [ ] Test Bluetooth and USB-OTG mode switching, screen-off operation, reconnect behavior, and no simultaneous collection on Xiaomi Note 10.
- [ ] Confirm the Cloudflare Worker deployment and schema compatibility before enabling relay in a public app.
- [ ] Publish APK/IPA/firmware as a versioned GitHub Release artifact; keep binaries out of Git history.
- [ ] Confirm docs state what is experimental, what is confirmed, and how to report a defect safely.

## Current limitations

The app sources and local debug package are development-stage. There has been no full phone/vehicle release validation in this workspace. CAN candidates may depend on vehicle/firmware revision. The Cloudflare worker’s local tests do not deploy it. Xcode signing and Play/App Store packaging remain release-owner steps.
