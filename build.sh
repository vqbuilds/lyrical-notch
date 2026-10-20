#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="$PWD/build/Lyrical Notch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 644 .build/checkouts/Yams/LICENSE "$APP/Contents/Resources/Yams-LICENSE.txt"
install -m 644 docs/LibYAML-LICENSE.txt "$APP/Contents/Resources/LibYAML-LICENSE.txt"
install -m 644 docs/QQMusicDecoder-LICENSE.txt "$APP/Contents/Resources/QQMusicDecoder-LICENSE.txt"
install -m 644 LICENSE "$APP/Contents/Resources/LyricalNotch-LICENSE.txt"
install -m 644 THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp .build/release/LyricalNotch "$APP/Contents/MacOS/LyricalNotch"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LyricalNotch</string>
<key>CFBundleIdentifier</key><string>local.notchletras.personal</string>
<key>CFBundleName</key><string>Lyrical Notch</string>
<key>CFBundleDisplayName</key><string>Lyrical Notch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.3</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Lyrical Notch necesita leer la canción y su posición y controlar Spotify o Música para mostrar las letras sincronizadas.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/LyricalNotch" --self-test
mkdir -p dist
ditto -c -k --keepParent "$APP" dist/Lyrical-Notch-0.5.3-macos.zip
print "App creada: $APP"
