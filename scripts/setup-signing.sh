#!/bin/bash
# Creates (once) the self-signed certificate every MacUtils build is signed with, and puts it
# in a dedicated keychain so codesign can use it without prompts.
#
# Why: macOS remembers permissions such as Accessibility per app *signature*. Ad-hoc builds
# get a new identity every time; builds signed with one stable certificate keep the grant
# across updates.
#
# On another build Mac: copy ~/.mac-utils-signing from this one and run this script again.
set -euo pipefail
source "$(dirname "$0")/common.sh"

OPENSSL=/usr/bin/openssl   # LibreSSL writes .p12 files that `security import` accepts

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
umask 077

if [[ ! -f "$SIGNING_PASSWORD_FILE" ]]; then
    "$OPENSSL" rand -hex 24 > "$SIGNING_PASSWORD_FILE"
fi
PASSWORD="$(cat "$SIGNING_PASSWORD_FILE")"

if [[ ! -f "$SIGNING_P12" ]]; then
    step "Creating self-signed code-signing certificate \"$SIGNING_IDENTITY\""
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGNING_IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
    "$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
        -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$SIGNING_DIR/certificate.pem" 2>/dev/null
    "$OPENSSL" pkcs12 -export -name "$SIGNING_IDENTITY" \
        -inkey "$TMP/key.pem" -in "$SIGNING_DIR/certificate.pem" \
        -passout "pass:$PASSWORD" -out "$SIGNING_P12"
fi

step "Importing it into $SIGNING_KEYCHAIN"
if [[ -f "$SIGNING_KEYCHAIN" ]]; then
    security delete-keychain "$SIGNING_KEYCHAIN" 2>/dev/null || rm -f "$SIGNING_KEYCHAIN"
fi
security create-keychain -p "$PASSWORD" "$SIGNING_KEYCHAIN"
security set-keychain-settings "$SIGNING_KEYCHAIN"          # no auto-lock
security unlock-keychain -p "$PASSWORD" "$SIGNING_KEYCHAIN"
security import "$SIGNING_P12" -k "$SIGNING_KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

# codesign only searches keychains in the user's search list.
current=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [[ -n "$line" && "$line" != "$SIGNING_KEYCHAIN" ]] && current+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${current[@]}" "$SIGNING_KEYCHAIN"

FINGERPRINT="$("$OPENSSL" x509 -in "$SIGNING_DIR/certificate.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
cat <<EOF

Done. Signing identity "$SIGNING_IDENTITY" is ready.
  SHA-256: $FINGERPRINT

IMPORTANT: back up $SIGNING_DIR (e.g. to an encrypted USB stick or your password manager).
If it is lost, future releases can't be verified by installed copies and every Mac would
need a manual reinstall plus a new Accessibility grant.
EOF
