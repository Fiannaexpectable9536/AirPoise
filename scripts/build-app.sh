#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/.build/release/AirPoise"
APP="$ROOT/dist/AirPoise.app"
ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

python3 "$ROOT/scripts/generate-icon.py"
iconutil -c icns "$ICONSET" -o "$ICNS"

swift build -c release --product AirPoise

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AirPoise"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/AirPoise.entitlements" "$APP/Contents/Resources/AirPoise.entitlements"
mkdir -p "$APP/Contents/Resources/Onboarding"
cp "$ROOT/Resources/Onboarding/"*.png "$APP/Contents/Resources/Onboarding/"
cp "$ROOT/Resources/Fonts/"*.ttf "$APP/Contents/Resources/"
cat > "$APP/Contents/PkgInfo" <<'EOF'
APPL????
EOF

# TCC (Motion/Accessibility permissions) is keyed to the code signature's
# designated requirement. Ad-hoc signing (-) needs a fresh binary-hash entry per
# build, so macOS re-prompts every time. A stable Apple Development identity
# survives rebuilds: grant once, it sticks. Use it if present; fall back to a
# persistent self-signed dev cert, else ad-hoc.
APPLE_DEV="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
CERT_NAME="AirPoise Dev"

choose_sign() {
    if [ -n "$APPLE_DEV" ]; then
        echo "$APPLE_DEV"; return
    fi
    if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
        echo "$CERT_NAME"; return
    fi
    echo "-"
}

if [ -z "$APPLE_DEV" ]; then
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
        echo "creating persistent self-signed dev identity (one-time)…"
        TMP="$(mktemp -d)"
        cat > "$TMP/airpoise.cfg" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = AirPoise Dev
[ ext ]
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical,CA:false
subjectKeyIdentifier = hash
EOF
        openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
            -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/airpoise.cfg" >/dev/null 2>&1
        openssl pkcs12 -export -legacy -out "$TMP/id.p12" \
            -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -password pass:airpoise-p12 >/dev/null 2>&1
        # pass:airpoise-p12 is a local dummy so openssl will export the throwaway
        # self-signed identity. It is not an account password. Files stay in $TMP.
        security import "$TMP/id.p12" -P airpoise-p12 -T /usr/bin/codesign 2>/dev/null \
            && echo "identity installed" \
            || echo "NOTE: self-signed import unavailable; building ad-hoc (will ask once per install)"
        rm -rf "$TMP"
    fi
fi

SIGN="$(choose_sign)"

/usr/bin/codesign --force --deep --sign "$SIGN" \
  --entitlements "$ROOT/Resources/AirPoise.entitlements" \
  "$APP"

echo "built $APP (signed: $SIGN)"
echo "launch with:  open '$APP'"
