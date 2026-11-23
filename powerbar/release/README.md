# PowerBar

Pandora radio on a PowerPC Mac. PowerBar is a small native Cocoa player for
**Mac OS X 10.4 Tiger and 10.5 Leopard** on G3, G4 and G5 Macs, built around
[pianobar](https://github.com/PromyLOPh/pianobar), the console Pandora client.

- One universal PowerPC app with a build for each of G3, G4 and G5 (AltiVec on G4/G5).
  The Mac picks the right one.
- Modern, verified HTTPS (OpenSSL 3 + curl, bundled), so it works with today's Pandora
  servers on a 2005 Mac.
- Everything pianobar can do: stations, ratings, seeds, Shuffle, history, explicit
  content filter, plus a Dashboard widget.
- Updates itself (from 0.7), with signed updates.

You need a Pandora account, and Pandora has to be available where you are.

## Download

Get the latest `PowerBar-<version>.zip` from
**[Releases](https://github.com/cmstuberg/PowerBar/releases/latest)**, unzip it and drag
PowerBar to Applications. On a Mac this old, Safari may not open GitHub any more.
TenFourFox, or downloading on another computer and copying the zip over, works.

From version 0.7 on, PowerBar checks for updates itself (PowerBar > Check for
Updates...). If you have 0.6, install 0.7 by hand once.

How to use it is in [powerbar/README.md](powerbar/README.md), which is also in the
app (Contents/Resources/README.txt).

## Building from source

This repository holds the complete source of each release. Every release is one
commit, tagged `v<version>`, that matches that release's zip exactly. It's
published from a private working repository, so day-to-day history isn't here.

You need a PowerPC Mac running **Mac OS X 10.5** with **Xcode 3.1** (for gcc-4.0
and the 10.4u SDK), and [MacPorts](https://www.macports.org) with `curl`,
`openssl3`, `perl5` and, for the tests, `python27`. Third-party sources are
downloaded and checked against pinned SHA-256 sums, then patched (see each
directory's `versions.sh` and `patches/`).

    tls/build.sh            # OpenSSL 3 + curl + zlib, fat g3/g4/g5 (takes a while)
    av/build.sh             # a minimal LGPL ffmpeg for audio decoding
    make -C json-c
    make -C pianobar        # the engine
    make -C sparkle         # the updater framework
    make -C powerbar dist   # build/PowerBar.app and build/PowerBar-<version>.zip

`make test` in `powerbar/`, `pianobar/` and `sparkle/` runs the tests. The GUI
tests need a logged-in session; see `tools/gui-run` and
`tools/install-gui-runner.sh`.

| Directory | What |
|---|---|
| `powerbar/` | The app (Cocoa, nib-less), its Dashboard widget and tests |
| `pianobar/` | pianobar for 10.4/PowerPC: small shims and patches, audio through curl |
| `sparkle/` | Sparkle 1.5 for PowerPC, updated: modern HTTPS, Ed25519 signatures ([its README](sparkle/README.md) explains how to use it in your own app) |
| `tls/` | OpenSSL 3, curl and zlib as fat static libraries, and a CA bundle |
| `av/` | ffmpeg 6.1 (LGPL, decoders only) as fat dylibs |
| `json-c/` | json-c as a fat static library |
| `mk/`, `tools/` | Shared build rules (one slice per CPU), slice checks, the GUI test runner |

## Licences

PowerBar's own code is [MIT](LICENSE) licensed. The app also contains, each under
its own licence:

| | Licence |
|---|---|
| [pianobar](https://github.com/PromyLOPh/pianobar) | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) 1.5 | MIT |
| [ffmpeg](https://ffmpeg.org) 6.1 | LGPL 2.1 or later: shipped as separate dylibs in Contents/Frameworks that you can replace, and built from the source in `av/` |
| [OpenSSL](https://www.openssl.org) 3 | Apache 2.0 |
| [curl](https://curl.se) | curl licence (MIT-style) |
| [zlib](https://zlib.net) | zlib licence |
| [json-c](https://github.com/json-c/json-c) | MIT |

The full texts are in the app's Contents/Resources/Licenses.

PowerBar is not affiliated with, endorsed by or sponsored by Pandora Media.
Pandora is a trademark of Pandora Media, LLC.
