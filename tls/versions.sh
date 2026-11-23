# Pinned upstream sources. Checksums match the MacPorts Portfiles
# (devel/openssl3, net/curl, archivers/zlib), which are the versions MacPorts ships on the build machine.
OPENSSL_VERSION=3.6.5
OPENSSL_SHA256=a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz

CURL_VERSION=8.23.0
CURL_SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
CURL_URL=https://curl.se/download/curl-$CURL_VERSION.tar.xz

# curl needs zlib >= 1.2.5.2; Tiger's SDK only has 1.2.3, so we bundle our own.
ZLIB_VERSION=1.4
ZLIB_SHA256=4f11c512053d7bab8d9e9b89bde3575add3e4c50a383b42ef6cb837035fc5a7c
ZLIB_URL=https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.xz
