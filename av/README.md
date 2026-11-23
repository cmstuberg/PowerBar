# av: ffmpeg for PowerPC Mac OS X

A minimal, **LGPL** ffmpeg built as fat dylibs with a slice per CPU family (see
`../mk/ppc.mk`), all targeting **Mac OS X 10.4+**:

| slice | Mach-O subtype | AltiVec |
|-------|----------------|---------|
| g3 | `ppc750` | off (scalar C) |
| g4 | `ppc7400` | on |
| g5 | `ppc970` | on |

**Why ffmpeg 6.1:** ffmpeg 7.0 and later require a C11 compiler. Apple gcc-4.0, the
only compiler that works with the 10.4u SDK, is C99. 6.1.x builds cleanly with it, unpatched.

## Build

    ./build.sh            # fetch + verify, build all slices, merge into dist/
    CPUS=g5 ./build.sh    # single slice while iterating

Output in `dist/`:

    Frameworks/libav*.dylib libswresample.*.dylib   fat; install name @executable_path/../Frameworks/
    lib/*.a                                         fat static libs (tests; AltiVec scan)
    include/                                        headers
    share/licenses/ffmpeg-COPYING.LGPLv2.1
    VERSIONS                                        version + exact configure line

## What's in it

Only what the apps need so far (PowerBar): AAC/HE-AAC and MP3 decoders, MP4 and
MP3 demuxers, and the `abuffer`, `abuffersink`, `volume`, `aformat` and `aresample`
filters. **Network protocols are off.** Apps feed ffmpeg through our own curl (`../tls`),
so every connection uses one TLS stack that verifies certificates. Later apps
can add components in `build.sh`.

## Using it in an app

    include ../mk/ppc.mk
    include ../mk/av.mk

Copy `$(AV_DYLIBS)` into `YourApp.app/Contents/Frameworks/` and ship
`$(AV_LICENSE)`. To run a binary outside a bundle, set
`DYLD_FALLBACK_LIBRARY_PATH=../av/dist/Frameworks`.

## Licence

ffmpeg is built without `--enable-gpl` or `--enable-nonfree`, so it is LGPL 2.1+. The
dylibs are shipped as separate, replaceable files, and this directory holds everything
needed to rebuild them.
