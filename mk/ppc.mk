# Shared PowerPC build rules: one fat Mach-O with a slice per CPU family.
#
#   g3 -> ppc750   (-mcpu=G3, no AltiVec)   runs on G3, G4, G5
#   g4 -> ppc7400  (-mcpu=G4, -maltivec)    runs on G4, G5
#   g5 -> ppc970   (-mcpu=G5, -maltivec)    runs on G5
#
# dyld (10.4 and 10.5) picks the best slice for the CPU it's running on, so a single
# binary gets AltiVec on G4/G5 and still runs on a G3. All slices target 10.4.
#
# A project Makefile sets PRODUCT (and/or LIBRARY) and SRCS (plus optional
# CFLAGS/LDFLAGS/CPUS), then includes this file. It gets build/$(PRODUCT), a lipo'd
# binary, and/or build/$(LIBRARY), a lipo'd static library. Before
# merging, tools/check-slices scans the project's own g3 objects for AltiVec
# (libraries are scanned when they're built), then checks the fat binary's slices. Code can use PPC_SLICE ("g3"/"g4"/"g5") and __VEC__.
#
#   make CPUS="g4 g5"   # drop the G3 slice when a project can't support it
#   make CPUS=g5        # quick single-slice build while iterating

TOP      := $(dir $(lastword $(MAKEFILE_LIST)))..
CPUS     ?= g3 g4 g5
SDK      ?= /Developer/SDKs/MacOSX10.4u.sdk
MIN_OS   ?= 10.4
CC       := /usr/bin/gcc-4.0
OPT      ?= -O2
WARN     ?= -Wall -Wextra -Wno-unused-parameter
COMMON   := -isysroot $(SDK) -mmacosx-version-min=$(MIN_OS)

CPUFLAGS_g3 := -arch ppc     -mcpu=G3 -mtune=G3           -DPPC_SLICE='"g3"'
CPUFLAGS_g4 := -arch ppc7400 -mcpu=G4 -mtune=G4 -maltivec -DPPC_SLICE='"g4"'
CPUFLAGS_g5 := -arch ppc970  -mcpu=G5 -mtune=G5 -maltivec -DPPC_SLICE='"g5"'

OBJNAMES := $(addsuffix .o,$(basename $(SRCS)))

define ppc_slice
build/$(1)/%.o: %.m
	@mkdir -p $$(@D)
	$$(CC) $$(COMMON) $$(CPUFLAGS_$(1)) $$(OPT) $$(WARN) $$(CFLAGS) -c -o $$@ $$<
build/$(1)/%.o: %.c
	@mkdir -p $$(@D)
	$$(CC) $$(COMMON) $$(CPUFLAGS_$(1)) $$(OPT) $$(WARN) $$(CFLAGS) -c -o $$@ $$<
ifneq ($(PRODUCT),)
build/$(1)/$$(PRODUCT): $$(addprefix build/$(1)/,$$(OBJNAMES))
	$$(CC) $$(COMMON) $$(CPUFLAGS_$(1)) -o $$@ $$^ $$(LDFLAGS)
endif
ifneq ($(LIBRARY),)
build/$(1)/$$(LIBRARY): $$(addprefix build/$(1)/,$$(OBJNAMES))
	rm -f $$@
	ar rc $$@ $$^
	ranlib $$@
endif
endef
$(foreach c,$(CPUS),$(eval $(call ppc_slice,$(c))))

ifneq ($(PRODUCT),)
build/$(PRODUCT): $(foreach c,$(CPUS),build/$(c)/$(PRODUCT))
	$(if $(filter g3,$(CPUS)),$(TOP)/tools/check-slices $(addprefix build/g3/,$(OBJNAMES)))
	lipo -create $^ -output $@
	$(TOP)/tools/check-slices $@
endif

# A static library instead of (or as well as) an executable: set LIBRARY := libfoo.a.
# Each slice is archived (and ranlib'd) thin, then merged. Never ranlib the fat
# archive: Leopard's ranlib keeps only one slice.
ifneq ($(LIBRARY),)
build/$(LIBRARY): $(foreach c,$(CPUS),build/$(c)/$(LIBRARY))
	lipo -create $^ -output $@
	$(TOP)/tools/check-slices $@
endif
