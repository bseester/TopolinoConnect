#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
PROJECT="$ROOT/../AmiTopolinoMacCAN/macos"
"$PROJECT/build_mac_app.sh"

# Keep the established app filename in sync while the CAN monitor source of truth
# lives in the focused AmiTopolinoMacCAN project.
rm -rf "$ROOT/TopolinoESPMonitor.app"
/usr/bin/ditto "$PROJECT/AmiTopolinoCANMonitor.app" "$ROOT/TopolinoESPMonitor.app"
print "$ROOT/TopolinoESPMonitor.app"
