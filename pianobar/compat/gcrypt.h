/* gcrypt.h: the small part of the libgcrypt API that libpiano uses (Blowfish in ECB
 * mode), implemented with OpenSSL's Blowfish from our TLS stack (tls/dist).
 *
 * Why: libgcrypt is only used for this, and building it for 10.4/PowerPC means
 * libgpg-error plus a newer compiler. OpenSSL is already linked in for curl.
 *
 * Part of PowerBar. MIT licence, like pianobar. */
#ifndef PPB_GCRYPT_COMPAT_H
#define PPB_GCRYPT_COMPAT_H

/* BF_* are deprecated in OpenSSL 3 but still built; there's no EVP route to Blowfish
 * without loading the legacy provider. */
#define OPENSSL_SUPPRESS_DEPRECATED 1
#include <openssl/blowfish.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned int gcry_error_t;
typedef struct ppb_gcry_cipher { BF_KEY key; } *gcry_cipher_hd_t;

#define GPG_ERR_NO_ERROR      0
#define GPG_ERR_GENERAL       1
#define GCRY_CIPHER_BLOWFISH  4
#define GCRY_CIPHER_MODE_ECB  1
#define GCRYCTL_DISABLE_SECMEM           37
#define GCRYCTL_INITIALIZATION_FINISHED  38

static inline const char *gcry_check_version (const char *req) {
	(void) req;
	return "ppb-openssl";
}

/* gcry_control (cmd, ...): nothing to configure here. */
#define gcry_control(...) ((gcry_error_t) GPG_ERR_NO_ERROR)

static inline gcry_error_t gcry_cipher_open (gcry_cipher_hd_t *h, int algo,
		int mode, unsigned int flags) {
	(void) flags;
	*h = NULL;
	if (algo != GCRY_CIPHER_BLOWFISH || mode != GCRY_CIPHER_MODE_ECB) {
		return GPG_ERR_GENERAL;
	}
	*h = calloc (1, sizeof (**h));
	return *h != NULL ? GPG_ERR_NO_ERROR : GPG_ERR_GENERAL;
}

static inline gcry_error_t gcry_cipher_setkey (gcry_cipher_hd_t h,
		const void *key, size_t len) {
	if (h == NULL || len == 0 || len > 56) {
		return GPG_ERR_GENERAL;
	}
	BF_set_key (&h->key, (int) len, key);
	return GPG_ERR_NO_ERROR;
}

static inline gcry_error_t ppb_gcry_ecb (gcry_cipher_hd_t h, void *out,
		size_t outlen, const void *in, size_t inlen, int enc) {
	/* libgcrypt semantics: in == NULL means encrypt/decrypt out in place */
	const unsigned char *src = in != NULL ? in : out;
	unsigned char *dst = out;
	size_t len = in != NULL ? inlen : outlen;
	if (h == NULL || len % BF_BLOCK != 0 || outlen < len) {
		return GPG_ERR_GENERAL;
	}
	for (size_t i = 0; i < len; i += BF_BLOCK) {
		BF_ecb_encrypt (src + i, dst + i, &h->key, enc);
	}
	return GPG_ERR_NO_ERROR;
}

static inline gcry_error_t gcry_cipher_encrypt (gcry_cipher_hd_t h, void *out,
		size_t outlen, const void *in, size_t inlen) {
	return ppb_gcry_ecb (h, out, outlen, in, inlen, BF_ENCRYPT);
}

static inline gcry_error_t gcry_cipher_decrypt (gcry_cipher_hd_t h, void *out,
		size_t outlen, const void *in, size_t inlen) {
	return ppb_gcry_ecb (h, out, outlen, in, inlen, BF_DECRYPT);
}

static inline void gcry_cipher_close (gcry_cipher_hd_t h) {
	if (h != NULL) {
		memset (h, 0, sizeof (*h));
		free (h);
	}
}

#endif
