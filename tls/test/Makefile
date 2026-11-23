PRODUCT := tlscheck
SRCS    := tlscheck.c

all: build/$(PRODUCT)

include ../../mk/ppc.mk
include ../../mk/tls.mk
CFLAGS += -I../support

# Runs the fat binary, then each slice on its own (the G5 can execute all three).
test: build/$(PRODUCT)
	PPC_TLS_CAFILE=$(TLS_CACERT) build/$(PRODUCT)
	for c in $(CPUS); do printf -- "--- %s slice: " $$c; PPC_TLS_CAFILE=$(TLS_CACERT) build/$$c/$(PRODUCT) > build/$$c.log 2>&1 || { echo; cat build/$$c.log; exit 1; }; tail -1 build/$$c.log; done

clean:
	rm -rf build

.PHONY: all test clean
