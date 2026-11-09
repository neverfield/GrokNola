#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in a dedicated keychain.
# A stable signature lets macOS keep privacy permissions across rebuilds.
# The keychain has its own password and stays locked except while build-app.sh signs,
# so other apps cannot sign code as GrokNola without you knowing.
set -euo pipefail

NAME="Grok Notes Local Signing"
KEYCHAIN="$HOME/Library/Keychains/groknola-signing.keychain-db"
LOGIN="$HOME/Library/Keychains/login.keychain-db"

has_identity() {
  [ -f "$1" ] && security find-identity -p codesigning "$1" 2>/dev/null | grep -q "\"$NAME\""
}

if ! [ -t 0 ]; then
  echo "Run this script in a terminal. It asks for the signing keychain's password." >&2
  exit 1
fi

CREATED=0
if has_identity "$KEYCHAIN"; then
  echo "\"$NAME\" already exists in $KEYCHAIN."
else
  # create-keychain adds the keychain to the search list; put the list back afterwards.
  ORIGINAL_KEYCHAINS=()
  while IFS= read -r line; do
    line="$(echo "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
    [ -n "$line" ] && ORIGINAL_KEYCHAINS+=("$line")
  done < <(security list-keychains -d user)

  umask 077
  TMP="$(mktemp -d -t groknola-signing)"
  cleanup() {
    rm -f "$TMP/key.pem" "$TMP/cert.pem"
    rmdir "$TMP" 2>/dev/null || true
    security lock-keychain "$KEYCHAIN" 2>/dev/null || true
    security list-keychains -d user -s ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"} || true
  }
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  if [ ! -f "$KEYCHAIN" ]; then
    echo "Choose a password for the GrokNola signing keychain. Use a new one, not your login password."
    echo "build-app.sh asks for it each time it signs the app."
    security create-keychain "$KEYCHAIN"
  fi
  # Lock after 5 minutes and on sleep.
  security set-keychain-settings -l -u -t 300 "$KEYCHAIN"
  echo "Unlock the signing keychain:"
  security unlock-keychain "$KEYCHAIN"

  openssl req -x509 -newkey rsa:2048 -nodes -days 730 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

  security import "$TMP/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
  security import "$TMP/cert.pem" -k "$KEYCHAIN"
  echo "Enter the signing keychain's password once more so codesign can use the key without a dialog:"
  security set-key-partition-list -S apple-tool:,apple: -s "$KEYCHAIN" >/dev/null

  cleanup
  trap - EXIT INT TERM
  CREATED=1
  echo "Created \"$NAME\" in $KEYCHAIN. The keychain is locked."
fi

if has_identity "$LOGIN"; then
  echo ""
  echo "An older \"$NAME\" identity is also in your login keychain."
  echo "The login keychain is unlocked while you are logged in, so any app can use that identity"
  echo "to sign code as GrokNola without asking. build-app.sh no longer needs it."
  read -r -p "Remove it from the login keychain? [y/N] " answer
  case "$answer" in
    [yY]*) security delete-identity -c "$NAME" "$LOGIN" && echo "Removed it from the login keychain." ;;
    *) echo "Kept it. Remove it later with: security delete-identity -c \"$NAME\" \"$LOGIN\"" ;;
  esac
fi

if [ "$CREATED" = 1 ]; then
  echo ""
  echo "Next: run ./scripts/build-app.sh. The new signature differs from the old one, so macOS asks"
  echo "once more for Microphone, Screen & System Audio Recording, Accessibility, and Calendar."
  echo "Turn GrokNola back on in System Settings > Privacy & Security if it does not ask."
fi
