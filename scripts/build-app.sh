#!/usr/bin/env bash
# Builds "build/Grok Notes.app".
# macOS ties privacy permissions to the code signature. An ad-hoc signature
# changes on every rebuild, so permissions are lost. The script signs with
# CODESIGN_IDENTITY, else the certificate from create-signing-cert.sh, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
LOCAL_CERT_HASH="$(security find-identity -p codesigning 2>/dev/null | awk '/"Grok Notes Local Signing"/ { print $2; exit }')"
IDENTITY="${CODESIGN_IDENTITY:-${LOCAL_CERT_HASH:--}}"
if [ "$IDENTITY" = "-" ]; then
  echo "warning: ad-hoc signing. Run scripts/create-signing-cert.sh to keep permissions across rebuilds." >&2
fi
APP="build/Grok Notes.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GrokNotes" "$APP/Contents/MacOS/GrokNotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"
