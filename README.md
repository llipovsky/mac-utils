# MacUtils

A small menu bar app for my own Macs. Current features:

- **Keep Awake**: indefinite or timed sessions (5 min – 12 h, or until a set time), optionally
  letting the display sleep, keeping chat apps from showing "Away", and stopping on low battery.
  Needs no permissions, so it works for standard (non-admin) users.
- **Mouse Jiggler**: built-in patterns (Zen, Subtle, Nudge, Circle, Square, Zigzag, Wander) or
  your own `.jiggle` scripts. It skips turns while you're using the Mac and stops the moment you
  touch the mouse.
- **Self-update** from GitHub Releases, keeping the Accessibility permission.

Planned: clipboard history (Maccy-style), window snapping and shortcuts (Rectangle-style), CPU temperature.

## Install on a Mac

From an **admin** account, the first time:

```bash
curl -fsSL https://raw.githubusercontent.com/llipovsky/mac-utils/main/install.sh | bash
```

This installs to `/Applications/MacUtils.app`, so it's available to every user. It then opens
System Settings › Privacy & Security › Accessibility, where you turn on **MacUtils** once.
That grant applies to all users on the Mac and survives updates.

Without admin rights the same command installs to `~/Applications` for that user only.
Other options: `bash -s -- --user`, `--zip PATH`, `--uninstall [--purge]`.

## Updates

MacUtils checks GitHub every few hours (Settings › General) and shows **Install Update…** in its
menu. Any local user can install updates, because the installer makes the app group-writable
for `staff`. An update is only installed if it's signed with the same certificate as the
running copy, which is also why macOS keeps the Accessibility permission across updates.

## Control from Terminal / Shortcuts

```bash
open -g "macutils://awake?minutes=90"     # or hours=2, or no argument for the default length
open -g "macutils://stop"
open -g "macutils://jiggle?state=on&pattern=circle&interval=30"   # state=off|toggle|once
open -g "macutils://status"   # writes ~/Library/Application Support/MacUtils/status.json
```

## Jiggle scripts

Put `.jiggle` files in `~/Library/Application Support/MacUtils/Scripts`. The menu item
Pattern › Open Scripts Folder opens it. That folder also has `README.txt` with every command:

```
move 40 0 over 0.3
circle 20 over 0.8
repeat 2
  random 60 over 0.4
  wait 0.2-0.6
end
back over 0.4
```

## Development

Requires Xcode or the Command Line Tools (Swift 5.9+).

```bash
scripts/setup-signing.sh    # once per build Mac: creates the self-signed certificate
scripts/build.sh            # build/MacUtils.app + build/MacUtils.zip (universal)
./install.sh --zip build/MacUtils.zip
scripts/release.sh          # bump version, build, tag, publish a GitHub release
```

**Back up `~/.mac-utils-signing/`.** Every release must be signed by that certificate. If it's lost,
installed copies will refuse new releases and you'll need to reinstall manually and grant
Accessibility again. `signing/designated-requirement.txt` records the expected signature, and
`build.sh` refuses to produce a build that doesn't match it.

Notes:
- It's self-signed, not notarized. That's fine because `curl` downloads aren't quarantined, so
  Gatekeeper never blocks the app. Don't download the zip with a browser; use the installer.
- Closing a laptop's lid still sleeps it unless it's on power with an external display connected.
  Preventing that needs admin rights (`pmset`), so it isn't included.
