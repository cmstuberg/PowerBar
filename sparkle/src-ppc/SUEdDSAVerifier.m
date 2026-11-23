#import "SUEdDSAVerifier.h"
#include <openssl/evp.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_ARCHIVE (1024L * 1024 * 1024)

/* Strict base64: the standard alphabet, whitespace and up to two trailing '='.
 * Returns the decoded length, or -1 if it's malformed or longer than max. */
static long b64decode (const char *in, unsigned char *out, size_t max) {
    unsigned long v = 0;
    int bits = 0, pad = 0;
    size_t n = 0;
    for (; *in; in++) {
        int c = (unsigned char) *in, d;
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        if (c == '=') { pad++; continue; }
        if (pad) return -1;
        if (c >= 'A' && c <= 'Z') d = c - 'A';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 26;
        else if (c >= '0' && c <= '9') d = c - '0' + 52;
        else if (c == '+') d = 62;
        else if (c == '/') d = 63;
        else return -1;
        v = ((v << 6) | d) & 0xffffff;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n >= max) return -1;
            out[n++] = (unsigned char) (v >> bits);
        }
    }
    return pad > 2 ? -1 : (long) n;
}

@implementation SUEdDSAVerifier

+ (BOOL)validatePath:(NSString *)path withEncodedEdSignature:(NSString *)signature
     withPublicEdKey:(NSString *)publicKey {
    unsigned char pub[48], sig[96];
    struct stat st;
    void *m;
    int fd;
    EVP_PKEY *key;
    EVP_MD_CTX *ctx;
    BOOL ok;

    if (path == nil || signature == nil || publicKey == nil) return NO;
    if (b64decode ([publicKey UTF8String], pub, sizeof pub) != 32) return NO;
    if (b64decode ([signature UTF8String], sig, sizeof sig) != 64) return NO;

    fd = open ([path fileSystemRepresentation], O_RDONLY);
    if (fd < 0) return NO;
    if (fstat (fd, &st) != 0 || !S_ISREG (st.st_mode) || st.st_size <= 0 || st.st_size > MAX_ARCHIVE) {
        close (fd);
        return NO;
    }
    m = mmap (NULL, (size_t) st.st_size, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
    close (fd);
    if (m == MAP_FAILED) return NO;

    key = EVP_PKEY_new_raw_public_key (EVP_PKEY_ED25519, NULL, pub, 32);
    ctx = EVP_MD_CTX_new ();
    ok = key != NULL && ctx != NULL
        && EVP_DigestVerifyInit (ctx, NULL, NULL, NULL, key) == 1
        && EVP_DigestVerify (ctx, sig, 64, m, (size_t) st.st_size) == 1;
    EVP_MD_CTX_free (ctx);
    EVP_PKEY_free (key);
    munmap (m, (size_t) st.st_size);
    return ok;
}

@end
