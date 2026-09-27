#!/bin/bash
# A DEBUG-only, in-memory component catalog. Never installs or closes the user's app.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
catalog_data="${NORKA_MAC_DERIVED_DATA:-/tmp/NorkaInstallData}"
xcodebuild -project Memory.xcodeproj -scheme Memory -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$catalog_data" build -quiet
open -n "$catalog_data/Build/Products/Debug/Norka.app" --args --design-catalog
