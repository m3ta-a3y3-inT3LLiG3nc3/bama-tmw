#!/bin/zsh
# Build a release .app bundle into dist/ and ad-hoc sign it. Local only; nothing is uploaded.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=dist/M3taOSConsole.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/M3taOSConsole" "$APP/Contents/MacOS/"
cp -R "$BIN/M3taOSConsole_ConsoleCore.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>M3ta-OS Console</string>
<key>CFBundleDisplayName</key><string>M3ta-OS Console</string>
<key>CFBundleIdentifier</key><string>os.m3ta.console</string>
<key>CFBundleExecutable</key><string>M3taOSConsole</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
P
codesign --force --deep -s - "$APP"
codesign --verify --verbose=1 "$APP"
echo "$APP"
