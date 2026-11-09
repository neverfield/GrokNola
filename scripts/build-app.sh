#!/usr/bin/env bash
# Builds "build/GrokNola.app".
# macOS ties privacy permissions to the code signature. An ad-hoc signature
# changes on every rebuild, so permissions are lost. The script signs with
# CODESIGN_IDENTITY, else the certificate in the signing keychain from
# create-signing-cert.sh, else the same certificate in the login keychain, else ad-hoc.
# The signing keychain is unlocked (asking for its password) only while signing.
# Set INSTALL_CURSOR_SKILL=1 to also install the calendar-sync skill into Cursor.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
CERT_NAME="Grok Notes Local Signing"
SIGN_KC="$HOME/Library/Keychains/groknola-signing.keychain-db"
ENTITLEMENTS="Resources/GrokNola.entitlements"
APP="build/GrokNola.app"

# The macOS 26 window style appears only in apps built with the macOS 26 SDK.
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || echo unknown)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if ! [[ "$SDK_MAJOR" =~ ^[0-9]+$ ]] || [ "$SDK_MAJOR" -lt 26 ]; then
  echo "warning: built with SDK $SDK_VERSION; on macOS 26 the window will use the older style. Use Xcode 26 or later." >&2
fi

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

identity_hash() {
  awk -v name="\"$CERT_NAME\"" 'index($0, name) { print $2; exit }'
}

ORIGINAL_KEYCHAINS=()
SIGN_KC_OPENED=0
close_signing_keychain() {
  [ "$SIGN_KC_OPENED" = 1 ] || return 0
  SIGN_KC_OPENED=0
  security lock-keychain "$SIGN_KC" 2>/dev/null || true
  security list-keychains -d user -s ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"} || true
}

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ -f "$SIGN_KC" ]; then
  while IFS= read -r line; do
    line="$(echo "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
    [ -n "$line" ] && ORIGINAL_KEYCHAINS+=("$line")
  done < <(security list-keychains -d user)
  SIGN_KC_OPENED=1
  trap close_signing_keychain EXIT
  trap 'exit 130' INT TERM

  # codesign finds the identity only through the user search list.
  IN_LIST=0
  for kc in ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"}; do
    [ "$kc" = "$SIGN_KC" ] && IN_LIST=1
  done
  if [ "$IN_LIST" = 0 ]; then
    security list-keychains -d user -s ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"} "$SIGN_KC"
  fi
  echo "Unlock the GrokNola signing keychain to sign the app:"
  if [ -t 0 ]; then
    security unlock-keychain "$SIGN_KC"
  else
    security unlock-keychain -u "$SIGN_KC"
  fi
  IDENTITY="$(security find-identity -p codesigning "$SIGN_KC" 2>/dev/null | identity_hash || true)"
  if [ -z "$IDENTITY" ]; then
    echo "warning: no \"$CERT_NAME\" identity in $SIGN_KC. Run scripts/create-signing-cert.sh." >&2
    close_signing_keychain
  fi
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null | identity_hash || true)"
  if [ -n "$IDENTITY" ]; then
    echo "warning: signing with \"$CERT_NAME\" from the login keychain, which any app can use without asking." >&2
    echo "warning: Run scripts/create-signing-cert.sh to move it to a locked signing keychain." >&2
  fi
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "warning: ad-hoc signing. Run scripts/create-signing-cert.sh to keep permissions across rebuilds." >&2
fi

codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
close_signing_keychain

# The calendar-sync skill is installed into Cursor only on request, and a changed copy only after review.
CURSOR_SKILLS_DIR="${HOME}/.cursor/skills/grok-notes-calendar-sync"
REPO_SKILL_DIR="$(pwd)/skills/grok-notes-calendar-sync"
if [ -d "$REPO_SKILL_DIR" ]; then
  if [ "${INSTALL_CURSOR_SKILL:-0}" = "1" ]; then
    INSTALL=1
    if [ -d "$CURSOR_SKILLS_DIR" ]; then
      if diff -rq "$CURSOR_SKILLS_DIR" "$REPO_SKILL_DIR" >/dev/null 2>&1; then
        INSTALL=0
        echo "Cursor skill is up to date."
      else
        echo "The installed Cursor skill differs from the repo copy:"
        diff -r "$CURSOR_SKILLS_DIR" "$REPO_SKILL_DIR" || true
        INSTALL=0
        if [ -t 0 ]; then
          read -r -p "Replace the installed skill with the repo copy? [y/N] " answer
          case "$answer" in [yY]*) INSTALL=1 ;; esac
        else
          echo "Not a terminal; left the installed skill unchanged."
        fi
      fi
    fi
    if [ "$INSTALL" = 1 ]; then
      mkdir -p "$CURSOR_SKILLS_DIR"
      cp -R "$REPO_SKILL_DIR/." "$CURSOR_SKILLS_DIR/"
      echo "Installed the Cursor skill in $CURSOR_SKILLS_DIR."
    fi
  else
    echo "Cursor calendar-sync skill not installed. To install it: INSTALL_CURSOR_SKILL=1 ./scripts/build-app.sh"
  fi
fi

echo "Built $APP"
