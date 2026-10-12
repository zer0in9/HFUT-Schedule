#!/bin/bash
set -euo pipefail

# Run from any directory. No developer certificate is needed: users re-sign the IPA.
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
version="${IOS_VERSION:-0.1.0}"
build_number="${IOS_BUILD_NUMBER:-1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid IOS_VERSION' >&2; exit 1; }
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid IOS_BUILD_NUMBER' >&2; exit 1; }
output="$project_root/iosApp/build"
archive="$output/HFUTSchedule.xcarchive"
mkdir -p "$output"
cd "$project_root/iosApp"
xcodegen generate
xcodebuild archive -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -derivedDataPath "$output/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

app="$archive/Products/Applications/HFUTSchedule.app"
test -d "$app"
# Verify real device architecture before packaging; simulator apps are not IPA payloads.
xcrun lipo "$app/HFUTSchedule" -verify_arch arm64
staging="$(mktemp -d "$output/ipa.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"
ditto "$app" "$staging/Payload/HFUTSchedule.app"
ipa="$output/HFUT-Schedule-iOS-$version-$build_number-unsigned.ipa"
ditto -c -k --sequesterRsrc --keepParent "$staging/Payload" "$ipa"
python3 "$project_root/iosApp/scripts/verify-ipa.py" "$ipa"
cd "$output"
shasum -a 256 "$(basename "$ipa")" > "$(basename "$ipa").sha256"
echo "IPA: $ipa (requires personal signing before installation)"
