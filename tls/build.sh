#!/bin/sh
# Build OpenSSL 3 + curl as static libraries for each CPU slice (g3/g4/g5), all
# targeting Mac OS X 10.4, then merge them into fat libraries in tls/dist/.
#
#   ./build.sh                 # everything, all slices
#   CPUS=g5 ./build.sh         # one slice while iterating
#   ./build.sh openssl         # one stage: openssl | curl | dist | test
#   ./build.sh test            # run OpenSSL's own test suite on each slice
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
PERL=/opt/local/bin/perl5
SRC=$HERE/src; B=$HERE/build; DIST=$HERE/dist
# Keep MacPorts (pkg-config, libs, nm) out of the build so nothing links against /opt/local.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH

cpuflags() {
  case $1 in
    g3) echo "-arch ppc -mcpu=G3 -mtune=G3" ;;
    g4) echo "-arch ppc7400 -mcpu=G4 -mtune=G4 -maltivec" ;;
    g5) echo "-arch ppc970 -mcpu=G5 -mtune=G5 -maltivec" ;;
    *) echo "unknown cpu $1" >&2; exit 1 ;;
  esac
}

log() { echo "==> [$1] $2"; }

build_openssl() {
  cpu=$1; d=$B/$cpu/openssl; p=$B/$cpu/prefix
  if [ -f "$p/lib/libcrypto.a" ]; then log $cpu "openssl: already built"; return; fi
  log $cpu "openssl $OPENSSL_VERSION: configure"
  rm -rf "$d"; mkdir -p "$d"; cd "$d"
  occ=$CC; [ $cpu = g4 ] && occ=$HERE/cc-asm-all.sh   # see cc-asm-all.sh
  REAL_CC=$CC OPENSSL_LOCAL_CONFIG_DIR=$HERE/openssl-config CC=$occ \
    $PERL "$SRC/openssl-$OPENSSL_VERSION/Configure" darwin-ppc-$cpu \
      --prefix="$p" --libdir=lib --openssldir=/usr/local/etc/ppc-tls \
      no-shared no-module no-docs no-zlib \
      "-isysroot $SDK" -Wl,-syslibroot,$SDK -mmacosx-version-min=$MIN_OS > configure.log 2>&1 \
    || { tail -30 configure.log; exit 1; }
  log $cpu "openssl: make"
  REAL_CC=$CC make -j$JOBS > make.log 2>&1 || { grep -E "error|Error" make.log | head -30; tail -20 make.log; exit 1; }
  REAL_CC=$CC make install_sw > install.log 2>&1 || { tail -20 install.log; exit 1; }
  sub=$(lipo -info "$p/lib/libcrypto.a" | sed 's/.*: //')
  log $cpu "openssl: done (libcrypto.a: $sub)"
}

build_zlib() {
  cpu=$1; d=$B/$cpu/zlib; p=$B/$cpu/prefix; f="$(cpuflags $cpu) -isysroot $SDK -mmacosx-version-min=$MIN_OS"
  if [ -f "$p/lib/libz.a" ]; then log $cpu "zlib: already built"; return; fi
  log $cpu "zlib $ZLIB_VERSION"
  rm -rf "$d"; cp -R "$SRC/zlib-$ZLIB_VERSION" "$d"; cd "$d"
  CC=$CC CFLAGS="$f -O2" LDFLAGS="$f" ./configure --static --prefix="$p" > configure.log 2>&1 \
    || { tail -20 configure.log; exit 1; }
  make -j$JOBS libz.a > make.log 2>&1 && make install > install.log 2>&1 \
    || { tail -20 make.log install.log; exit 1; }
}

build_curl() {
  cpu=$1; d=$B/$cpu/curl; p=$B/$cpu/prefix; f="$(cpuflags $cpu) -isysroot $SDK -mmacosx-version-min=$MIN_OS"
  if [ -f "$p/lib/libcurl.a" ]; then log $cpu "curl: already built"; return; fi
  log $cpu "curl $CURL_VERSION: configure"
  rm -rf "$d"; mkdir -p "$d"; cd "$d"
  # -search_paths_first: otherwise ld prefers the SDK's libcrypto.dylib (0.9.7) over our .a
  CC=$CC CFLAGS="$f -O2" LDFLAGS="$f -Wl,-search_paths_first" CPPFLAGS="" \
    "$SRC/curl-$CURL_VERSION/configure" --prefix="$p" \
      --disable-shared --enable-static \
      --with-openssl="$p" --with-zlib="$p" \
      --without-libpsl --without-libidn2 --without-brotli --without-zstd \
      --without-nghttp2 --without-nghttp3 --without-ngtcp2 --without-libssh2 \
      --without-librtmp --without-libgsasl \
      --disable-ldap --disable-ldaps --disable-manual --disable-docs \
      --without-ca-bundle --without-ca-path \
      > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
  log $cpu "curl: make"
  make -j$JOBS > make.log 2>&1 || { grep -E "error|Error" make.log | head -30; tail -20 make.log; exit 1; }
  make install > install.log 2>&1 || { tail -20 install.log; exit 1; }
  log $cpu "curl: done"
}

build_ppctls() {
  cpu=$1; p=$B/$cpu/prefix; o=$B/$cpu/ppctls
  log $cpu "ppctls helper"
  mkdir -p "$o"
  $CC $(cpuflags $cpu) -isysroot $SDK -mmacosx-version-min=$MIN_OS -O2 -Wall -Wextra \
    -DPPC_SLICE="\"$cpu\"" -DCURL_STATICLIB -I"$p/include" \
    -c -o "$o/ppctls.o" "$HERE/support/ppctls.c"
  rm -f "$p/lib/libppctls.a"; ar rc "$p/lib/libppctls.a" "$o/ppctls.o"; ranlib "$p/lib/libppctls.a"
}

test_openssl() {
  cpu=$1; d=$B/$cpu/openssl
  # Test each slice with the CPU features its target really has, not the build machine's:
  # OPENSSL_ppccap overrides ppccap.c's detection (FPU=0x08 ALTIVEC=0x02 MFTB=0x20
  # FPU64=0x01). G3: FPU+MFTB. G4: +AltiVec, no 64-bit FPU. G5: detected (all).
  case $cpu in g3) caps=0x28 ;; g4) caps=0x2A ;; *) caps="" ;; esac
  log $cpu "openssl: test suite${caps:+ as OPENSSL_ppccap=$caps} (results in build/$cpu/openssl/test.log)"
  cd "$d"
  if [ -n "$caps" ]; then OPENSSL_ppccap=$caps; export OPENSSL_ppccap; else unset OPENSSL_ppccap; fi
  # The harness runs helper scripts via "/usr/bin/env perl", which needs 5.10+; Leopard has 5.8.8.
  if PATH=/opt/local/bin:$PATH REAL_CC=$CC make test HARNESS_JOBS=$JOBS > test.log 2>&1; then log $cpu "openssl tests: $(grep -a -E '^(Files=|Result:)' test.log | tail -2 | tr '\n' ' ')"
  else log $cpu "openssl tests FAILED"; grep -a -E "^(Result|Files=|Failed|.*Dubious|.*Failed test)" test.log | head -20; return 1; fi
}

make_dist() {
  log fat "merging $CPUS into $DIST"
  rm -rf "$DIST"; mkdir -p "$DIST/lib" "$DIST/bin" "$DIST/include" "$DIST/share"
  first=$(echo $CPUS | awk '{print $1}')
  for c in $CPUS; do   # headers must be identical across slices, or apps get the wrong one
    diff -r "$B/$first/prefix/include" "$B/$c/prefix/include" > /dev/null \
      || { echo "headers differ between $first and $c" >&2; diff -r "$B/$first/prefix/include" "$B/$c/prefix/include" | head; exit 1; }
  done
  cp -R "$B/$first/prefix/include/" "$DIST/include/"
  cp "$HERE/support/ppctls.h" "$DIST/include/"
  for l in libz libcrypto libssl libcurl libppctls; do
    lipo -create $(for c in $CPUS; do echo "$B/$c/prefix/lib/$l.a"; done) -output "$DIST/lib/$l.a"
  done
  for t in openssl curl; do
    lipo -create $(for c in $CPUS; do echo "$B/$c/prefix/bin/$t"; done) -output "$DIST/bin/$t"
  done
  cp "$HERE/cacert.pem" "$DIST/share/cacert.pem"
  printf 'openssl %s\ncurl %s\nzlib %s\nslices %s\n' "$OPENSSL_VERSION" "$CURL_VERSION" "$ZLIB_VERSION" "$CPUS" > "$DIST/VERSIONS"
  for f in "$DIST"/lib/*.a "$DIST"/bin/*; do echo "$(basename $f): $(lipo -info "$f" | sed 's/.*: //')"; done
  "$HERE/../tools/check-slices" "$DIST"/lib/*.a
}

"$HERE/fetch.sh"
stage=${1:-all}
for c in $CPUS; do
  case $stage in all|openssl) build_openssl $c ;; esac
  case $stage in all|curl)    build_zlib $c; build_curl $c; build_ppctls $c ;; esac
done
case $stage in all|dist) make_dist ;; esac
case $stage in test) rc=0; for c in $CPUS; do test_openssl $c || rc=1; done; exit $rc ;; esac
