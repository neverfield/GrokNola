#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in the login keychain.
# A stable signature lets macOS keep privacy permissions across rebuilds.
set -euo pipefail

NAME="Grok Notes Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(uuidgen)"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

LEGACY=()
if openssl version | grep -q "^OpenSSL 3"; then LEGACY=(-legacy); fi
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\"."
