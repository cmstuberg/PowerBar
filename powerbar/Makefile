# PowerBar.app: Cocoa front end + the pianobar engine, fat g3/g4/g5, 10.4+.
#
#   make          # build/PowerBar.app
#   make test     # --selftest in a logged-in GUI session: the fat app, then a copy of
#                 # the app per slice (thin front end + thin engine)
#   make dist     # build/PowerBar-<version>.zip (ditto, keeps the bundle intact)
#
# Needs: ../tls/build.sh, ../av/build.sh, make -C ../json-c, make -C ../pianobar,
# make -C ../sparkle (the updater, embedded in Contents/Frameworks).
PRODUCT := PowerBar
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
BUILD   := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
SRCS    := src/main.m src/PPBController.m src/PPBEngine.m src/PPBActionPanel.m \
           src/PPBFlows.m src/PPBUI.m src/PPBKeychain.m src/PPBFetch.m src/PPBUITest.m
CFLAGS  := -Isrc -F../sparkle/build
LDFLAGS := -framework Cocoa -framework Security -F../sparkle/build -framework Sparkle
BUNDLE  := build/$(PRODUCT).app

all: $(BUNDLE)

include ../mk/ppc.mk
include ../mk/tls.mk

ENGINE  := ../pianobar/build/pianobar
AV_FW   := ../av/dist/Frameworks
LICENSES := ../pianobar/src/pianobar-*/COPYING:pianobar.txt \
            ../av/dist/share/licenses/ffmpeg-COPYING.LGPLv2.1:ffmpeg-LGPL-2.1.txt \
            ../json-c/dist/share/licenses/json-c-COPYING:json-c.txt \
            ../tls/src/openssl-*/LICENSE.txt:OpenSSL.txt \
            ../tls/src/curl-*/COPYING:curl.txt \
            ../tls/src/zlib-*/LICENSE:zlib.txt \
            ../sparkle/src/Sparkle-*/License.txt:Sparkle.txt
SPARKLE_FW := ../sparkle/build/Sparkle.framework

$(ENGINE):
	$(MAKE) -C ../pianobar

$(SPARKLE_FW):
	$(MAKE) -C ../sparkle
# ppc.mk's object rules only know the .m files: rebuild everything when a header
# changes (a new ivar changes the object layout every file must agree on)
$(foreach c,$(CPUS),$(addprefix build/$(c)/,$(OBJNAMES))): $(wildcard src/*.h)
# the controller includes <Sparkle/Sparkle.h>
$(foreach c,$(CPUS),build/$(c)/src/PPBController.o): | $(SPARKLE_FW)

# --- Dashboard widget (widget/) ---
# powerbar-ctl: the widget's buttons -> a distributed notification PowerBar listens to
build/%/powerbar-ctl: widget/powerbar-ctl.m
	@mkdir -p $(@D)
	$(CC) $(COMMON) $(CPUFLAGS_$*) -O2 $(WARN) -o $@ $< -framework Foundation
build/powerbar-ctl: $(foreach c,$(CPUS),build/$(c)/powerbar-ctl)
	lipo -create $^ -output $@
	../tools/check-slices $@

WIDGET := build/PowerBar.wdgt
WIDGET_SRC := widget/Info.plist widget/PowerBar.html widget/PowerBar.css widget/PowerBar.js widget/Default.png
$(WIDGET): $(WIDGET_SRC) build/powerbar-ctl icon/PowerBar.png Info.plist
	rm -rf $@
	mkdir -p $@/Images
	cp $(WIDGET_SRC) $@/
	@# the app's build number, so the app can tell an older installed copy (refreshInstalledWidget)
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD)" $@/Info.plist
	cp build/powerbar-ctl $@/powerbar-ctl
	strip -x $@/powerbar-ctl
	sips -z 84 84 icon/PowerBar.png --out $@/Images/placeholder.png > /dev/null
	sips -z 80 80 icon/PowerBar.png --out $@/Icon.png > /dev/null

# Default.png (what Dashboard shows while the widget loads) is the widget's empty
# look, rendered offscreen in a logged-in GUI session. Committed; rerun after a redesign.
build/widgetshot: test/widgetshot.m
	$(CC) $(COMMON) $(CPUFLAGS_g4) -O2 $(WARN) -o $@ $< -framework Cocoa -framework WebKit
widget-default: build/widgetshot $(WIDGET)
	../tools/gui-run -t 60 $$(pwd)/build/widgetshot $$(pwd)/$(WIDGET)/PowerBar.html empty $$(pwd)/widget/Default.png
# widgettest: the widget's real page in a WebView, fed four songs whose covers reuse
# the two cover file names; each new cover must show on the widget's canvas.
build/widgettest: test/widgettest.m
	$(CC) $(COMMON) $(CPUFLAGS_g4) -O2 $(WARN) -o $@ $< -framework Cocoa -framework WebKit
widgettest: build/widgettest $(WIDGET)
	@rm -rf build/test/widgetstate
	../tools/gui-run -t 90 $$(pwd)/build/widgettest $$(pwd)/$(WIDGET)/PowerBar.html $$(pwd)/build/test/widgetstate

# A look at the widget with a song playing (test/widget-demo), for review.
widget-preview: build/widgetshot $(WIDGET)
	@rm -rf build/test/widget; mkdir -p build/test/widget
	cp test/widget-demo/nowplaying.json build/test/widget/
	sips -z 300 300 icon/PowerBar.png --out build/test/widget/cover-1 > /dev/null
	../tools/gui-run -t 60 $$(pwd)/build/widgetshot $$(pwd)/$(WIDGET)/PowerBar.html \
	  state=$$(pwd)/build/test/widget/ $$(pwd)/build/test/widget/playing.png
	../tools/gui-run -t 60 $$(pwd)/build/widgetshot $$(pwd)/$(WIDGET)/PowerBar.html \
	  state=/nonexistent/ $$(pwd)/build/test/widget/idle.png

$(BUNDLE): build/$(PRODUCT) $(ENGINE) Info.plist ppb-event icon/PowerBar.icns $(WIDGET) $(TLS_CACERT) $(SPARKLE_FW)
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources/Licenses $@/Contents/Frameworks
	cp Info.plist $@/Contents/Info.plist
	printf "APPL????" > $@/Contents/PkgInfo
	cp build/$(PRODUCT) $@/Contents/MacOS/$(PRODUCT)
	cp $(ENGINE) $@/Contents/MacOS/pianobar
	cp $(AV_FW)/*.[0-9]*.dylib $@/Contents/Frameworks/
	cp -R $(SPARKLE_FW) $@/Contents/Frameworks/
	install -m 755 ppb-event $@/Contents/Resources/ppb-event
	cp icon/PowerBar.icns $@/Contents/Resources/PowerBar.icns
	cp -R $(WIDGET) $@/Contents/Resources/
	cp $(TLS_CACERT) $@/Contents/Resources/cacert.pem
	for l in $(LICENSES); do cp $${l%%:*} $@/Contents/Resources/Licenses/$${l##*:}; done
	cp README.md $@/Contents/Resources/README.txt
	strip -x $@/Contents/MacOS/$(PRODUCT) $@/Contents/MacOS/pianobar
	strip -S $@/Contents/Frameworks/*.dylib
	../tools/check-slices $@/Contents/MacOS/$(PRODUCT) $@/Contents/MacOS/pianobar $@/Contents/Frameworks/*.dylib \
	  $@/Contents/Resources/PowerBar.wdgt/powerbar-ctl $@/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle
	@du -sh $@

# enginetest: PPBEngine against a scripted pianobar (test/fake-pianobar) that checks
# every answer: prompts, one-key and typed answers, cancel, events, time, quit.
build/enginetest: test/enginetest.m src/PPBEngine.m src/PPBEngine.h
	$(CC) $(COMMON) $(CPUFLAGS_g4) -O2 $(WARN) $(CFLAGS) -o $@ test/enginetest.m src/PPBEngine.m -framework Cocoa

enginetest: build/enginetest
	@rm -rf build/test/engine; mkdir -p build/test/engine
	build/enginetest $$(pwd)/test/fake-pianobar $$(pwd)/build/test/engine

# uitest: the real app against test/fake-pianobar-full (every feature, worded like
# pianobar). The app opens each feature window, clicks its buttons and checks the
# result; window snapshots land in build/test/ui/.
uitest: $(BUNDLE)
	@rm -rf build/test/ui; mkdir -p build/test/ui/support build/test/ui/Widgets
	cp -R $(WIDGET) build/test/ui/Widgets/
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0" build/test/ui/Widgets/PowerBar.wdgt/Info.plist
	@# a different cover for each song (the icon at different sizes), sent as file:// coverArt
	mkdir -p build/test/ui/art
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12; do sips -z $$((40 + i * 4)) $$((40 + i * 4)) icon/PowerBar.png \
	  --out build/test/ui/art/art$$i.png > /dev/null 2>&1; done
	../tools/gui-run -t 300 /usr/bin/env PPB_ENGINE=$$(pwd)/test/fake-pianobar-full \
	  PPB_SUPPORT_DIR=$$(pwd)/build/test/ui/support FAKE_LOG=$$(pwd)/build/test/ui/fake.log \
	  PPB_WIDGETS_DIR=$$(pwd)/build/test/ui/Widgets FAKE_ART_DIR=$$(pwd)/build/test/ui/art \
	  $(BUNDLE)/Contents/MacOS/$(PRODUCT) --uitest $$(pwd)/build/test/ui
	@# every Shuffle box was flipped: Jazz Radio out, the other four in
	@grep -q "^mix: Miles Davis Radio,Renamed Radio,Rock Radio,Shared 12345$$" build/test/ui/fake.log \
	  || { echo "uitest: wrong Shuffle mix:"; grep "^mix:" build/test/ui/fake.log; exit 1; }
	@# the "installed" widget from an older build was replaced with this build's
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/test/ui/Widgets/PowerBar.wdgt/Info.plist)" = "$(BUILD)" \
	  || { echo "uitest: the installed Dashboard widget wasn't refreshed"; exit 1; }
	@echo "uitest: installed Dashboard widget refreshed to build $(BUILD)"

# Then --selftest against the real Pandora. Each slice gets its own copy of the
# bundle with thin binaries, so dyld really runs that slice for both the front end
# and the engine (the G5 executes G3/G4 code).
test: $(BUNDLE) enginetest uitest widgettest
	@rm -rf build/test/support; mkdir -p build/test/support
	PPB_SUPPORT_DIR=$$(pwd)/build/test/support ../tools/gui-run -t 120 /usr/bin/env \
	  PPB_SUPPORT_DIR=$$(pwd)/build/test/support $(BUNDLE)/Contents/MacOS/$(PRODUCT) --selftest
	@set -e; for c in $(CPUS); do \
	  t=build/test/$$c/$(PRODUCT).app; rm -rf $$t; mkdir -p build/test/$$c; cp -R $(BUNDLE) $$t; \
	  cp build/$$c/$(PRODUCT) $$t/Contents/MacOS/$(PRODUCT); \
	  cp ../pianobar/build/$$c/pianobar $$t/Contents/MacOS/pianobar; \
	  lipo $(SPARKLE_FW)/Versions/A/Sparkle -thin $$(lipo -info build/$$c/$(PRODUCT) | sed 's/.*: //') \
	    -output $$t/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle; \
	  echo "[$$c]"; ../tools/gui-run -t 120 /usr/bin/env PPB_SUPPORT_DIR=$$(pwd)/build/test/support \
	    $$t/Contents/MacOS/$(PRODUCT) --selftest; \
	done

dist: $(BUNDLE)
	rm -f build/$(PRODUCT)-$(VERSION).zip
	cd build && ditto -c -k --keepParent $(PRODUCT).app $(PRODUCT)-$(VERSION).zip
	@ls -la build/$(PRODUCT)-$(VERSION).zip

run: $(BUNDLE)
	open $(BUNDLE)

clean:
	rm -rf build

.PHONY: all test enginetest uitest widgettest widget-default widget-preview dist run clean
