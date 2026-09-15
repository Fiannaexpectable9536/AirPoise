#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
VOL="AirPoise"
APP_NAME="AirPoise.app"
STAGE="$ROOT/dist/dmg-stage"
RW="$ROOT/dist/AirPoise-rw.dmg"
DMG="$ROOT/dist/AirPoise-${VERSION}.dmg"

killall AirPoise 2>/dev/null || true

"$ROOT/scripts/build-app.sh"

rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto "$ROOT/dist/AirPoise.app" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"
python3 "$ROOT/scripts/generate-dmg-bg.py"

rm -f "$RW" "$DMG"
hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -ov \
  "$RW" >/dev/null

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
DEV="$(echo "$ATTACH" | awk '/Apple_HFS/ { print $1; exit }')"
MOUNT="/Volumes/$VOL"

# Wait for Finder to see the volume.
for _ in {1..20}; do
  [[ -d "$MOUNT/$APP_NAME" ]] && break
  sleep 0.2
done

if [[ -d "$MOUNT/.background" ]]; then
  chflags hidden "$MOUNT/.background" 2>/dev/null || true
fi

osascript <<EOF || echo "NOTE: Finder layout skipped (DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 140, 860, 560}
    delay 0.3
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    try
      set background picture of opts to file ".background:dmg-bg.png"
    end try
    set position of item "$APP_NAME" of container window to {160, 240}
    set position of item "Applications" of container window to {500, 240}
    update without registering applications
    delay 1
    close
    open
    delay 0.5
  end tell
end tell
EOF

sync
hdiutil detach "$DEV" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

echo "wrote $DMG"
ls -lh "$DMG"
xattr -cr "$DMG" 2>/dev/null || true
