#!/bin/zsh
# Build a release .app bundle into dist/ and sign it. Local only; nothing
# is uploaded, notarized, or submitted anywhere.
#
# Phase 1 fix F2/F3: the bundle id is the spec/original-scaffold id
# com.th3m3taway.m3taosconsole, and release builds are signed with the
# local "Developer ID Application" identity when one is installed
# (CODE_SIGN_IDENTITY overrides detection). Ad-hoc signing remains only
# as an explicit dev fallback and is announced loudly when used — TCC
# identity follows the bundle id + signing identity, so the vault-read
# acceptance must run on this signed build after relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=dist/M3taOSConsole.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/M3taOSConsole" "$APP/Contents/MacOS/"
cp -R "$BIN/M3taOSConsole_ConsoleCore.bundle" "$APP/Contents/Resources/"
cp -R Resources/brand "$APP/Contents/Resources/brand"
cp Resources/theme/icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>M3ta-OS Console</string>
<key>CFBundleDisplayName</key><string>M3ta-OS Console</string>
<key>CFBundleIdentifier</key><string>com.th3m3taway.m3taosconsole</string>
<key>CFBundleExecutable</key><string>M3taOSConsole</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsUsageDescription</key><string>The Lookout reads today's events from your allowlisted (business) calendar only.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>The Lookout reads today's events from your allowlisted (business) calendar only.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
P
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
if [[ -n "$IDENTITY" ]]; then
  echo "Signing with Developer ID identity: $IDENTITY"
  # NO hardened runtime (--options runtime) — measured root cause,
  # 2026-11-09: a NON-notarized Developer ID app signed WITH the hardened
  # runtime gets its TCC privacy prompts silently suppressed on macOS 26
  # (requestFullAccessToEvents returns false instantly, authorization
  # status never leaves notDetermined, no prompt, no Settings entry — the
  # Lookout calendar panel could never be granted). The identical binary
  # signed Developer ID WITHOUT the runtime option, or ad-hoc, prompts
  # and grants normally (bisect evidence in the Phase 2 build report).
  # This build is local-only and never notarized (Phase 1 posture), so
  # the hardened runtime bought nothing here and cost the permission
  # flow. If the app is ever notarized for distribution, revisit.
  if ! codesign --force --deep -s "$IDENTITY" "$APP"; then
    echo "codesign failed in this session. Over SSH the login keychain is not" >&2
    echo "interaction-available (errSecInternalComponent); re-run this script" >&2
    echo "in a local Terminal window on the Mac, where the key is usable." >&2
    exit 1
  fi
else
  echo "WARNING: no Developer ID Application identity found — falling back to ad-hoc signing (dev build only, not a release build)" >&2
  codesign --force --deep -s - "$APP"
fi
codesign --verify --verbose=1 "$APP"
echo "$APP"
