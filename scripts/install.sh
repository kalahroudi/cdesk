#!/bin/bash
# Installs CDesk into /Applications from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/kalahroudi/cdesk/main/scripts/install.sh | bash
# Options (environment): CDESK_VERSION=v0.1.0 to pin a version, CDESK_DEST=~/Applications to change the folder.
# If no release exists yet, it builds from source (needs the Xcode command line tools).
set -euo pipefail

REPO="kalahroudi/cdesk"
DEST="${CDESK_DEST:-/Applications}"
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "CDesk is a macOS app."
[ "$(uname -m)" = "arm64" ] || say "Note: CDesk is built for Apple silicon. Intel Macs should build from source."
mkdir -p "$DEST" || die "Can't create $DEST"
[ -w "$DEST" ] || die "No permission to write to $DEST. Try CDESK_DEST=\$HOME/Applications"

TMP="$(mktemp -d)"
trap 'hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

API="https://api.github.com/repos/$REPO/releases/${CDESK_VERSION:+tags/$CDESK_VERSION}"
[ -n "${CDESK_VERSION:-}" ] || API="https://api.github.com/repos/$REPO/releases/latest"

say "Looking for the latest release"
if JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null)"; then
  DMG_URL="$(printf '%s' "$JSON" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*: *"//; s/"$//')"
  SUMS_URL="$(printf '%s' "$JSON" | grep -o '"browser_download_url": *"[^"]*SHA256SUMS"' | head -1 | sed 's/.*: *"//; s/"$//')"
fi

if [ -n "${DMG_URL:-}" ]; then
  NAME="$(basename "$DMG_URL")"
  say "Downloading $NAME"
  curl -fL --progress-bar -o "$TMP/$NAME" "$DMG_URL"
  if [ -n "${SUMS_URL:-}" ]; then
    curl -fsSL -o "$TMP/SHA256SUMS" "$SUMS_URL"
    EXPECT="$(grep " \*\?$NAME\$" "$TMP/SHA256SUMS" | awk '{print $1}')"
    ACTUAL="$(shasum -a 256 "$TMP/$NAME" | awk '{print $1}')"
    [ -n "$EXPECT" ] && [ "$EXPECT" = "$ACTUAL" ] || die "Checksum mismatch. The download may be damaged."
    say "Checksum OK"
  fi
  mkdir -p "$TMP/mnt"
  hdiutil attach "$TMP/$NAME" -nobrowse -readonly -mountpoint "$TMP/mnt" -quiet
  SRC="$TMP/mnt/CDesk.app"
else
  say "No release found. Building from source (a few minutes)"
  command -v swift >/dev/null || die "Install the Xcode command line tools first: xcode-select --install"
  git clone --depth 1 "https://github.com/$REPO.git" "$TMP/src"
  (cd "$TMP/src" && scripts/bundle.sh)
  SRC="$TMP/src/dist/CDesk.app"
fi

if pgrep -x CDesk >/dev/null; then say "Quitting the running CDesk"; osascript -e 'tell application "CDesk" to quit' 2>/dev/null || pkill -x CDesk || true; sleep 1; fi
rm -rf "$DEST/CDesk.app"
ditto "$SRC" "$DEST/CDesk.app"
say "Installed $DEST/CDesk.app"

command -v colima >/dev/null || say "Colima is not installed yet. CDesk will offer to install it (with Docker) on first launch."
open "$DEST/CDesk.app"
say "Done. Look for the cube icon in your menu bar."
