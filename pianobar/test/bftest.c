/* bftest: compat/gcrypt.h (Blowfish on OpenSSL) against published ECB test vectors
 * (Eric Young's set, as used by OpenSSL and libgcrypt), plus a round trip through
 * libpiano's own PianoEncryptString/PianoDecryptString. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "crypt.h"   /* libpiano: pulls in our gcrypt.h */

static const struct { const char *key, *pt, *ct; } vec[] = {
	{ "0000000000000000", "0000000000000000", "4EF997456198DD78" },
	{ "FFFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFF", "51866FD5B85ECB8A" },
	{ "3000000000000000", "1000000000000001", "7D856F9A613063F2" },
	{ "1111111111111111", "1111111111111111", "2466DD878B963C9D" },
	{ "0123456789ABCDEF", "1111111111111111", "61F9C3802281B096" },
	{ "FEDCBA9876543210", "0123456789ABCDEF", "0ACEAB0FC6A0A28D" },
};

static void unhex (const char *s, unsigned char *out) {
	for (size_t i = 0; s[2*i]; i++) {
		unsigned int b;
		sscanf (s + 2*i, "%2x", &b);
		out[i] = (unsigned char) b;
	}
}

int main (void) {
	int fail = 0;
	for (size_t i = 0; i < sizeof (vec) / sizeof (*vec); i++) {
		unsigned char key[8], pt[8], ct[8], buf[8];
		unhex (vec[i].key, key); unhex (vec[i].pt, pt); unhex (vec[i].ct, ct);
		gcry_cipher_hd_t h;
		if (gcry_cipher_open (&h, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0) ||
				gcry_cipher_setkey (h, key, 8)) {
			printf ("vector %zu: setup failed\n", i); return 1;
		}
		memcpy (buf, pt, 8);
		gcry_cipher_encrypt (h, buf, 8, NULL, 0);
		int ok = memcmp (buf, ct, 8) == 0;
		gcry_cipher_decrypt (h, buf, 8, NULL, 0);
		ok = ok && memcmp (buf, pt, 8) == 0;
		gcry_cipher_close (h);
		printf ("vector %zu: %s\n", i, ok ? "ok" : "FAIL");
		fail += !ok;
	}

	/* libpiano round trip with pianobar's default (public) Android partner keys */
	gcry_cipher_hd_t in, out;
	const char *inkey = "R=U!LH$O2B#", *outkey = "6#26FRL$ZWD";
	gcry_cipher_open (&in, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0);
	gcry_cipher_setkey (in, inkey, strlen (inkey));
	gcry_cipher_open (&out, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0);
	gcry_cipher_setkey (out, outkey, strlen (outkey));
	const char *msg = "{\"syncTime\":1234567890,\"note\":\"PowerPC\"}";
	char *enc = PianoEncryptString (in, msg);
	size_t n = 0;
	char *dec = enc ? PianoDecryptString (in, enc, &n) : NULL;
	int ok = dec != NULL && strncmp (dec, msg, strlen (msg)) == 0 && n % 8 == 0;
	printf ("libpiano round trip: %s\n", ok ? "ok" : "FAIL");
	fail += !ok;
	free (enc); free (dec);
	gcry_cipher_close (in); gcry_cipher_close (out);

	printf ("%s\n", fail ? "FAILED" : "PASS");
	return fail != 0;
}
