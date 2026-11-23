#!/bin/sh
# Fetch + verify + extract the pinned Sparkle source into sparkle/src/, with our
# patches (patches/sparkle/*.diff) applied.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/src; PATCHES=$HERE/patches
. "$HERE/versions.sh"
. "$HERE/../tools/fetch-src.sh"
fetch_get sparkle "$SPARKLE_URL" "$SPARKLE_SHA256"
fetch_prepare sparkle "Sparkle-$SPARKLE_COMMIT" \
  tar -xzf "$SRC/$SPARKLE_COMMIT.tar.gz" -C "$SRC"
