# Sourced by the other scripts.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT/config.env"

# The signing identity lives outside the repo. Back this folder up: losing it means the
# next release is signed differently and Accessibility must be granted again on every Mac.
SIGNING_DIR="${MACUTILS_SIGNING_DIR:-$HOME/.mac-utils-signing}"
SIGNING_KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
SIGNING_PASSWORD_FILE="$SIGNING_DIR/password.txt"
SIGNING_P12="$SIGNING_DIR/identity.p12"
EXPECTED_REQUIREMENT_FILE="$ROOT/signing/designated-requirement.txt"

die() {
    echo "error: $*" >&2
    exit 1
}

step() {
    printf '\n==> %s\n' "$*"
}
