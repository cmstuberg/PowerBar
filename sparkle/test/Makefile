# SparkleTest.app: a test app that embeds ../build/Sparkle.framework like a real
# app does. `make` (from ../ as `make test`) runs fwtest in a logged-in GUI session for
# the fat app, then for a copy per slice with a thin app binary and a thin
# framework, so dyld really runs that slice of Sparkle (the G5 runs G3/G4 code).
# nettest.sh then checks networking and DSA: all of it on the fat app, the core
# subset on each slice.
PRODUCT := SparkleTest
SRCS    := fwtest.m
CFLAGS  := -F../build -I$(firstword $(wildcard ../src/Sparkle-*))
LDFLAGS := -F../build -framework Sparkle -framework Cocoa -framework WebKit
FW      := ../build/Sparkle.framework
APP     := build/$(PRODUCT).app

all: run

include ../../mk/ppc.mk

$(APP): build/$(PRODUCT) Info.plist $(FW)
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Frameworks
	cp Info.plist $@/Contents/Info.plist
	printf "APPL????" > $@/Contents/PkgInfo
	cp build/$(PRODUCT) $@/Contents/MacOS/$(PRODUCT)
	cp -R $(FW) $@/Contents/Frameworks/

run: $(APP)
	../../tools/gui-run -t 60 $$(pwd)/$(APP)/Contents/MacOS/$(PRODUCT)
	sh nettest.sh $$(pwd)/$(APP)/Contents/MacOS/$(PRODUCT) full
	@set -e; for c in $(CPUS); do \
	  t=build/slice-$$c/$(PRODUCT).app; rm -rf build/slice-$$c; mkdir -p build/slice-$$c; \
	  cp -R $(APP) $$t; cp build/$$c/$(PRODUCT) $$t/Contents/MacOS/$(PRODUCT); \
	  lipo $(FW)/Versions/A/Sparkle -thin $$(lipo -info build/$$c/$(PRODUCT) | sed 's/.*: //') \
	    -output $$t/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle; \
	  echo "[$$c]"; l=build/slice-$$c/fwtest.log; \
	  ../../tools/gui-run -t 60 $$(pwd)/$$t/Contents/MacOS/$(PRODUCT) > $$l 2>&1 || { cat $$l; exit 1; }; \
	  tail -1 $$l; \
	  sh nettest.sh $$(pwd)/$$t/Contents/MacOS/$(PRODUCT) quick || exit 1; \
	done

clean:
	rm -rf build

.PHONY: all run clean
