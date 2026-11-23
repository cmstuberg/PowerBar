# json-c as a fat g3/g4/g5 static library, built with our own rules (no CMake).
#
#   make          # fetch + build dist/lib/libjson-c.a, dist/include/json-c/
#   make test     # json-c's own test suite on every slice
#
# Apps: include ../mk/json.mk (after mk/ppc.mk), then #include <json.h>.
include versions.sh
J        := src/json-c-$(JSONC_VERSION)
LIBRARY  := libjson-c.a
SRCS     := $(addprefix $(J)/,arraylist.c debug.c json_c_version.c json_object.c \
              json_object_iterator.c json_tokener.c json_util.c json_visit.c linkhash.c \
              printbuf.c random_seed.c strerror_override.c json_pointer.c json_patch.c)
PUBLIC_H := arraylist.h debug.h json_c_version.h json_inttypes.h json_object.h \
            json_object_iterator.h json_tokener.h json_types.h json_util.h json_visit.h \
            linkhash.h printbuf.h json_pointer.h json_patch.h
CFLAGS   := -Iconfig -Ibuild/include/json-c -I$(J) -D_REENTRANT
WARN     := -Wall -Wno-unused-parameter -Wno-unused-function
DIST     := dist

all: $(DIST)/lib/$(LIBRARY)

include ../mk/ppc.mk

# Sources come from fetch.sh (verified tarball). The objects need the generated
# headers in place first.
$(SRCS) $(J)/json.h.cmakein $(J)/COPYING: | $(J)/.ppc-patches
$(J)/.ppc-patches: versions.sh fetch.sh $(wildcard patches/json-c/*.diff)
	./fetch.sh
$(foreach c,$(CPUS),$(addprefix build/$(c)/,$(OBJNAMES))): | build/include/json-c/json.h

build/include/json-c/json.h: $(J)/json.h.cmakein config/json_config.h
	mkdir -p $(@D)
	cp $(addprefix $(J)/,$(PUBLIC_H)) config/json_config.h $(@D)/
	sed -e 's|@JSON_H_JSON_POINTER@|#include "json_pointer.h"|' \
	    -e 's|@JSON_H_JSON_PATCH@|#include "json_patch.h"|' $< > $@

$(DIST)/lib/$(LIBRARY): build/$(LIBRARY)
	rm -rf $(DIST); mkdir -p $(DIST)/lib $(DIST)/include $(DIST)/share/licenses
	cp build/$(LIBRARY) $@
	cp -R build/include/json-c $(DIST)/include/
	cp $(J)/COPYING $(DIST)/share/licenses/json-c-COPYING

# json-c's tests: each slice's test programs, run by upstream's *.test scripts,
# which compare output against the .expected files.
TESTS := test1 test2 test4 testReplaceExisting test_cast test_charcase test_compare \
  test_deep_copy test_deep_nesting test_double_serializer test_float test_int_add \
  test_int_get test_locale test_null test_parse test_parse_int64 test_printbuf \
  test_set_serializer test_set_value test_strerror test_util_file test_visit \
  test_object_iterator test_json_pointer test_safe_json_pointer_set test_json_patch
test: $(DIST)/lib/$(LIBRARY)
	@set -e; top=$$(pwd); for c in $(CPUS); do \
	  t=build/$$c/tests; mkdir -p $$t; \
	  for n in $(TESTS) test1Formatted test2Formatted; do \
	    src=$${n%Formatted}; def=; [ $$n = $$src ] || def="-DTEST_FORMATTED=1 $(J)/tests/parse_flags.c"; \
	    $(CC) $(COMMON) $(CPUFLAGS_$$c) -O2 -w $(CFLAGS) -I$(J)/tests $$def -o $$t/$$n \
	      $(J)/tests/$$src.c build/$$c/$(LIBRARY); \
	  done; \
	  fail=0; pass=0; for n in $(TESTS); do \
	    if (cd $$t && srcdir=$$top/$(J)/tests top_builddir=$$top/build/$$c USE_VALGRIND=0 \
	        sh $$top/$(J)/tests/$$n.test > $$n.log 2>&1); then pass=$$((pass+1)); \
	    else fail=$$((fail+1)); echo "[$$c] FAIL $$n (see $$t/$$n.log)"; fi; \
	  done; echo "[$$c] json-c tests: $$pass passed, $$fail failed"; [ $$fail = 0 ]; \
	done

clean:
	rm -rf build $(DIST)

.PHONY: all test clean
