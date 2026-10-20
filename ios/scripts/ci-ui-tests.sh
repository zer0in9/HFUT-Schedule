#!/bin/bash
set -euo pipefail
if [[ "${CI:-}" != "true" ]]; then
  echo 'Simulator tests are restricted to CI for this project.' >&2
  exit 1
fi
cd "$(dirname "$0")/.."
xcodegen generate
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"]
family = os.environ.get("IOS_DEVICE_FAMILY", "iPhone")
if family not in ("iPhone", "iPad"):
    sys.exit("Unsupported simulator family")
candidates = [
    (tuple(int(part) for part in runtime.rsplit(".iOS-", 1)[1].split("-")), d)
    for runtime, group in devices.items() if ".iOS-" in runtime
    for d in group if family in d["name"] and d["isAvailable"]
    if int(runtime.rsplit(".iOS-", 1)[1].split("-")[0]) >= 26
]
if not candidates:
    sys.exit(f"No available iOS 26+ {family} simulator")
print(max(candidates, key=lambda candidate: candidate[0])[1]["udid"])
')
xcodebuild test \
  -project HFUTSchedule.xcodeproj \
  -scheme HFUTSchedule \
  -destination "platform=iOS Simulator,id=$device_id" \
  -resultBundlePath UITests.xcresult \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO
