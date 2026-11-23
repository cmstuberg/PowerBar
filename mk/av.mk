# Link a project against our ffmpeg (av/), as bundle-relative dylibs.
# Build it first:  ../av/build.sh   (produces av/dist, fat g3/g4/g5)
#
#   include ../mk/ppc.mk
#   include ../mk/av.mk
#
# The dylibs' install names are @executable_path/../Frameworks/, so an .app must copy
# $(AV_DYLIBS) into Contents/Frameworks/. ffmpeg is LGPL: shipping it as replaceable
# dylibs (plus its licence, $(AV_LICENSE)) is what keeps the app's own licence free.
# To run a binary outside a bundle, set DYLD_FALLBACK_LIBRARY_PATH=$(AV_DIST)/Frameworks.
AV_DIST    := $(TOP)/av/dist
AV_DYLIBS   = $(wildcard $(AV_DIST)/Frameworks/*.[0-9]*.dylib)
AV_LICENSE := $(AV_DIST)/share/licenses/ffmpeg-COPYING.LGPLv2.1
CFLAGS     += -I$(AV_DIST)/include
LDFLAGS    += $(addprefix $(AV_DIST)/Frameworks/,libavfilter.dylib libavformat.dylib \
                libavcodec.dylib libswresample.dylib libavutil.dylib)

$(AV_DIST)/Frameworks/libavcodec.dylib:
	@echo "ffmpeg not built: run $(TOP)/av/build.sh" >&2; exit 1
