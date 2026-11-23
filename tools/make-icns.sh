#!/bin/sh
# make-icns.sh SOURCE.png OUT.icns
# Build an .icns that works from Mac OS X 10.4 on: the classic 16/32/48/128 icons
# (is32/il32/ih32/it32 + masks, written by Leopard's own tiff2icns), plus 256 and
# 512 as JPEG 2000 (ic08/ic09), which 10.5 shows and 10.4 skips. Modern iconutil
# writes formats Tiger can't read. tiff2icns needs the WindowServer, so this runs it
# through tools/gui-run. The result is committed; rerun only when the art changes.
set -e
SRC=$1; OUT=$2
[ -f "$SRC" ] && [ -n "$OUT" ] || { echo "usage: $0 source.png out.icns" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
T=$(mktemp -d /tmp/icns.XXXXXX)
trap 'rm -rf "$T"' EXIT
for s in 128 48 32 16; do
  sips -s format tiff -z $s $s "$SRC" --out "$T/$s.tiff" > /dev/null
done
tiffutil -cat "$T/128.tiff" "$T/48.tiff" "$T/32.tiff" "$T/16.tiff" -out "$T/all.tiff" > /dev/null 2>&1
"$HERE/gui-run" -t 60 /usr/bin/tiff2icns "$T/all.tiff" "$OUT"
sips -s format jp2 -z 256 256 "$SRC" --out "$T/256.jp2" > /dev/null
sips -s format jp2 -z 512 512 "$SRC" --out "$T/512.jp2" > /dev/null
# append ic08/ic09 and fix the total length in the header
/usr/bin/perl -e '
  my ($icns, $j256, $j512) = @ARGV;
  local $/;
  open (my $f, "<", $icns) or die; binmode $f; my $d = <$f>; close $f;
  for ([ "ic08", $j256 ], [ "ic09", $j512 ]) {
    open (my $j, "<", $_->[1]) or die; binmode $j; my $img = <$j>; close $j;
    $d .= $_->[0] . pack ("N", 8 + length $img) . $img;
  }
  substr ($d, 4, 4) = pack ("N", length $d);
  open ($f, ">", $icns) or die; binmode $f; print $f $d; close $f;
' "$OUT" "$T/256.jp2" "$T/512.jp2"
ls -la "$OUT"
