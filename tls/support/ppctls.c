#include "ppctls.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/param.h>
#include <mach-o/dyld.h>
#include <CoreFoundation/CoreFoundation.h>
#include <openssl/opensslv.h>

#ifndef PPC_SLICE
#define PPC_SLICE "unknown"
#endif

static char ca_path[MAXPATHLEN];
static int ca_searched;

static int readable(const char *p) { return p && *p && access(p, R_OK) == 0; }

static int from_bundle(char *out, size_t n)
{
    CFBundleRef b = CFBundleGetMainBundle();
    CFURLRef u;
    int ok = 0;
    if (!b) return 0;
    u = CFBundleCopyResourceURL(b, CFSTR("cacert"), CFSTR("pem"), NULL);
    if (u) {
        ok = CFURLGetFileSystemRepresentation(u, true, (UInt8 *)out, (CFIndex)n) && readable(out);
        CFRelease(u);
    }
    return ok;
}

static int beside_exe(const char *rel, char *out, size_t n)
{
    char exe[MAXPATHLEN], real[MAXPATHLEN], *slash;
    uint32_t sz = sizeof(exe);
    if (_NSGetExecutablePath(exe, &sz) != 0 || !realpath(exe, real)) return 0;
    if (!(slash = strrchr(real, '/'))) return 0;
    *slash = '\0';
    snprintf(out, n, "%s/%s", real, rel);
    return readable(out);
}

const char *ppctls_ca_file(void)
{
    if (!ca_searched) {
        const char *env = getenv("PPC_TLS_CAFILE");
        ca_searched = 1;
        if (readable(env)) strlcpy(ca_path, env, sizeof(ca_path));
        else if (!from_bundle(ca_path, sizeof(ca_path))
              && !beside_exe("cacert.pem", ca_path, sizeof(ca_path))
              && !beside_exe("../share/cacert.pem", ca_path, sizeof(ca_path)))
            ca_path[0] = '\0';
    }
    return ca_path[0] ? ca_path : NULL;
}

CURLcode ppctls_global_init(void)
{
    static int done;
    CURLcode rc = CURLE_OK;
    if (!done) { rc = curl_global_init(CURL_GLOBAL_DEFAULT); done = (rc == CURLE_OK); }
    return rc;
}

CURLcode ppctls_curl_setup(CURL *h)
{
    static char ua[64];
    const char *ca = ppctls_ca_file();
    if (!ca) return CURLE_SSL_CACERT_BADFILE;
    if (!ua[0]) snprintf(ua, sizeof(ua), "ppctls/%s", curl_version_info(CURLVERSION_NOW)->version);
    curl_easy_setopt(h, CURLOPT_CAINFO, ca);
    curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(h, CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(h, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(h, CURLOPT_USERAGENT, ua);
    return CURLE_OK;
}

const char *ppctls_version(void)
{
    static char v[128];
    if (!v[0])
        snprintf(v, sizeof(v), "OpenSSL %s / curl %s / %s slice, %s", OPENSSL_FULL_VERSION_STR,
                 curl_version_info(CURLVERSION_NOW)->version, PPC_SLICE,
#ifdef __VEC__
                 "AltiVec"
#else
                 "no AltiVec"
#endif
                 );
    return v;
}
