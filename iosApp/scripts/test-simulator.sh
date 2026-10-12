#!/bin/bash
set -euo pipefail

family="${1:?Pass iPhone or iPad}"
[[ "$family" == iPhone || "$family" == iPad ]] || exit 1
udid="$(awk -v family="$family" '$1 == family {print $2}' "$RUNNER_TEMP/ios-simulators.txt")"
test -n "$udid"
mkdir -p iosApp/build
collect_diagnostics() {
  xcrun simctl io "$udid" screenshot "iosApp/build/$family.png" || true
  xcrun simctl spawn "$udid" log show --last 5m --style compact \
    --predicate 'process == "HFUTSchedule" OR process == "HFUTScheduleUITests-Runner"' \
    > "iosApp/build/$family.log" 2>&1 || true
  xcrun simctl shutdown "$udid" || true
}
trap collect_diagnostics EXIT
# Boot explicitly so simulator startup has a visible phase rather than stalling XCTest.
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcodebuild test-without-building -project iosApp/HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -destination "platform=iOS Simulator,id=$udid" -destination-timeout 60 \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "iosApp/build/$family.xcresult" \
  -derivedDataPath iosApp/build/SimulatorDerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
