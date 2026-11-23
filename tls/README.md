# tls: modern TLS for PowerPC Mac OS X

OpenSSL 3 + curl built as **fat static libraries** with a slice per CPU family
(see `../mk/ppc.mk`), all targeting **Mac OS X 10.4+**:

| slice | Mach-O subtype | OpenSSL asm | AltiVec |
|-------|----------------|-------------|---------|
| g3 | `ppc` (ALL) | ppc32 asm | asm present, used only if `hw.optional.altivec` (never on a G3) |
| g4 | `ppc7400` | ppc32 asm | yes |
| g5 | `ppc970` | ppc32 asm | yes |

Versions are pinned in `versions.sh` (checksums from the MacPorts Portfiles). zlib
1.4 is bundled too, because curl needs zlib 1.2.5.2 or newer and Tiger has 1.2.3.

## Build

    ./build.sh           # fetch + verify + patch, build all slices, merge into dist/
    ./build.sh test      # run OpenSSL's own test suite on each slice
    CPUS=g5 ./build.sh   # single slice while iterating

Output in `dist/`:

    lib/libcrypto.a libssl.a libcurl.a libz.a libppctls.a   (fat g3/g4/g5)
    include/openssl include/curl include/ppctls.h
    bin/openssl bin/curl                              (fat, statically linked CLIs)
    share/cacert.pem                                  (Mozilla roots via curl.se)

Built with Apple gcc-4.0 against `MacOSX10.4u.sdk` (Apple's gcc-4.2 has no compiler
headers in the 10.4u SDK). MacPorts is kept off `PATH` during the build so nothing
links against `/opt/local`. Apart from the bundled libs, only libSystem and the CoreFoundation/
SystemConfiguration frameworks are used.

## Using it in an app

    include ../mk/ppc.mk
    include ../mk/tls.mk          # adds include path + static libs + frameworks

    #include "ppctls.h"
    ppctls_global_init();
    CURL *h = curl_easy_init();
    ppctls_curl_setup(h);        // CA bundle, verify peer+host, TLS >= 1.2, redirects

`ppctls_ca_file()` finds the CA bundle at `$PPC_TLS_CAFILE`, then
`<App>.app/Contents/Resources/cacert.pem`, then next to the executable. Copy
`$(TLS_CACERT)` into the app's Resources when bundling. `test/` has an end-to-end
check (`make test`) that real sites connect and bad certificates are refused.

## CA bundle

`cacert.pem` is committed. `./update-cacert.sh` refreshes it from curl.se,
verifies the published SHA-256, and trusts the current bundle to do so (so it
works with our own curl on a G3/G4). Rebuild `dist/` afterwards, then the apps.

## Patches (publishable)

`patches/<pkg>/*.diff`, applied with `-p1` by `fetch.sh`:

- `openssl/0001-numbers-size_max-ppc970-32bit.diff`: `include/internal/numbers.h`
  redefines `SIZE_MAX` as 64-bit whenever `_ARCH_PPC64` is set. GCC sets that
  for **32-bit** code built with `-arch ppc970`/`-mcpu=G5`, so 32-bit G5 builds got
  a 64-bit `SIZE_MAX` and overflow checks like `len > SIZE_MAX / 2` could never fire.
  The fix tests `__LP64__`. It should go upstream.
- `curl/0001-vtls_scache-realpath-buffer.diff`: curl calls `realpath(path, NULL)`
  (POSIX.1-2008) to build TLS session-cache keys whenever a CA file or client
  cert path is relative. Mac OS X before 10.6 crashes on a NULL buffer (bus error
  in `strlen`), so the patch passes a `PATH_MAX` buffer when one is available.
  This should go upstream.

## Build gotchas (Tiger/Leopard toolchain)

- **Linker search order:** Apple's ld looks for a `.dylib` in *all* search paths
  before any `.a`, so `-lcrypto` found the SDK's OpenSSL 0.9.7 instead of ours.
  curl's LDFLAGS carry `-Wl,-search_paths_first`. `mk/tls.mk` links libraries by
  full path.
- **Configure quoting:** pass `"-isysroot $SDK"` to OpenSSL's Configure as one
  argument (as MacPorts does); otherwise the path becomes a stray `-D` flag.
- **g4 asm subtype:** OpenSSL's perlasm emits `.machine ppc970` on OS X, which tags
  asm objects G5-only, so the g4 slice and any G4 app linked against it would
  refuse to run on a G4. `cc-asm-all.sh` assembles as usual and relabels those
  objects `ppc7400`. The 64-bit/POWER8 paths in them are runtime-gated.
- **Don't `ranlib` a fat archive:** it silently keeps only one slice.
- **zsh doesn't split `$VAR`**: run ad-hoc compile commands under `/bin/sh`.

## Checks

- `tools/check-slices` scans each slice of the `dist/lib/*.a` archives. AltiVec in
  the g3 slice is allowed only for the entries in `tools/altivec-runtime-ok.txt`
  (OpenSSL functions behind `ppccap.c` runtime checks, plus constant tables in
  `__text`). Each entry was audited against 3.6.5; re-audit when OpenSSL changes.
- `test/`: `make test` runs `tlscheck` (fat binary + each thinned slice). Good sites
  must connect with verified certificates (TLS 1.3 via howsmyssl, GitHub API, a TLS
  1.2-only host). Expired, wrong-host, self-signed and untrusted-root certificates
  and TLS 1.0 must all be refused.
- `./build.sh test`: OpenSSL's own test suite on each slice, using the CPU features
  of that slice's target (`OPENSSL_ppccap`): g3 runs as a G3 (scalar paths), g4 as a
  G4 (AltiVec, no 64-bit FPU) and g5 as detected. Takes about 13 minutes per slice.
  Last result (2026-11-22): **PASS on all three, 356 files / 4049 tests each.**

## Per-CPU config

`openssl-config/50-ppc-slices.conf` defines `darwin-ppc-g3/g4/g5`. Upstream
`darwin-ppc` hard-codes `-arch ppc -Wa,-force_cpusubtype_ALL`, which stamps every
slice as generic ppc so lipo can't merge them. The g3 target keeps
`-force_cpusubtype_ALL` because the assembler won't otherwise accept the
(runtime-gated) AltiVec instructions in OpenSSL's ppc32 asm.
