#!/bin/sh
# update-cacert.sh [CURL]
# Refresh tls/cacert.pem, the Mozilla root store as published by curl.se.
# Uses our own curl (tls/dist/bin/curl) when built, and trusts the current
# bundle to fetch the next one, so it also works on a G3/G4 with no modern TLS.
# The first run falls back to MacPorts curl and its CA bundle.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
CA=$HERE/cacert.pem
URL=https://curl.se/ca/cacert.pem
CURL=${1:-$HERE/dist/bin/curl}
[ -x "$CURL" ] || CURL=/opt/local/bin/curl
TRUST=""; [ -f "$CA" ] && TRUST="--cacert $CA"
T=${TMPDIR:-/tmp}/cacert.$$; mkdir -p "$T"; trap 'rm -rf "$T"' EXIT

"$CURL" -fsS $TRUST -o "$T/cacert.pem" "$URL"
"$CURL" -fsS $TRUST -o "$T/cacert.pem.sha256" "$URL.sha256"
want=$(awk '{print $1}' "$T/cacert.pem.sha256")
got=$(openssl dgst -sha256 "$T/cacert.pem" 2>/dev/null | sed 's/.*= //')
[ -n "$got" ] || got=$(shasum -a 256 "$T/cacert.pem" | awk '{print $1}')
[ "$want" = "$got" ] || { echo "update-cacert: checksum mismatch ($got != $want)" >&2; exit 1; }
n=$(grep -c "BEGIN CERTIFICATE" "$T/cacert.pem")
[ "$n" -gt 100 ] || { echo "update-cacert: only $n certificates, refusing" >&2; exit 1; }
date=$(sed -n 's/^## Certificate data from Mozilla as of: //p' "$T/cacert.pem")
if [ -f "$CA" ] && cmp -s "$CA" "$T/cacert.pem"; then
  echo "update-cacert: unchanged ($n roots, Mozilla data of $date)"
else
  mv "$T/cacert.pem" "$CA"
  echo "update-cacert: updated ($n roots, Mozilla data of $date)"
fi
