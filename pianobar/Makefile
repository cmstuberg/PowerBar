# pianobar (the console Pandora client) for PowerPC Mac OS X 10.4+, as a fat
# g3/g4/g5 binary. This is the engine inside PowerBar.app, and it works on
# its own in Terminal too.
#
#   make          # fetch + patch upstream, build build/pianobar
#   make test     # offline checks + a live Pandora handshake (see test/)
#
# Needs the shared libraries built first: ../tls/build.sh, ../av/build.sh,
# make -C ../json-c.
#
# Differences from upstream (all for 10.4/PowerPC, see README.md):
#   compat/gcrypt.h       libgcrypt API subset on OpenSSL's Blowfish
#   compat/ao/            libao API subset on CoreAudio (ao_coreaudio.c)
#   src-ppb/curlio.c      song streams through libcurl (patches/pianobar/0001)
#   patches/pianobar/0002 API calls use the TLS stack's CA bundle and defaults
include versions.sh
P        := src/pianobar-$(PIANOBAR_VERSION)
PRODUCT  := pianobar
UPSTREAM := $(addprefix $(P)/src/,main.c debug.c player.c settings.c terminal.c \
              ui_act.c ui.c ui_readline.c ui_dispatch.c \
              libpiano/crypt.c libpiano/piano.c libpiano/request.c \
              libpiano/response.c libpiano/list.c)
SRCS     := $(UPSTREAM) src-ppb/curlio.c compat/ao_coreaudio.c
CFLAGS   := -std=gnu99 -DNDEBUG -Icompat -Isrc-ppb -I$(P)/src -I$(P)/src/libpiano
WARN     := -Wall -Wno-unused-parameter -Wno-pointer-sign
LDFLAGS  := -framework AudioUnit -framework CoreAudio -framework CoreServices -lm

all: build/$(PRODUCT)

include ../mk/ppc.mk
include ../mk/tls.mk
include ../mk/av.mk
include ../mk/json.mk

# Upstream sources come from fetch.sh (verified tarball + our patches).
$(UPSTREAM): | $(P)/.ppc-patches
$(P)/.ppc-patches: versions.sh fetch.sh $(wildcard patches/pianobar/*.diff)
	./fetch.sh

# Offline: Blowfish shim against published test vectors. Online: a full Pandora
# partner handshake with a dummy account (TLS, Blowfish, JSON), which must end
# in Pandora's "invalid login" answer.
test: build/$(PRODUCT)
	$(MAKE) -C test CPUS="$(CPUS)"

clean:
	rm -rf build
	$(MAKE) -C test clean

.PHONY: all test clean
