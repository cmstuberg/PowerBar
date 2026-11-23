# Sparkle 1.5 (the Tiger-era line) as a fat g3/g4/g5 Sparkle.framework for
# Mac OS X 10.4+, built with gcc-4.0 and the 10.4u SDK through mk/ppc.mk.
#
#   make          # fetch + patch upstream, build build/Sparkle.framework
#   make test     # load the framework from a test app (fat, then each slice)
#
# Apps embed build/Sparkle.framework in Contents/Frameworks and use it exactly
# like stock Sparkle 1.5 (SUUpdater, SUFeedURL, ...). See README.md.
include versions.sh
S        := src/Sparkle-$(SPARKLE_COMMIT)
FW_SRCS  := NTSynchronousTask SUAppcast SUAppcastItem SUAutomaticUpdateAlert \
            SUAutomaticUpdateDriver SUBasicUpdateDriver SUConstants SUDSAVerifier \
            SUDiskImageUnarchiver SUHost SUInstaller SUPackageInstaller SUPipedUnarchiver \
            SUPlainInstaller SUPlainInstallerInternals SUProbingUpdateDriver \
            SUScheduledUpdateDriver SUStandardVersionComparator SUStatusController \
            SUSystemProfiler SUUIBasedUpdateDriver SUUnarchiver SUUnarchiver_Private \
            SUUpdateAlert SUUpdateDriver SUUpdatePermissionPrompt SUUpdater \
            SUUserInitiatedUpdateDriver SUWindowController
UPSTREAM := $(addprefix $(S)/,$(addsuffix .m,$(FW_SRCS)))
SRCS     := $(UPSTREAM) src-ppc/SUNoBinaryDelta.m src-ppc/SUCurlURLProtocol.m \
            src-ppc/SUEdDSAVerifier.m
PRODUCT  := Sparkle
CFLAGS   := -std=gnu99 -fobjc-exceptions -include $(S)/Sparkle.pch -I$(S) -Isrc-ppc -Ibuild/include
WARN     := -Wall -Wno-unused-parameter
LDFLAGS  := -dynamiclib -install_name @loader_path/../Frameworks/Sparkle.framework/Versions/A/Sparkle \
            -compatibility_version 1.5 -current_version 1.5 -Wl,-search_paths_first \
            -framework AppKit -framework Foundation -framework IOKit -framework Security \
            -framework WebKit -Wl,-exported_symbols_list,build/Sparkle.exp
PUBLIC_H := Sparkle.h SUUpdater.h SUAppcast.h SUAppcastItem.h SUVersionComparisonProtocol.h
FW       := build/Sparkle.framework
# CFBundleShortVersionString, so this build can't be mistaken for stock 1.5
PPC_VERSION := 1.5-ppc.1

all: $(FW)

include ../mk/ppc.mk
# Networking (src-ppc/SUCurlURLProtocol.m) and DSA (patch 0002) use the bundled
# curl + OpenSSL 3, linked in statically. Only Sparkle's own symbols are exported
# (build/Sparkle.exp), so they never clash with an app's own copy.
include ../mk/tls.mk

# The export list: every global defined in Sparkle's own objects (classes and
# SU* constants; ld doesn't export categories), from the first slice's objects.
# Order-only, so ppc.mk's link line ($^) doesn't take it as an input.
EXP_SLICE := $(firstword $(CPUS))
build/Sparkle.exp: $(addprefix build/$(EXP_SLICE)/,$(OBJNAMES))
	nm -gUj $^ | grep -v -e '^$$' -e ':$$' -e '^\.objc_category_name_' | sort -u > $@
$(foreach c,$(CPUS),build/$(c)/$(PRODUCT)): | build/Sparkle.exp

# Upstream sources come from fetch.sh (verified tarball + our patches).
$(UPSTREAM) $(S)/relaunch.m $(S)/Sparkle.pch: | $(S)/.ppc-patches
$(S)/.ppc-patches: versions.sh fetch.sh $(wildcard patches/sparkle/*.diff)
	./fetch.sh
	@# <Sparkle/X.h> while building the framework itself
	mkdir -p build/include && rm -f build/include/Sparkle && ln -s ../../$(S) build/include/Sparkle

# relaunch: waits for the app to quit, then opens the updated copy. Lives in the
# framework's Resources; Sparkle copies it to a temp dir before installing.
build/%/relaunch: $(S)/relaunch.m | $(S)/.ppc-patches
	@mkdir -p $(@D)
	$(CC) $(COMMON) $(CPUFLAGS_$*) -Os $(WARN) $(CFLAGS) -o $@ $< -framework AppKit
build/relaunch: $(foreach c,$(CPUS),build/$(c)/relaunch)
	lipo -create $^ -output $@
	../tools/check-slices $@

# Resources as the Xcode project ships them: compiled (keyed) nibs only, without
# the Interface Builder source files next to them.
$(FW): build/$(PRODUCT) build/relaunch $(TLS_CACERT)
	rm -rf $@
	mkdir -p $@/Versions/A/Resources $@/Versions/A/Headers
	cp build/$(PRODUCT) $@/Versions/A/Sparkle
	strip -x $@/Versions/A/Sparkle
	sed -e 's/$${EXECUTABLE_NAME}/Sparkle/' -e 's/$${PRODUCT_NAME}/Sparkle/' \
	  -e 's/1\.5 Beta (git)/$(PPC_VERSION)/' \
	  $(S)/Info.plist > $@/Versions/A/Resources/Info.plist
	cd $(S) && cp $(PUBLIC_H) $(CURDIR)/$@/Versions/A/Headers/
	cd $(S) && cp -R *.lproj SUStatus.nib Sparkle.icns SUModelTranslation.plist License.txt \
	  $(CURDIR)/$@/Versions/A/Resources/
	find $@/Versions/A/Resources -name '*.nib' -type d -exec sh -c \
	  'cd "$$0" && rm -f classes.nib info.nib designable.nib data.dependency' {} \;
	cp build/relaunch $@/Versions/A/Resources/relaunch
	cp $(TLS_CACERT) $@/Versions/A/Resources/cacert.pem
	mkdir -p $@/Versions/A/Resources/Licenses
	cp ../tls/src/openssl-*/LICENSE.txt $@/Versions/A/Resources/Licenses/OpenSSL.txt
	cp ../tls/src/curl-*/COPYING $@/Versions/A/Resources/Licenses/curl.txt
	cp ../tls/src/zlib-*/LICENSE $@/Versions/A/Resources/Licenses/zlib.txt
	strip -x $@/Versions/A/Resources/relaunch
	ln -s A $@/Versions/Current
	ln -s Versions/Current/Sparkle $@/Sparkle
	ln -s Versions/Current/Resources $@/Resources
	ln -s Versions/Current/Headers $@/Headers
	../tools/check-slices $@/Versions/A/Sparkle $@/Versions/A/Resources/relaunch
	@du -sh $@

test: $(FW)
	$(MAKE) -C test CPUS="$(CPUS)"

clean:
	rm -rf build
	$(MAKE) -C test clean

.PHONY: all test clean
