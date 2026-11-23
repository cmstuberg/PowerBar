#!/bin/sh
# Fetch + verify + extract the pinned pianobar source into pianobar/src/, with our
# patches (patches/pianobar/*.diff) applied.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/src; PATCHES=$HERE/patches
. "$HERE/versions.sh"
. "$HERE/../tools/fetch-src.sh"
fetch_get pianobar "$PIANOBAR_URL" "$PIANOBAR_SHA256"
fetch_prepare pianobar "pianobar-$PIANOBAR_VERSION" \
  tar -xjf "$SRC/pianobar-$PIANOBAR_VERSION.tar.bz2" -C "$SRC"
