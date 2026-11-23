# Tests for the pianobar engine. Run from ../ with `make test`.
# Builds bftest and playurl for every slice against the engine's own objects, then
# runs run.sh.
include ../versions.sh
P       := ../src/pianobar-$(PIANOBAR_VERSION)/src
ENGINE  := debug.o player.o settings.o terminal.o ui_act.o ui.o ui_readline.o \
           ui_dispatch.o libpiano/crypt.o libpiano/piano.o libpiano/request.o \
           libpiano/response.o libpiano/list.o
OURS    := src-ppb/curlio.o compat/ao_coreaudio.o
CFLAGS  := -std=gnu99 -DNDEBUG -I../compat -I../src-ppb -I$(P) -I$(P)/libpiano
WARN    := -Wall -Wno-unused-parameter
LDFLAGS := -framework AudioUnit -framework CoreAudio -framework CoreServices -lm

include ../../mk/ppc.mk
include ../../mk/tls.mk
include ../../mk/av.mk
include ../../mk/json.mk

engine = $(addprefix ../build/$(1)/src/pianobar-$(PIANOBAR_VERSION)/src/,$(ENGINE)) \
         $(addprefix ../build/$(1)/,$(OURS))

define test_slice
build/$(1)/bftest: bftest.c ../build/$(1)/src/pianobar-$(PIANOBAR_VERSION)/src/libpiano/crypt.o
	@mkdir -p $$(@D)
	$$(CC) $$(COMMON) $$(CPUFLAGS_$(1)) -O2 $$(WARN) $$(CFLAGS) -o $$@ $$^ $$(LDFLAGS)
build/$(1)/playurl: playurl.c $$(call engine,$(1))
	@mkdir -p $$(@D)
	$$(CC) $$(COMMON) $$(CPUFLAGS_$(1)) -O2 $$(WARN) $$(CFLAGS) -o $$@ $$^ $$(LDFLAGS)
endef
$(foreach c,$(CPUS),$(eval $(call test_slice,$(c))))

all: $(foreach c,$(CPUS),build/$(c)/bftest build/$(c)/playurl)
	./run.sh $(CPUS)

clean:
	rm -rf build

.PHONY: all clean
.DEFAULT_GOAL := all
