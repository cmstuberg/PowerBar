#!/bin/sh
# Build a minimal LGPL ffmpeg for each CPU slice (g3/g4/g5), all targeting
# Mac OS X 10.4, then merge the slices into av/dist/:
#
#   dist/Frameworks/*.dylib   fat dylibs, install names @executable_path/../Frameworks/
#                             (what apps ship: LGPL lets users swap in their own build)
#   dist/lib/*.a              fat static libs (for tools/tests, and the AltiVec scan)
#   dist/include/             headers
#
#   ./build.sh                 # everything, all slices
#   CPUS=g5 ./build.sh         # one slice while iterating
#   ./build.sh dist            # only re-merge
#
# The component list is the smallest set PowerBar (pianobar) needs: AAC/HE-AAC
# and MP3 decoding, MP4/MP3 demuxing, and the volume/format/resample filters. Network
# protocols are off: apps feed ffmpeg through our own curl (tls/), so every connection
# uses one verified TLS stack. Later apps (Plex) can add components here.
#
# Slice flags mirror mk/ppc.mk. Keep them in sync.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/versions.sh"
CPUS=${CPUS:-"g3 g4 g5"}
JOBS=${JOBS:-4}
SDK=/Developer/SDKs/MacOSX10.4u.sdk
MIN_OS=10.4
CC=${CC:-/usr/bin/gcc-4.0}   # Apple gcc-4.2 has no compiler headers in the 10.4u SDK
SRC=$HERE/src; B=$HERE/build; DIST=$HERE/dist
INSTALL_NAME_DIR='@executable_path/../Frameworks'
# Keep MacPorts (pkg-config, libs) out of the build so nothing links against /opt/local.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH

archflags() {
  case $1 in
    g3) echo "-arch ppc" ;;
    g4) echo "-arch ppc7400" ;;
    g5) echo "-arch ppc970" ;;
    *) echo "unknown cpu $1" >&2; exit 1 ;;
  esac
}
# ffmpeg's configure adds -mcpu itself from --cpu, and turns AltiVec off for 750.
ffcpu() { case $1 in g3) echo 750 ;; g4) echo 7400 ;; g5) echo 970 ;; esac; }

log() { echo "==> [$1] $2"; }

COMPONENTS="--disable-everything \
  --enable-decoder=aac,mp3float,mp3 \
  --enable-demuxer=mov,mp3,aac \
  --enable-parser=aac,mpegaudio \
  --enable-protocol=file \
  --enable-filter=abuffer,abuffersink,volume,aformat,aresample \
  --enable-swresample"

build_ffmpeg() {
  cpu=$1; d=$B/$cpu/ffmpeg; p=$B/$cpu/prefix
  f="$(archflags $cpu) -isysroot $SDK -mmacosx-version-min=$MIN_OS"
  if [ -f "$p/lib/libavcodec.a" ]; then log $cpu "ffmpeg: already built"; return; fi
  log $cpu "ffmpeg $FFMPEG_VERSION: configure (--cpu=$(ffcpu $cpu))"
  rm -rf "$d" "$p"; mkdir -p "$d"; cd "$d"
  "$SRC/ffmpeg-$FFMPEG_VERSION/configure" \
      --prefix="$p" --install-name-dir="$INSTALL_NAME_DIR" \
      --cc="$CC" --arch=ppc --cpu=$(ffcpu $cpu) --target-os=darwin \
      --extra-cflags="$f" --extra-ldflags="$f" \
      --enable-shared --enable-static \
      --disable-programs --disable-doc --disable-debug \
      --disable-autodetect --disable-network \
      --disable-avdevice --disable-swscale --disable-postproc \
      --disable-vsx --disable-power8 \
      $COMPONENTS > configure.log 2>&1 \
    || { tail -30 configure.log; exit 1; }
  grep -q '^#define HAVE_ALTIVEC 1' config.h && av=on || av=off
  log $cpu "ffmpeg: make (AltiVec $av)"
  make -j$JOBS > make.log 2>&1 || { grep -E "error|Error" make.log | head -30; tail -20 make.log; exit 1; }
  make install > install.log 2>&1 || { tail -20 install.log; exit 1; }
  log $cpu "ffmpeg: done (libavcodec: $(lipo -info "$p/lib/libavcodec.a" 2>&1 | tail -1 | sed 's/.*: //'))"
}

make_dist() {
  log fat "merging $CPUS into $DIST"
  rm -rf "$DIST"; mkdir -p "$DIST/lib" "$DIST/Frameworks" "$DIST/include" "$DIST/share/licenses"
  first=$(echo $CPUS | awk '{print $1}')
  for c in $CPUS; do   # headers must be identical across slices, or apps get the wrong one
    diff -r "$B/$first/prefix/include" "$B/$c/prefix/include" > /dev/null \
      || { echo "headers differ between $first and $c" >&2; diff -r "$B/$first/prefix/include" "$B/$c/prefix/include" | head; exit 1; }
  done
  cp -R "$B/$first/prefix/include/" "$DIST/include/"
  for l in libavutil libswresample libavcodec libavformat libavfilter; do
    lipo -create $(for c in $CPUS; do echo "$B/$c/prefix/lib/$l.a"; done) -output "$DIST/lib/$l.a"
    # the versioned dylib (e.g. libavcodec.60.dylib) is the one the install name points at
    v=$(cd "$B/$first/prefix/lib" && ls $l.[0-9]*.dylib | awk -F. 'NF==3')
    lipo -create $(for c in $CPUS; do echo "$B/$c/prefix/lib/$v"; done) -output "$DIST/Frameworks/$v"
    ln -s "$v" "$DIST/Frameworks/$l.dylib"
  done
  cp "$SRC/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$DIST/share/licenses/ffmpeg-COPYING.LGPLv2.1"
  { printf 'ffmpeg %s (LGPL 2.1+)\nslices %s\nconfigure:' "$FFMPEG_VERSION" "$CPUS"
    sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"/ \1/p' "$B/$first/ffmpeg/config.h"; } > "$DIST/VERSIONS"
  for f in "$DIST"/lib/*.a "$DIST"/Frameworks/*.[0-9]*.dylib; do
    echo "$(basename $f): $(lipo -info "$f" | sed 's/.*: //')"
  done
  # Every dylib and its dependencies must use the bundle-relative install name.
  if otool -L "$DIST"/Frameworks/*.[0-9]*.dylib | grep -v ':$' | grep -v '@executable_path\|/usr/lib/\|/System/' ; then
    echo "unexpected install names above" >&2; exit 1
  fi
  "$HERE/../tools/check-slices" "$DIST"/lib/*.a "$DIST"/Frameworks/*.[0-9]*.dylib
}

"$HERE/fetch.sh"
stage=${1:-all}
for c in $CPUS; do
  case $stage in all|ffmpeg) build_ffmpeg $c ;; esac
done
case $stage in all|dist) make_dist ;; esac
