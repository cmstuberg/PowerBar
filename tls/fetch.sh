#!/bin/sh
# Fetch + verify + extract the pinned sources into tls/src/.
# Uses the MacPorts distfile cache when it holds the same file.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/versions.sh"
SRC=$HERE/src; mkdir -p "$SRC"
PATH=/opt/local/bin:$PATH

sha256() { openssl dgst -sha256 "$1" | sed 's/.*= //'; }

get() { # name url sha cachedir
  f=$SRC/$(basename "$2")
  if [ ! -f "$f" ] || [ "$(sha256 "$f")" != "$3" ]; then
    c=/opt/local/var/macports/distfiles/$4/$(basename "$2")
    if [ -f "$c" ] && [ "$(sha256 "$c")" = "$3" ]; then cp "$c" "$f"
    else curl -fL --retry 3 -o "$f" "$2"; fi
  fi
  got=$(sha256 "$f")
  [ "$got" = "$3" ] || { echo "fetch: $1 checksum mismatch: $got" >&2; rm -f "$f"; exit 1; }
  echo "fetch: $1 OK ($3)"
}

get openssl "$OPENSSL_URL" "$OPENSSL_SHA256" openssl3
get curl    "$CURL_URL"    "$CURL_SHA256"    curl
get zlib    "$ZLIB_URL"    "$ZLIB_SHA256"    zlib

# Extract and apply tls/patches/<pkg>/*.diff (-p1). A stamp file records the patch
# set; if patches change, the tree is re-extracted so they apply to a clean copy.
prepare() { # pkg dir extract-cmd...
  pkg=$1; dir=$SRC/$2; shift 2
  want=$(cat "$HERE"/patches/$pkg/*.diff 2>/dev/null | openssl dgst -sha256 | sed 's/.*= //')
  if [ -d "$dir" ] && [ "$(cat "$dir/.ppc-patches" 2>/dev/null)" = "$want" ]; then return; fi
  rm -rf "$dir"; "$@"
  for p in "$HERE"/patches/$pkg/*.diff; do
    [ -f "$p" ] || continue
    echo "fetch: $pkg: applying $(basename "$p")"
    patch -d "$dir" -p1 -s < "$p"
  done
  echo "$want" > "$dir/.ppc-patches"
}
prepare openssl "openssl-$OPENSSL_VERSION" tar -xzf "$SRC/openssl-$OPENSSL_VERSION.tar.gz" -C "$SRC"
prepare curl    "curl-$CURL_VERSION"       sh -c "xz -dc '$SRC/curl-$CURL_VERSION.tar.xz' | tar -xf - -C '$SRC'"
prepare zlib    "zlib-$ZLIB_VERSION"       sh -c "xz -dc '$SRC/zlib-$ZLIB_VERSION.tar.xz' | tar -xf - -C '$SRC'"
