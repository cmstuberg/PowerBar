/* ppctls: glue between apps and the bundled OpenSSL 3 + curl (tls/dist).
 *
 *   #include "ppctls.h"
 *   ppctls_global_init();                 // once, at startup
 *   CURL *h = curl_easy_init();
 *   ppctls_curl_setup(h);                 // CA bundle, TLS 1.2+, sane defaults
 *
 * Link with mk/tls.mk. Apps copy tls/dist/share/cacert.pem into
 * Contents/Resources (mk/tls.mk's TLS_CACERT does it). */
#ifndef PPCTLS_H
#define PPCTLS_H

#include <curl/curl.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Path of the CA bundle in use, or NULL if none was found. Looks, in order, at:
 *   $PPC_TLS_CAFILE
 *   <main bundle>/Contents/Resources/cacert.pem
 *   <dir of executable>/cacert.pem
 *   <dir of executable>/../share/cacert.pem */
const char *ppctls_ca_file(void);

/* curl_global_init(CURL_GLOBAL_DEFAULT); safe to call more than once. */
CURLcode ppctls_global_init(void);

/* Apply the CA bundle, require TLS >= 1.2, follow redirects, set a User-Agent
 * ("ppctls/<curl version>") unless the caller sets one later. Returns
 * CURLE_SSL_CACERT_BADFILE if no CA bundle could be found. */
CURLcode ppctls_curl_setup(CURL *h);

/* "OpenSSL 3.6.5 / curl 8.23.0 / g4 slice, AltiVec" style string, for About boxes and logs. */
const char *ppctls_version(void);

#ifdef __cplusplus
}
#endif
#endif
