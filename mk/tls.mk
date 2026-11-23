# Link a project against the bundled TLS stack (OpenSSL 3 + curl + ppctls helper).
# Build the stack first:  ../tls/build.sh   (produces tls/dist, fat g3/g4/g5)
#
#   include ../mk/ppc.mk
#   include ../mk/tls.mk
#
# For an .app, copy the CA bundle in:  cp $(TLS_CACERT) $(BUNDLE)/Contents/Resources/
TLS_DIST   := $(TOP)/tls/dist
TLS_CACERT := $(TLS_DIST)/share/cacert.pem
CFLAGS     += -I$(TLS_DIST)/include -DCURL_STATICLIB
LDFLAGS    += $(TLS_DIST)/lib/libppctls.a $(TLS_DIST)/lib/libcurl.a \
              $(TLS_DIST)/lib/libssl.a $(TLS_DIST)/lib/libcrypto.a $(TLS_DIST)/lib/libz.a \
              -framework CoreFoundation -framework Security -framework SystemConfiguration

$(TLS_DIST)/lib/libcurl.a:
	@echo "TLS stack not built: run $(TOP)/tls/build.sh" >&2; exit 1
