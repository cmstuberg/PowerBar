# Shared source fetching for third-party builds. Source it from a project's script:
#
#   HERE=...; SRC=$HERE/src; PATCHES=$HERE/patches
#   . "$HERE/../tools/fetch-src.sh"
#   fetch_get     name url sha256 [macports-distfile-dir]
#   fetch_prepare pkg dir extract-cmd...
#
# fetch_get downloads into $SRC (or copies from the MacPorts distfile cache when it
# holds the same file) and verifies the SHA-256. fetch_prepare extracts into
# $SRC/<dir> and applies $PATCHES/<pkg>/*.diff (-p1). A stamp records the patch
# set; when patches change, the tree is re-extracted so they apply to a clean copy.
PATH=/opt/local/bin:$PATH

fetch_sha256() { openssl dgst -sha256 "$1" | sed 's/.*= //'; }

fetch_get() { # name url sha cachedir
  mkdir -p "$SRC"
  f=$SRC/$(basename "$2")
  if [ ! -f "$f" ] || [ "$(fetch_sha256 "$f")" != "$3" ]; then
    c=/opt/local/var/macports/distfiles/${4:-none}/$(basename "$2")
    if [ -f "$c" ] && [ "$(fetch_sha256 "$c")" = "$3" ]; then cp "$c" "$f"
    else curl -fL --retry 3 -o "$f" "$2"; fi
  fi
  got=$(fetch_sha256 "$f")
  [ "$got" = "$3" ] || { echo "fetch: $1 checksum mismatch: $got" >&2; rm -f "$f"; exit 1; }
  echo "fetch: $1 OK ($3)"
}

fetch_prepare() { # pkg dir extract-cmd...
  pkg=$1; dir=$SRC/$2; shift 2
  want=$(cat "$PATCHES"/$pkg/*.diff 2>/dev/null | openssl dgst -sha256 | sed 's/.*= //')
  if [ -d "$dir" ] && [ "$(cat "$dir/.ppc-patches" 2>/dev/null)" = "$want" ]; then return; fi
  rm -rf "$dir"; "$@"
  for p in "$PATCHES"/$pkg/*.diff; do
    [ -f "$p" ] || continue
    echo "fetch: $pkg: applying $(basename "$p")"
    patch -d "$dir" -p1 -s < "$p"
  done
  echo "$want" > "$dir/.ppc-patches"
}
