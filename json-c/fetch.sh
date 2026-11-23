#!/bin/sh
# Fetch + verify + extract the pinned json-c source into json-c/src/.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/src; PATCHES=$HERE/patches
. "$HERE/versions.sh"
. "$HERE/../tools/fetch-src.sh"
fetch_get json-c "$JSONC_URL" "$JSONC_SHA256" json-c
fetch_prepare json-c "json-c-$JSONC_VERSION" tar -xzf "$SRC/json-c-$JSONC_VERSION-nodoc.tar.gz" -C "$SRC"
