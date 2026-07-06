#!/bin/bash
# Build Murmur.app from the SwiftPM package.
#
# Only the Xcode Command Line Tools are required (no full Xcode, no MLX/Metal
# toolchain — the LLM step runs in Ollama, out of process).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build (release)"
swift build -c release

APP="build/Murmur.app"
BIN="$(swift build -c release --show-bin-path)/Murmur"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Murmur"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Murmur</string>
    <key>CFBundleDisplayName</key>
    <string>Murmur</string>
    <key>CFBundleIdentifier</key>
    <string>com.skanparthy.murmur</string>
    <key>CFBundleExecutable</key>
    <string>Murmur</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Murmur records your voice while you hold the dictation hotkey, transcribes it locally, and types it into the app you are using. Audio never leaves this Mac.</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
PLIST

echo "==> codesigning (ad-hoc)"
codesign --force --sign - "$APP"

echo ""
echo "Built $APP"
echo "Run it with:  open $APP"
echo "First launch: grant Microphone + Accessibility when prompted, then hold Right Option (⌥) and speak."
