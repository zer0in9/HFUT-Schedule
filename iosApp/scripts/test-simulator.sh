#!/bin/bash
set -euo pipefail

family="${1:?Pass iPhone or iPad}"
[[ "$family" == iPhone || "$family" == iPad ]] || exit 1
udid="$(awk -v family="$family" '$1 == family {print $2}' "$RUNNER_TEMP/ios-simulators.txt")"
test -n "$udid"
mkdir -p iosApp/build
bounded() { python3 iosApp/scripts/run-with-timeout.py "$@"; }
collect_diagnostics() {
  bounded 30 xcrun simctl io "$udid" screenshot "iosApp/build/$family.png" || true
  bounded 30 xcrun simctl spawn "$udid" log show --last 5m --style compact \
    --predicate 'process == "HFUTSchedule" OR process == "HFUTScheduleUITests-Runner"' \
    > "iosApp/build/$family.log" 2>&1 || true
  bounded 30 xcrun simctl shutdown "$udid" || true
}
trap collect_diagnostics EXIT
# CoreSimulator can stop responding after a long native build. Recover boot once,
# but never retry or ignore application test failures.
if ! bounded 90 xcrun simctl boot "$udid"; then
  echo "Restarting unresponsive CoreSimulator before retrying device boot"
  killall -9 Simulator com.apple.CoreSimulator.CoreSimulatorService || true
  bounded 60 xcrun simctl list devices > "$RUNNER_TEMP/simulator-recovery.log"
fi
bounded 30 open -a "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$udid"
# -b boots a shutdown device as well as waiting for an already booting device.
bounded 360 xcrun simctl bootstatus "$udid" -b
bounded 300 xcodebuild test-without-building -project iosApp/HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -destination "platform=iOS Simulator,id=$udid" -destination-timeout 60 \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "iosApp/build/$family.xcresult" \
  -derivedDataPath iosApp/build/SimulatorDerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
