#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package_app.sh must run on macOS." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

swift test
swift build --configuration release --product MomentMonitor
bin_dir="$(swift build --configuration release --show-bin-path)"

app="$root/dist/Moment Monitor.app"
contents="$app/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"

rm -rf "$app" "$root/dist/MomentMonitor.zip"
mkdir -p "$macos" "$resources"
install -m 755 "$bin_dir/MomentMonitor" "$macos/MomentMonitor"
install -m 644 "$root/LICENSE" "$resources/LICENSE.txt"
install -m 644 "$root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
mkdir -p "$resources/MobileDashboard"
install -m 644 "$root/Sources/MomentMonitorCore/MobileDashboard/index.html" "$resources/MobileDashboard/index.html"
install -m 644 "$root/Sources/MomentMonitorCore/MobileDashboard/app.css" "$resources/MobileDashboard/app.css"
install -m 644 "$root/Sources/MomentMonitorCore/MobileDashboard/app.js" "$resources/MobileDashboard/app.js"

cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MomentMonitor</string>
  <key>CFBundleIdentifier</key>
  <string>com.timyeou.momentmonitor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Moment Monitor</string>
  <key>CFBundleDisplayName</key>
  <string>Moment Monitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.4.2</string>
  <key>CFBundleVersion</key>
  <string>6</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Timothy Yu</string>
</dict>
</plist>
PLIST

xattr -cr "$app" 2>/dev/null || true
codesign --force --deep --sign - "$app"
ditto -c -k --keepParent "$app" "$root/dist/MomentMonitor.zip"

echo "Built: $app"
echo "Archive: $root/dist/MomentMonitor.zip"
