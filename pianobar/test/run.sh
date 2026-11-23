#!/bin/sh
# run.sh SLICE...: the engine tests (called by make test).
#   1. bftest: Blowfish shim vs published vectors, libpiano round trip
#   2. decode: playurl -> audio_pipe for an HE-AAC/MP4 and an MP3 over HTTPS. Every
#      slice must play to the end and produce the same number of PCM bytes.
#   3. handshake: the real pianobar binary logs in to Pandora with a dummy
#      account. "Wrong email address or password" means TLS, the partner login,
#      Blowfish both ways and JSON all worked.
#   4. live audio (optional, PPB_LIVE=1): 4 s of the AAC sample through CoreAudio, in
#      a logged-in GUI session via tools/gui-run.
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$HERE/../..
CPUS=${*:-g3 g4 g5}
export PPC_TLS_CAFILE=$TOP/tls/dist/share/cacert.pem
export DYLD_FALLBACK_LIBRARY_PATH=$TOP/av/dist/Frameworks
AAC=https://samples.ffmpeg.org/A-codecs/AAC/ct_nero-heaac.mp4
MP3=https://samples.ffmpeg.org/A-codecs/MP3/Silent_Light.mp3
T=$(mktemp -d /tmp/ppbtest.XXXXXX)
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

echo "== Blowfish shim"
for c in $CPUS; do
  if "$HERE/build/$c/bftest" > "$T/bf.log" 2>&1; then ok "[$c] bftest"; else bad "[$c] bftest"; cat "$T/bf.log"; fi
done

echo "== decode over HTTPS (curlio -> ffmpeg -> audio_pipe)"
mkdir -p "$T/xdg/pianobar"
printf 'audio_pipe = %s\n' "$T/pcm" > "$T/xdg/pianobar/config"
for u in $AAC $MP3; do
  ref=
  for c in $CPUS; do
    rm -f "$T/pcm"; mkfifo "$T/pcm"
    (cat "$T/pcm" | wc -c | tr -d ' ' > "$T/bytes") &
    reader=$!
    if XDG_CONFIG_HOME=$T/xdg /usr/bin/perl -e 'alarm 120; exec @ARGV' \
        "$HERE/build/$c/playurl" "$u" > "$T/play.log" 2>&1; then
      wait $reader; n=$(cat "$T/bytes")
      if [ -z "$ref" ]; then ref=$n; fi
      if [ "$n" -gt 0 ] && [ "$n" = "$ref" ]; then ok "[$c] $(basename $u): $(sed 's/.*: //' "$T/play.log"), $n PCM bytes"
      else bad "[$c] $(basename $u): $n PCM bytes (first slice: $ref)"; fi
    else
      kill $reader 2>/dev/null; bad "[$c] $(basename $u)"; cat "$T/play.log"
    fi
  done
done

echo "== Pandora handshake (dummy account)"
mkdir -p "$T/hs/pianobar"
printf 'user = nobody@example.invalid\npassword = not-a-real-password\n' > "$T/hs/pianobar/config"
for c in fat $CPUS; do
  b=$HERE/../build/pianobar; [ $c = fat ] || b=$HERE/../build/$c/pianobar
  out=$(XDG_CONFIG_HOME=$T/hs /usr/bin/perl -e 'alarm 60; exec @ARGV' "$b" < /dev/null 2>&1 | tr '\r' '\n')
  if echo "$out" | grep -q "Wrong email address or password"; then ok "[$c] partner login + encrypted user login answered"
  else bad "[$c] handshake"; echo "$out" | tail -5; fi
done

if [ "${PPB_LIVE:-0}" = 1 ]; then
  echo "== live audio via CoreAudio (GUI session)"
  for c in $CPUS; do
    if "$TOP/tools/gui-run" -t 60 /usr/bin/env PPC_TLS_CAFILE=$PPC_TLS_CAFILE \
        DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH XDG_CONFIG_HOME=$T/none \
        "$HERE/build/$c/playurl" $AAC 4 > "$T/live.log" 2>&1; then ok "[$c] $(tail -1 "$T/live.log" | sed 's/.*: //')"
    else bad "[$c] live"; cat "$T/live.log"; fi
  done
fi

[ $fail = 0 ] && echo "PASS" || echo "FAILED"
exit $fail
