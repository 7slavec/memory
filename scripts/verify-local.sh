#!/bin/bash
# No installs, backend deploys, cache deletion, or user-data resets.
set -euo pipefail

run_ui=false
case "${1:-}" in
  "") ;;
  --ui) run_ui=true ;;
  *) echo "Usage: bash scripts/verify-local.sh [--ui]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: bash scripts/verify-local.sh [--ui]" >&2
  exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mac_data="${NORKA_MAC_DERIVED_DATA:-/tmp/NorkaInstallData}"
ios_data="${NORKA_IOS_DERIVED_DATA:-/tmp/NorkaDeviceData}"
report_dir="$(mktemp -d /tmp/norka-verification.XXXXXX)"
echo "Verification reports: $report_dir"

run_check() {
  local name="$1"
  shift
  echo "Running $name"
  if "$@" > "$report_dir/$name.log" 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name — $report_dir/$name.log" >&2
    tail -n 35 "$report_dir/$name.log" >&2
    return 1
  fi
}

run_check diff git diff --check
run_check mac-unit xcodebuild -project Memory.xcodeproj -scheme Memory \
  -destination 'platform=macOS' -derivedDataPath "$mac_data" \
  -resultBundlePath "$report_dir/mac-unit.xcresult" \
  -only-testing:MemoryTests test -quiet
run_check ios-build xcodebuild -project Memory.xcodeproj -scheme Memory \
  -destination 'generic/platform=iOS' -derivedDataPath "$ios_data" \
  CODE_SIGNING_ALLOWED=NO build -quiet

if [[ "$run_ui" == true ]]; then
  run_check mac-ui xcodebuild -project Memory.xcodeproj -scheme Memory \
    -destination 'platform=macOS' -derivedDataPath "$mac_data" \
    -resultBundlePath "$report_dir/mac-ui.xcresult" \
    -only-testing:MemoryUITests/MemoryUITests/testVoiceReviewUsesOnePageAndReturnsFromEachRecord \
    test -quiet
fi

echo "Completed. Builds/tests only; no device installation or live-service verification."
