/* SUCurlURLProtocol: Sparkle's own HTTP(S) loads go through our curl + OpenSSL 3
 * (../tls) instead of the system's networking, which can't talk to modern servers
 * (GitHub) on 10.4/10.5.
 *
 * It is an NSURLProtocol, so NSURLDownload and WebView keep working exactly as in
 * stock Sparkle (destination files, progress, delegates). It only takes requests
 * Sparkle has tagged with SUCurlTagRequest: the host app's own networking is left
 * alone. CA bundle: the framework's Resources/cacert.pem ($PPC_TLS_CAFILE, if
 * set, replaces it; used by the tests). */
#import <Foundation/Foundation.h>

/* Marks a request as Sparkle's, so it loads through curl. */
void SUCurlTagRequest (NSMutableURLRequest *request);

/* A tagged copy (autoreleased). */
NSURLRequest *SUCurlTaggedRequest (NSURLRequest *request);
