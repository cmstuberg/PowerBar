#!/bin/sh
# nettest.sh APP [full|quick]
# Sparkle's networking and DSA checks, run through SparkleTest.app (APP is its
# executable) in a logged-in GUI session. A local test CA + HTTPS server
# (https-server.py) covers redirects, downgrades, errors, timeouts and release
# notes; two checks go to GitHub for real (skip them with PPC_OFFLINE=1).
# "quick" (used per slice) runs the core subset.
set -u
APP=$1
MODE=${2:-full}
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$HERE/../..
SRC=$(cd "$HERE/.." && ls -d src/Sparkle-*/ | head -1)
SRC=$HERE/../$SRC
OPENSSL=$TOP/tls/dist/bin/openssl
GUIRUN=$TOP/tools/gui-run
PY=/opt/local/bin/python2.7
W=$HERE/build/net-$$
PA=18443; PB=18444; PC=18080
pass=0; fail=0

ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

# run NAME ENV-CA ARGS...: runs the app in the GUI session, output in $out, status in $rc.
# ENV-CA is "test" (trust the test CA) or "real" (the framework's own cacert.pem).
# RUNAPP (default APP) is the executable to run.
run() {
  ca=$2; shift 2
  if [ "$ca" = test ]; then
    out=$("$GUIRUN" -t 150 /usr/bin/env PPC_TLS_CAFILE="$W/ca.pem" "${RUNAPP:-$APP}" "$@" 2>&1); rc=$?
  else
    out=$("$GUIRUN" -t 150 /usr/bin/env PPC_TLS_CAFILE= "${RUNAPP:-$APP}" "$@" 2>&1); rc=$?
  fi
  out=$(printf '%s\n' "$out" | grep -E '^(fetch|download|notes|dsa|ed|driver|scheduled):' | tail -1)
}
# expect_ok NAME PATTERN CA ARGS...: exit 0 and output matching PATTERN (grep -E)
expect_ok() {
  name=$1; pat=$2; shift 2; run "$name" "$@"
  if [ $rc -eq 0 ] && printf '%s' "$out" | grep -Eq "$pat"; then ok "$name: $out"; else bad "$name: rc=$rc $out"; fi
}
expect_fail() {
  name=$1; shift; run "$name" "$@"
  if [ $rc -ne 0 ] && [ -n "$out" ]; then ok "$name: $out"; else bad "$name: rc=$rc $out"; fi
}
# expect_refused NAME PATTERN CA ARGS...: nonzero exit and output matching PATTERN
expect_refused() {
  name=$1; pat=$2; shift 2; run "$name" "$@"
  if [ $rc -ne 0 ] && printf '%s' "$out" | grep -Eq "$pat"; then ok "$name: $out"; else bad "$name: rc=$rc $out"; fi
}
# expect_ok_retry: expect_ok, with one more try after 10 s (for live GitHub, which
# sometimes answers 503)
expect_ok_retry() {
  run_name=$1; run_pat=$2; shift 2; run "$run_name" "$@"
  if [ $rc -ne 0 ] || ! printf '%s' "$out" | grep -Eq "$run_pat"; then
    echo "        (retrying in 10 s: $out)"; sleep 10
  fi
  expect_ok "$run_name" "$run_pat" "$@"
}
seconds() { printf '%s' "$out" | sed -n 's/.*(\([0-9.]*\) s, max stall \([0-9.]*\) s).*/\1 \2/p'; }

# --- fixtures -------------------------------------------------------------------
rm -rf "$W"; mkdir -p "$W/www" "$W/dl"
cat > "$W/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
[dn]
EOF
export OPENSSL_CONF=$W/openssl.cnf
(
  cd "$W" &&
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 7 \
    -subj /CN=sparkle-test-ca -addext basicConstraints=critical,CA:TRUE \
    -addext keyUsage=critical,keyCertSign,cRLSign &&
  "$OPENSSL" req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj /CN=localhost &&
  printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > srv.ext &&
  "$OPENSSL" x509 -req -in srv.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 7 \
    -extfile srv.ext -out srv.pem
) > "$W/certs.log" 2>&1 || { cat "$W/certs.log"; echo "nettest: can't make test certificates"; exit 1; }

cp "$SRC/Sample Appcast.xml" "$W/www/appcast.xml"
dd if=/dev/urandom of="$W/www/big.bin" bs=1024 count=3072 2>/dev/null
cp "$SRC/Sparkle.icns" "$W/www/pixel.png"   # any bytes will do: we only check it was fetched
cat > "$W/www/notes.html" <<'EOF'
<html><body><h1>What's new</h1><p>PPC-NOTES-MARKER</p><img src="pixel.png"></body></html>
EOF

# DSA: Sparkle's own test key pair, signed as sign_update.rb does (dss1 = SHA-1 on OpenSSL 3)
DSA_PRIV="$SRC/Test Application/dsa_priv.pem"
DSA_PUB="$SRC/Test Application/dsa_pub.pem"
"$OPENSSL" dgst -sha1 -binary < "$W/www/big.bin" | "$OPENSSL" dgst -sha1 -sign "$DSA_PRIV" \
  | "$OPENSSL" enc -base64 | tr -d '\n' > "$W/big.sig" || { echo "nettest: can't sign"; exit 1; }
"$OPENSSL" dsaparam -out "$W/other.param" 1024 2>/dev/null &&
"$OPENSSL" gendsa -out "$W/other.key" "$W/other.param" 2>/dev/null &&
"$OPENSSL" dsa -in "$W/other.key" -pubout -out "$W/other.pub" 2>/dev/null
cp "$W/www/big.bin" "$W/tampered.bin"
printf 'X' | dd of="$W/tampered.bin" bs=1 seek=1500000 conv=notrunc 2>/dev/null
cmp -s "$W/www/big.bin" "$W/tampered.bin" && { echo "nettest: tampering failed"; exit 1; }

# --- server ---------------------------------------------------------------------
"$PY" "$HERE/https-server.py" "$W/www" "$W/srv.pem" "$W/srv.key" $PA $PB $PC "$W/server.log" "$W/ready" \
  > "$W/server.out" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT INT TERM
i=0; while [ ! -f "$W/ready" ] && [ $i -lt 15 ]; do sleep 1; i=$((i + 1)); done
[ -f "$W/ready" ] || { cat "$W/server.out"; echo "nettest: server didn't start"; exit 1; }

A=https://127.0.0.1:$PA
echo "nettest: $APP ($MODE)"

# --- appcast ----------------------------------------------------------------------
expect_ok   "appcast over HTTPS"                 "OK: 3 items" test --fetch "$A/appcast.xml"
expect_ok   "appcast via redirect to other host" "OK: 3 items" test --fetch "$A/redirect/appcast.xml"
if [ "$MODE" = full ]; then
expect_ok   "appcast over plain HTTP"            "OK: 3 items" test --fetch "http://127.0.0.1:$PC/appcast.xml"
expect_fail "HTTPS -> HTTP redirect refused"                   test --fetch "$A/to-http/appcast.xml"
expect_fail "404 is an error"                                  test --fetch "$A/missing.xml"
expect_fail "untrusted certificate refused"                    real --fetch "$A/appcast.xml"
expect_fail "connection refused"                               test --fetch "https://127.0.0.1:18449/appcast.xml"
set -- $(seconds)
if [ "${1:-99}" != 99 ] && [ "$(echo "$1 < 5" | bc)" = 1 ]; then ok "  ...fails fast (${1} s)"; else bad "  ...took ${1:-?} s"; fi
expect_fail "server that never answers"                        test --fetch "$A/hang"
set -- $(seconds)
if [ "$(echo "${1:-99} < 45 && ${2:-9} < 1" | bc)" = 1 ]; then ok "  ...gave up in ${1} s, main thread never stalled (max ${2} s)"
else bad "  ...took ${1:-?} s, max stall ${2:-?} s"; fi
fi

# --- archive download --------------------------------------------------------------
SIZE=$(wc -c < "$W/www/big.bin" | tr -d ' ')
rm -f "$W/dl/"*
expect_ok "download via redirect" "name=big.bin bytes=$SIZE expected=$SIZE progress=$SIZE" \
  test --download "$A/redirect/big.bin" "$W/dl"
if cmp -s "$W/www/big.bin" "$W/dl/big.bin"; then ok "  ...file is identical"; else bad "  ...file differs"; fi
if [ "$MODE" = full ]; then
expect_fail "download 404 is an error" test --download "$A/missing.zip" "$W/dl"

# --- release notes (WebView) ---------------------------------------------------
: > "$W/server.log"
expect_ok "release notes in the update window" "marker found" test --notes "$A/notes.html" PPC-NOTES-MARKER
if grep -q " /pixel.png$" "$W/server.log"; then ok "  ...its image loaded through curl too"; else bad "  ...image not requested"; fi
fi

# --- DSA (OpenSSL 3) -------------------------------------------------------------
expect_ok   "DSA: good signature"   "dsa: OK" test --dsa "$DSA_PUB" "$(cat "$W/big.sig")" "$W/www/big.bin"
expect_fail "DSA: tampered file"              test --dsa "$DSA_PUB" "$(cat "$W/big.sig")" "$W/tampered.bin"
if [ "$MODE" = full ]; then
expect_fail "DSA: wrong key"                  test --dsa "$W/other.pub" "$(cat "$W/big.sig")" "$W/www/big.bin"
expect_fail "DSA: garbage signature"          test --dsa "$DSA_PUB" "AAAA" "$W/www/big.bin"
fi

# --- Ed25519 signing tools (bin/) -----------------------------------------------
GEN=$HERE/../bin/generate_keys
SIGN=$HERE/../bin/sign_update
b64() { "$OPENSSL" base64 -A; }
unhex() { perl -e 'print pack("H*", $ARGV[0])' "$1"; }

if PUB=$("$GEN" "$W/ed.pem" 2>/dev/null) && [ ${#PUB} -eq 44 ]; then ok "generate_keys: public key $PUB"
else bad "generate_keys: '$PUB'"; fi
case "$(ls -l "$W/ed.pem" | cut -c1-10)" in -rw-------) ok "  ...private key is mode 600" ;; *) bad "  ...private key mode $(ls -l "$W/ed.pem" | cut -c1-10)" ;; esac
if "$GEN" "$W/ed.pem" >/dev/null 2>&1; then bad "  ...overwrote an existing key"; else ok "  ...won't overwrite an existing key"; fi
if [ "$("$GEN" -p "$W/ed.pem")" = "$PUB" ]; then ok "  ...-p prints the same public key"; else bad "  ...-p differs"; fi
"$GEN" "$W/ed2.pem" > "$W/ed2.pub" 2>/dev/null

# RFC 8032 section 7.1, test 2: a published key, message and signature
RFC_PUB=$(unhex 3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c | b64)
RFC_SIG=$(unhex 92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00 | b64)
unhex 72 > "$W/rfc.msg"
expect_ok "Ed25519: RFC 8032 test vector verifies" "ed: OK" test --ed "$RFC_PUB" "$RFC_SIG" "$W/rfc.msg"
unhex 302e020100300506032b6570042204204ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb \
  | "$OPENSSL" pkey -inform DER -out "$W/rfc.pem" 2>/dev/null
if [ "$("$SIGN" "$W/rfc.msg" "$W/rfc.pem")" = "sparkle:edSignature=\"$RFC_SIG\" length=\"1\"" ]; then
  ok "sign_update reproduces the RFC 8032 signature"; else bad "sign_update: $("$SIGN" "$W/rfc.msg" "$W/rfc.pem" 2>&1)"; fi
if "$SIGN" "$W/rfc.msg" "$DSA_PRIV" >/dev/null 2>&1; then bad "sign_update took a DSA key"; else ok "sign_update refuses a non-Ed25519 key"; fi

ED_BIG=$("$SIGN" "$W/www/big.bin" "$W/ed.pem" | sed 's/.*edSignature="\([^"]*\)".*/\1/')
expect_ok   "Ed25519: good signature"   "ed: OK" test --ed "$PUB" "$ED_BIG" "$W/www/big.bin"
expect_fail "Ed25519: tampered file"             test --ed "$PUB" "$ED_BIG" "$W/tampered.bin"
if [ "$MODE" = full ]; then
expect_fail "Ed25519: wrong key"                 test --ed "$(cat "$W/ed2.pub")" "$ED_BIG" "$W/www/big.bin"
expect_fail "Ed25519: garbage signature"         test --ed "$PUB" "AAAA" "$W/www/big.bin"
expect_fail "Ed25519: malformed key"             test --ed "not-a-key" "$ED_BIG" "$W/www/big.bin"
fi

# --- signature policy, through Sparkle's own update driver -------------------
# App copies whose Info.plist holds: our test Ed25519 key, only a DSA key, no key
# (SparkleTest itself carries the RFC 8032 test key, so SUUpdater starts quietly).
APPDIR=$(cd "$(dirname "$APP")/../.." && pwd)
EXE=$(basename "$APP")
for k in ed dsa none; do
  mkdir -p "$W/apps/$k"; cp -R "$APPDIR" "$W/apps/$k/"
done
PB=/usr/libexec/PlistBuddy
$PB -c "Set :SUPublicEDKey $PUB" "$W/apps/ed/$(basename "$APPDIR")/Contents/Info.plist"
$PB -c "Delete :SUPublicEDKey" "$W/apps/dsa/$(basename "$APPDIR")/Contents/Info.plist"
$PB -c "Delete :SUPublicEDKey" "$W/apps/none/$(basename "$APPDIR")/Contents/Info.plist"
cp "$DSA_PUB" "$W/apps/dsa/$(basename "$APPDIR")/Contents/Resources/dsa_pub.pem" 2>/dev/null \
  || { mkdir -p "$W/apps/dsa/$(basename "$APPDIR")/Contents/Resources"; cp "$DSA_PUB" "$W/apps/dsa/$(basename "$APPDIR")/Contents/Resources/dsa_pub.pem"; }
$PB -c "Add :SUPublicDSAKeyFile string dsa_pub.pem" "$W/apps/dsa/$(basename "$APPDIR")/Contents/Info.plist"
APP_ED=$W/apps/ed/$(basename "$APPDIR")/Contents/MacOS/$EXE
APP_DSA=$W/apps/dsa/$(basename "$APPDIR")/Contents/MacOS/$EXE
APP_NONE=$W/apps/none/$(basename "$APPDIR")/Contents/MacOS/$EXE

# Version 7 of the app as an update archive, a tampered copy, and its signatures.
mkdir -p "$W/v7"; cp -R "$APPDIR" "$W/v7/"
$PB -c "Set :CFBundleVersion 7" -c "Set :CFBundleShortVersionString 0.7" "$W/v7/$(basename "$APPDIR")/Contents/Info.plist"
(cd "$W/v7" && ditto -c -k --keepParent "$(basename "$APPDIR")" "$W/www/SparkleTest-7.zip")
cp "$W/www/SparkleTest-7.zip" "$W/www/SparkleTest-7-tampered.zip"
ZLEN=$(wc -c < "$W/www/SparkleTest-7.zip" | tr -d ' ')
printf 'X' | dd of="$W/www/SparkleTest-7-tampered.zip" bs=1 seek=$((ZLEN / 2)) conv=notrunc 2>/dev/null
ED_ATTR=$("$SIGN" "$W/www/SparkleTest-7.zip" "$W/ed.pem")
WRONG_ATTR=$("$SIGN" "$W/www/SparkleTest-7.zip" "$W/ed2.pem")
DSA_ZIP=$("$OPENSSL" dgst -sha1 -binary < "$W/www/SparkleTest-7.zip" | "$OPENSSL" dgst -sha1 -sign "$DSA_PRIV" | b64)

feed() { # FILE VERSION URL ENCLOSURE-ATTRIBUTES
  cat > "$W/www/$1" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>SparkleTest</title>
<item><title>Version 0.$2</title>
<sparkle:minimumSystemVersion>10.4</sparkle:minimumSystemVersion>
<enclosure url="$3" sparkle:version="$2" sparkle:shortVersionString="0.$2" type="application/octet-stream" $4 />
</item></channel></rss>
EOF
}
feed ed-good.xml     7 "$A/redirect/SparkleTest-7.zip"   "$ED_ATTR"
feed ed-tampered.xml 7 "$A/SparkleTest-7-tampered.zip"   "$ED_ATTR"
feed ed-wrongkey.xml 7 "$A/SparkleTest-7.zip"            "$WRONG_ATTR"
feed unsigned.xml    7 "$A/SparkleTest-7.zip"            "length=\"$ZLEN\""
feed dsa-only.xml    7 "$A/SparkleTest-7.zip"            "length=\"$ZLEN\" sparkle:dsaSignature=\"$DSA_ZIP\""
feed both.xml        7 "$A/SparkleTest-7.zip"            "$ED_ATTR sparkle:dsaSignature=\"$DSA_ZIP\""
feed older.xml       5 "$A/SparkleTest-7.zip"            "$ED_ATTR"

RUNAPP=$APP_ED
expect_ok      "Ed25519 app, signed update (via redirect): installs"    "INSTALL: version 7" test --driver "$A/ed-good.xml"
expect_refused "Ed25519 app, tampered archive: refused"     "EdDSA signature is not valid" test --driver "$A/ed-tampered.xml"
if [ "$MODE" = full ]; then
expect_refused "Ed25519 app, unsigned update over HTTPS: refused"  "no EdDSA signature" test --driver "$A/unsigned.xml"
expect_refused "Ed25519 app, signed with another key: refused"     "EdDSA signature is not valid" test --driver "$A/ed-wrongkey.xml"
expect_refused "Ed25519 app, only a DSA signature: refused"        "no EdDSA signature" test --driver "$A/dsa-only.xml"
expect_ok      "Ed25519 app, both signatures: installs"            "INSTALL: version 7" test --driver "$A/both.xml"
expect_refused "Ed25519 app, older version: not offered"           "already have the newest version" test --driver "$A/older.xml"
RUNAPP=$APP_DSA
expect_ok      "DSA-only app, DSA-signed update: installs"         "INSTALL: version 7" test --driver "$A/dsa-only.xml"
expect_refused "DSA-only app, unsigned update over HTTPS: refused" "no DSA signature" test --driver "$A/unsigned.xml"
RUNAPP=$APP_NONE
expect_refused "app with no key: refused"                          "no public key" test --driver "$A/ed-good.xml"
fi
RUNAPP=

# --- install + relaunch, Skip This Version, quiet offline check (full run only) ---
if [ "$MODE" = full ]; then
APPNAME=$(basename "$APPDIR")
mkdir -p "$W/inst"; cp -R "$W/apps/ed/$APPNAME" "$W/inst/"
INST=$W/inst/$APPNAME
# One GUI job installs and then waits for the relaunched app: the runner is a launchd
# job, and launchd would kill Sparkle's relaunch helper as soon as the job ended.
out=$("$GUIRUN" -t 240 /bin/sh -c 'PPC_TLS_CAFILE="$1" "$2" --install "$3"; rc=$?
  i=0; while [ ! -f "$4" ] && [ $i -lt 120 ]; do sleep 1; i=$((i + 1)); done
  if [ -f "$4" ]; then echo "relaunch: OK, version 7 is running"; else echo "relaunch: FAIL: version 7 never started"; rc=1; fi
  exit $rc' sh "$W/ca.pem" "$INST/Contents/MacOS/$EXE" "$A/ed-good.xml" "$W/inst/launched-7" 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "driver: INSTALL: version 7" && printf '%s' "$out" | grep -q "relaunch: OK"; then
  ok "install + relaunch: $(printf '%s' "$out" | grep '^relaunch:')"
else
  bad "install + relaunch: rc=$rc $(printf '%s' "$out" | grep -E '^(driver|relaunch):' | tr '\n' ' ')"
fi
V=$($PB -c "Print :CFBundleVersion" "$INST/Contents/Info.plist" 2>/dev/null)
if [ "$V" = 7 ]; then ok "  ...the app on disk is now version 7"; else bad "  ...the app on disk is version '$V'"; fi
for f in "Contents/MacOS/$EXE" Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle; do
  archs=$(lipo -info "$INST/$f" 2>/dev/null | sed 's/.*: //')
  case "$archs" in *ppc750*ppc7400*ppc970*) ok "  ...$(basename "$f") still has all three slices ($archs)" ;;
    *) bad "  ...$(basename "$f") slices: '$archs'" ;; esac
done
if [ -L "$INST/Contents/Frameworks/Sparkle.framework/Sparkle" ] && [ -L "$INST/Contents/Frameworks/Sparkle.framework/Versions/Current" ]
then ok "  ...framework symlinks kept"; else bad "  ...framework symlinks broken"; fi
# Sparkle moves the replaced copy to the Trash; drop the ones this run made
n=$(find "$HOME/.Trash" -maxdepth 1 -name "$APPNAME*" -newer "$W/ready" 2>/dev/null | wc -l | tr -d ' ')
find "$HOME/.Trash" -maxdepth 1 -name "$APPNAME*" -newer "$W/ready" -exec rm -rf {} + 2>/dev/null
echo "        (old copy: $n in the Trash, removed)"

RUNAPP=$APP_ED
defaults delete io.github.cmstuberg.SparkleTest SUSkippedVersion >/dev/null 2>&1
expect_ok "scheduled check shows 7; Skip This Version"     "ALERT: version 7, skipped" test --scheduled "$A/ed-good.xml" skip
expect_ok "  ...next scheduled check: 7 stays skipped"     "scheduled: QUIET"          test --scheduled "$A/ed-good.xml"
feed ed-v8.xml 8 "$A/SparkleTest-7.zip" "$ED_ATTR"
expect_ok "  ...a newer version (8) is still offered"      "ALERT: version 8, later"   test --scheduled "$A/ed-v8.xml"
defaults delete io.github.cmstuberg.SparkleTest SUSkippedVersion >/dev/null 2>&1
expect_ok "offline: scheduled check shows nothing"         "scheduled: QUIET"          test --scheduled "https://127.0.0.1:18449/appcast.xml"
RUNAPP=
fi

# --- GitHub, for real ----------------------------------------------------------
if [ "${PPC_OFFLINE:-0}" != 1 ]; then
  expect_ok_retry "GitHub appcast (raw.githubusercontent.com)" "OK: 3 items" real --fetch \
    "https://raw.githubusercontent.com/sparkle-project/Sparkle/a5c8e0b1e29f7e23993a306e8d80d937b7fb67e6/Sample%20Appcast.xml"
  if [ "$MODE" = full ]; then
    . "$TOP/tls/versions.sh"
    rm -f "$W/dl/"*
    expect_ok_retry "GitHub release download (redirects to another host)" "name=openssl-$OPENSSL_VERSION.tar.gz.sha256" real \
      --download "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz.sha256" "$W/dl"
    if grep -q "$OPENSSL_SHA256" "$W/dl/openssl-$OPENSSL_VERSION.tar.gz.sha256" 2>/dev/null; then ok "  ...contents match"
    else bad "  ...contents differ"; fi
  fi
fi

echo "nettest: $pass passed, $fail failed"
[ $fail -eq 0 ] && rm -rf "$W"
[ $fail -eq 0 ]
