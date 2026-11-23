/* tlscheck: end-to-end test of the bundled TLS stack.
 * Good sites must connect with verified certificates; bad ones must be refused.
 * Exit 0 only if every expectation holds. */
#include <stdio.h>
#include <string.h>
#include "ppctls.h"

struct buf { char data[16384]; size_t len; };

static size_t sink(char *p, size_t sz, size_t n, void *ud)
{
    struct buf *b = ud;
    size_t k = sz * n, room = sizeof(b->data) - 1 - b->len;
    if (k > room) k = room;
    memcpy(b->data + b->len, p, k); b->len += k; b->data[b->len] = '\0';
    return sz * n;
}

static int fetch(const char *url, int expect_ok, const char *show_field)
{
    CURL *h = curl_easy_init();
    struct buf b; CURLcode rc; long code = 0;
    struct curl_tlssessioninfo *ti = NULL;
    char err[CURL_ERROR_SIZE] = "";
    b.len = 0; b.data[0] = '\0';
    ppctls_curl_setup(h);
    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
    curl_easy_setopt(h, CURLOPT_WRITEDATA, &b);
    curl_easy_setopt(h, CURLOPT_ERRORBUFFER, err);
    curl_easy_setopt(h, CURLOPT_TIMEOUT, 30L);
    rc = curl_easy_perform(h);
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &code);
    (void)ti;
    if (expect_ok) {
        int ok = (rc == CURLE_OK && code < 400);
        printf("%s %-45s HTTP %ld%s%s\n", ok ? "PASS" : "FAIL", url, code, rc ? " " : "", rc ? err : "");
        if (ok && show_field) {
            const char *f = strstr(b.data, show_field);
            if (f) { const char *e = strchr(f, ','); printf("     %.*s\n", e ? (int)(e - f) : 60, f); }
        }
        curl_easy_cleanup(h); return ok;
    } else {
        int ok = (rc != CURLE_OK);
        printf("%s %-45s refused: %s\n", ok ? "PASS" : "FAIL", url, ok ? err : "(connected!)");
        curl_easy_cleanup(h); return ok;
    }
}

int main(void)
{
    int ok = 1;
    ppctls_global_init();
    printf("%s\nCA bundle: %s\n", ppctls_version(), ppctls_ca_file() ? ppctls_ca_file() : "(none)");
    ok &= fetch("https://www.howsmyssl.com/a/check", 1, "\"tls_version\"");
    ok &= fetch("https://www.howsmyssl.com/a/check", 1, "\"rating\"");
    ok &= fetch("https://api.github.com/zen", 1, NULL);
    ok &= fetch("https://tls-v1-2.badssl.com:1012/", 1, NULL);
    ok &= fetch("https://expired.badssl.com/", 0, NULL);
    ok &= fetch("https://wrong.host.badssl.com/", 0, NULL);
    ok &= fetch("https://self-signed.badssl.com/", 0, NULL);
    ok &= fetch("https://untrusted-root.badssl.com/", 0, NULL);
    ok &= fetch("https://tls-v1-0.badssl.com:1010/", 0, NULL);
    printf("%s\n", ok ? "ALL PASS" : "SOME FAILED");
    curl_global_cleanup();
    return ok ? 0 : 1;
}
