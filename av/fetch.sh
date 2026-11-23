#!/bin/sh
# Fetch + verify + extract the pinned ffmpeg source into av/src/.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/src; PATCHES=$HERE/patches
. "$HERE/versions.sh"
. "$HERE/../tools/fetch-src.sh"
fetch_get ffmpeg "$FFMPEG_URL" "$FFMPEG_SHA256" ffmpeg6
fetch_prepare ffmpeg "ffmpeg-$FFMPEG_VERSION" \
  sh -c "xz -dc '$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz' | tar -xf - -C '$SRC'"
