#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="$PWD/build/Notch Letras.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 644 .build/checkouts/Yams/LICENSE "$APP/Contents/Resources/Yams-LICENSE.txt"
install -m 644 docs/LibYAML-LICENSE.txt "$APP/Contents/Resources/LibYAML-LICENSE.txt"
install -m 644 docs/QQMusicDecoder-LICENSE.txt "$APP/Contents/Resources/QQMusicDecoder-LICENSE.txt"
install -m 644 LICENSE "$APP/Contents/Resources/NotchLetras-LICENSE.txt"
install -m 644 THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp .build/release/NotchLetras "$APP/Contents/MacOS/NotchLetras"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NotchLetras</string>
<key>CFBundleIdentifier</key><string>local.notchletras.personal</string>
<key>CFBundleName</key><string>Notch Letras</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.2</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Notch Letras necesita leer la canción y su posición y controlar Spotify o Música para mostrar las letras sincronizadas.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/NotchLetras" --self-test
mkdir -p dist
ditto -c -k --keepParent "$APP" dist/Notch-Letras-0.5.2-macos.zip
print "App creada: $APP"
