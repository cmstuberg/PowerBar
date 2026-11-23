# Link a project against json-c (json-c/), a fat g3/g4/g5 static library.
# Build it first:  make -C ../json-c
#
#   include ../mk/ppc.mk
#   include ../mk/json.mk        # then: #include <json.h>
JSONC_DIST    := $(TOP)/json-c/dist
JSONC_LICENSE := $(JSONC_DIST)/share/licenses/json-c-COPYING
CFLAGS        += -I$(JSONC_DIST)/include/json-c
LDFLAGS       += $(JSONC_DIST)/lib/libjson-c.a

$(JSONC_DIST)/lib/libjson-c.a:
	@echo "json-c not built: run make -C $(TOP)/json-c" >&2; exit 1
