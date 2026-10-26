#!/bin/bash
# Builds a universal (Apple silicon + Intel) MacUtils.app and MacUtils.zip in ./build.
#
#   scripts/build.sh            sign with the stable self-signed identity (see setup-signing.sh)
#   scripts/build.sh --adhoc    ad-hoc signature for quick local testing; can't self-update
set -euo pipefail
source "$(dirname "$0")/common.sh"

MODE=stable
[[ "${1:-}" == "--adhoc" ]] && MODE=adhoc

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

rm -rf "$OUT"
mkdir -p "$OUT"

ARCHS=(--arch arm64 --arch x86_64)
step "Compiling (arm64 + x86_64)"
swift build --package-path "$ROOT" -c release "${ARCHS[@]}"
BINARY="$(swift build --package-path "$ROOT" -c release "${ARCHS[@]}" --show-bin-path)/$APP_NAME"
[[ "$(lipo -archs "$BINARY")" == *arm64* && "$(lipo -archs "$BINARY")" == *x86_64* ]] || die "expected a universal binary at $BINARY"

step "Assembling $APP_NAME.app $VERSION ($BUILD_NUMBER)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD_NUMBER|g" \
    -e "s|__MIN_MACOS__|$MIN_MACOS|g" \
    -e "s|__GITHUB_REPO__|$GITHUB_REPO|g" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
# Icon: Resources/AppIcon.icns as-is, or generated from a 1024x1024 Resources/AppIcon.png.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
elif [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    ICONSET="$OUT/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

step "Signing ($MODE)"
if [[ "$MODE" == stable ]]; then
    [[ -f "$SIGNING_KEYCHAIN" ]] || die "no signing keychain. Run scripts/setup-signing.sh first (or build with --adhoc)."
    security unlock-keychain -p "$(cat "$SIGNING_PASSWORD_FILE")" "$SIGNING_KEYCHAIN"
    codesign --force --options runtime --timestamp=none \
        --keychain "$SIGNING_KEYCHAIN" --sign "$SIGNING_IDENTITY" \
        --identifier "$BUNDLE_ID" "$APP"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

if [[ "$MODE" == stable ]]; then
    REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
    if [[ ! -f "$EXPECTED_REQUIREMENT_FILE" ]]; then
        mkdir -p "$(dirname "$EXPECTED_REQUIREMENT_FILE")"
        echo "$REQUIREMENT" > "$EXPECTED_REQUIREMENT_FILE"
        echo "Recorded the signing requirement in signing/designated-requirement.txt — commit it."
    elif [[ "$(cat "$EXPECTED_REQUIREMENT_FILE")" != "$REQUIREMENT" ]]; then
        die "this build's signature doesn't match signing/designated-requirement.txt.
Installed copies would reject it as an update and lose their permissions.
  expected: $(cat "$EXPECTED_REQUIREMENT_FILE")
  got:      $REQUIREMENT
Restore the original ~/.mac-utils-signing folder from your backup."
    fi
fi

step "Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$APP_NAME.zip"
echo "Built $OUT/$APP_NAME.zip"
