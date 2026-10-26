#!/bin/bash
# MacUtils installer / updater / uninstaller.
#
#   curl -fsSL https://raw.githubusercontent.com/llipovsky/mac-utils/main/install.sh | bash
#
# Pass options after `bash -s --` when piping, e.g. `... | bash -s -- --user`.
#   --user          install for this user only (~/Applications), even if /Applications is writable
#   --zip PATH      install from a local MacUtils.zip instead of the latest GitHub release
#   --uninstall     remove MacUtils (add --purge to also delete its settings and scripts)
#
# Run it from an admin account the first time: MacUtils then goes into /Applications for
# every user, and stays writable for all local users so the built-in updater works for them.
set -euo pipefail

REPO="${MACUTILS_REPO:-llipovsky/mac-utils}"
APP_NAME="MacUtils"
BUNDLE_ID="io.github.llipovsky.macutils"
ACCESSIBILITY_URL="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

SCOPE=auto
ZIP=""
ACTION=install
PURGE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) SCOPE=user ;;
        --zip) ZIP="${2:?--zip needs a path}"; shift ;;
        --uninstall) ACTION=uninstall ;;
        --purge) PURGE=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

SHARED_APP="/Applications/$APP_NAME.app"
USER_APP="$HOME/Applications/$APP_NAME.app"

quit_running() {
    if pgrep -xq -u "$(id -u)" "$APP_NAME"; then
        say "Quitting the running MacUtils…"
        pkill -x -u "$(id -u)" "$APP_NAME" || true
        for _ in $(seq 1 25); do
            pgrep -xq -u "$(id -u)" "$APP_NAME" || break
            sleep 0.2
        done
    fi
}

if [[ "$ACTION" == uninstall ]]; then
    quit_running
    for app in "$SHARED_APP" "$USER_APP"; do
        if [[ -d "$app" ]]; then
            if rm -rf "$app" 2>/dev/null; then say "Removed $app"; else say "Couldn't remove $app (needs an admin account)."; fi
        fi
    done
    if [[ "$PURGE" == 1 ]]; then
        defaults delete "$BUNDLE_ID" 2>/dev/null || true
        rm -rf "$HOME/Library/Application Support/MacUtils"
        say "Removed settings and scripts for $(id -un)."
    fi
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    say "MacUtils uninstalled."
    exit 0
fi

# Where to install: update an existing copy in place; otherwise prefer the shared location.
if [[ "$SCOPE" == user ]]; then
    TARGET="$USER_APP"
elif [[ -d "$SHARED_APP" && -w "$SHARED_APP" ]]; then
    TARGET="$SHARED_APP"
elif [[ -d "$SHARED_APP" ]]; then
    die "$SHARED_APP exists but isn't writable by $(id -un). Run this installer from an admin account."
elif [[ -w /Applications ]]; then
    TARGET="$SHARED_APP"
else
    TARGET="$USER_APP"
fi
SHARED=0
[[ "$TARGET" == "$SHARED_APP" ]] && SHARED=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -n "$ZIP" ]]; then
    cp "$ZIP" "$WORK/$APP_NAME.zip"
else
    URL="https://github.com/$REPO/releases/latest/download/$APP_NAME.zip"
    say "Downloading $URL"
    curl -fL --progress-bar -o "$WORK/$APP_NAME.zip" "$URL" || die "download failed. Is there a published release in $REPO?"
fi

ditto -x -k "$WORK/$APP_NAME.zip" "$WORK/extracted"
NEW_APP="$WORK/extracted/$APP_NAME.app"
[[ -d "$NEW_APP" ]] || die "the archive doesn't contain $APP_NAME.app"
codesign --verify --strict "$NEW_APP" || die "the downloaded app's signature is broken."
xattr -cr "$NEW_APP"

FRESH=1
if [[ -d "$TARGET" ]]; then
    FRESH=0
    # Same check the in-app updater does: the new build must satisfy the installed one's
    # signing requirement, otherwise macOS would treat it as a different app.
    REQUIREMENT="$(codesign -d -r- "$TARGET" 2>&1 | sed -n 's/^designated => //p')"
    if [[ -n "$REQUIREMENT" && "$REQUIREMENT" != cdhash* ]]; then
        codesign --verify -R="$REQUIREMENT" "$NEW_APP" 2>/dev/null \
            || die "the new build is signed by a different certificate than the installed one. Uninstall first if that's intended (permissions will need to be granted again)."
    fi
fi

quit_running
mkdir -p "$(dirname "$TARGET")"
if [[ "$FRESH" == 1 ]]; then
    ditto "$NEW_APP" "$TARGET"
else
    # Swap Contents/ so only the bundle folder itself needs to be writable.
    OLD="$TARGET/Contents.old-$$"
    mv "$TARGET/Contents" "$OLD"
    if ! ditto "$NEW_APP/Contents" "$TARGET/Contents"; then
        rm -rf "$TARGET/Contents"; mv "$OLD" "$TARGET/Contents"
        die "couldn't copy the new version into $TARGET"
    fi
    rm -rf "$OLD"
fi

if [[ "$SHARED" == 1 ]]; then
    # Every local user is in "staff": let all of them update the shared copy.
    chgrp -R staff "$TARGET" 2>/dev/null || true
    chmod -R g+w "$TARGET" 2>/dev/null || true
fi
touch "$TARGET"

VERSION="$(defaults read "$TARGET/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?')"
say ""
say "Installed MacUtils $VERSION to $TARGET"
open "$TARGET"

if [[ "$FRESH" == 1 ]]; then
    cat <<EOF

Next: allow Accessibility so the mouse jiggler can send real mouse events
(keep-awake works without it).
  System Settings › Privacy & Security › Accessibility › turn on "MacUtils"
It needs an admin password once; after that it applies to every user on this Mac
and survives MacUtils updates.
EOF
    open "$ACCESSIBILITY_URL" 2>/dev/null || true
fi
