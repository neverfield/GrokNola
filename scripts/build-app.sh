#!/usr/bin/env bash
# Builds "build/GrokNola.app".
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
APP="build/GrokNola.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GrokNotes" "$APP/Contents/MacOS/GrokNotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Help "$APP/Contents/Resources/Help"

# The asset catalog gives native controls the amber accent. actool needs
# Xcode's first-launch setup (sudo xcodebuild -runFirstLaunch).
ASSETS_TMP="$(mktemp -d -t groknola-assets)"
PARTIAL_PLIST="$ASSETS_TMP/partial.plist"
if xcrun --find actool >/dev/null 2>&1 \
  && xcrun actool Resources/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --accent-color AccentColor \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    --output-format human-readable-text --notices --warnings --errors >/dev/null \
  && [ -f "$APP/Contents/Resources/Assets.car" ]; then
  :
else
  echo "" >&2
  echo "WARNING: actool could not compile Resources/Assets.xcassets." >&2
  echo "WARNING: The app will use the system accent color, not amber." >&2
  echo "WARNING: Run 'sudo xcodebuild -runFirstLaunch', then rebuild." >&2
  echo "" >&2
  rm -f "$APP/Contents/Resources/Assets.car"
  /usr/libexec/PlistBuddy -c "Delete :NSAccentColorName" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi
rm -rf "$ASSETS_TMP"

codesign --force --sign "$IDENTITY" "$APP"

# Install Cursor skill for Grok Notes calendar sync (idempotent overwrite).
CURSOR_SKILLS_DIR="${HOME}/.cursor/skills/grok-notes-calendar-sync"
REPO_SKILL_DIR="$(pwd)/skills/grok-notes-calendar-sync"
if [ -d "$REPO_SKILL_DIR" ]; then
  mkdir -p "$CURSOR_SKILLS_DIR"
  cp -R "$REPO_SKILL_DIR/." "$CURSOR_SKILLS_DIR/"
fi

echo "Built $APP"
