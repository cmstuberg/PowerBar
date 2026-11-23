# pianobar for PowerPC Mac OS X

[pianobar](https://github.com/PromyLOPh/pianobar) 2024.12.21, the console Pandora client,
built for **Mac OS X 10.4+ on PowerPC** as one fat binary (g3/g4/g5 slices; see
`../mk/ppc.mk`). It's the engine inside **PowerBar.app** (`../powerbar`),
and it also works on its own in Terminal.

## Build and test

    ../tls/build.sh && ../av/build.sh && make -C ../json-c   # shared libraries, once
    make            # build/pianobar
    make test       # engine tests (below); PPB_LIVE=1 also plays audio

`make test` runs, for every slice:

- **Blowfish:** the gcrypt shim against published test vectors, plus a libpiano round trip.
- **Decode over HTTPS:** pianobar's own player thread plays an HE-AAC/MP4 file
  (Pandora's `aacplus` format) and an MP3 from samples.ffmpeg.org into a pipe. It
  must reach the end with identical PCM output size on every slice.
- **Pandora handshake:** logs in with a dummy account. Pandora's "wrong email or
  password" reply means TLS, the partner login, Blowfish in both directions and JSON
  parsing all work.

## Changes from upstream

Upstream code is used unmodified except for two small patches. Missing libraries are
replaced by drop-in shims:

| | What | Why |
|---|---|---|
| `compat/gcrypt.h` | The libgcrypt calls libpiano makes (Blowfish ECB), on OpenSSL | libgcrypt is used only for this; OpenSSL is already linked for curl |
| `compat/ao/`, `compat/ao_coreaudio.c` | The libao calls pianobar makes, on CoreAudio's Default Output unit (10.4 API) plus raw output for `audio_pipe` | libao loads plugins at runtime from a fixed path, which doesn't suit a bundled app |
| `src-ppb/curlio.c` + `patches/pianobar/0001` | Songs stream through libcurl into ffmpeg (custom AVIOContext): buffered ahead, resumed with Range requests after a dropout | One TLS stack with certificate verification for everything; ffmpeg is built without network code |
| `patches/pianobar/0002` | API calls use `ppctls_curl_setup` (bundled CA file, TLS 1.2+) | Works with no `ca_bundle` setting |

Libraries: our OpenSSL 3 + curl (`../tls`), ffmpeg 6.1 (`../av`, LGPL dylibs in
`Contents/Frameworks`), json-c (`../json-c`).

## Licence

pianobar is MIT (`src/pianobar-*/COPYING`). Our shims and patches are MIT too.
