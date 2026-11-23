#import "SUCurlURLProtocol.h"
#include <curl/curl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

/* How it runs: NSURLConnection calls -startLoading on its loader thread, and every
 * call back to the client must come from that thread. So there is no extra thread:
 * a curl multi handle is driven by a CFRunLoopTimer on the loader thread's run loop
 * (curl resolves names asynchronously, so a tick never blocks). Redirects are
 * followed inside curl; an https request may only be redirected to https. */

static NSString *const kTagKey = @"SUCurlURLProtocol";
static const CFTimeInterval kTick = 0.01;

void SUCurlTagRequest (NSMutableURLRequest *request) {
    [NSURLProtocol setProperty:[NSNumber numberWithBool:YES] forKey:kTagKey inRequest:request];
}

NSURLRequest *SUCurlTaggedRequest (NSURLRequest *request) {
    NSMutableURLRequest *m = [[request mutableCopy] autorelease];
    SUCurlTagRequest (m);
    return m;
}

@interface SUCurlURLProtocol : NSURLProtocol {
    CURLM *multi;
    CURL *easy;
    struct curl_slist *headers;
    CFRunLoopTimerRef timer;
    NSMutableData *pending;
    char errbuf[CURL_ERROR_SIZE];
    void *hctx[2];                 /* header callback: easy handle, &finalHeaders */
    BOOL finalHeaders, responseSent, done;
}
- (void)tick;
@end

static void tickCb (CFRunLoopTimerRef t, void *info) {
    [(SUCurlURLProtocol *) info tick];
}

static size_t writeCb (char *p, size_t size, size_t n, void *ctx) {
    NSMutableData **pending = ctx;
    [*pending appendBytes:p length:size * n];
    return size * n;
}

/* The blank line after a final (2xx) response's headers. Redirects (3xx) and
 * interim (1xx) responses are followed by more headers. */
static size_t headerCb (char *p, size_t size, size_t n, void *ctx) {
    void **c = ctx;
    size_t len = size * n;
    if ((len == 2 && p[0] == '\r' && p[1] == '\n') || (len == 1 && p[0] == '\n')) {
        long code = 0;
        curl_easy_getinfo ((CURL *) c[0], CURLINFO_RESPONSE_CODE, &code);
        if (code >= 200 && code < 300) *(BOOL *) c[1] = YES;
    }
    return len;
}

static NSString *caFile (void) {
    const char *env = getenv ("PPC_TLS_CAFILE");
    if (env != NULL && *env && access (env, R_OK) == 0)
        return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:env length:strlen (env)];
    return [[NSBundle bundleForClass:NSClassFromString (@"SUCurlURLProtocol")] pathForResource:@"cacert" ofType:@"pem"];
}

static NSError *errorFor (CURLcode rc, const char *eb, NSURL *url) {
    int code;
    switch (rc) {
    case CURLE_COULDNT_RESOLVE_HOST:
    case CURLE_COULDNT_RESOLVE_PROXY:     code = NSURLErrorCannotFindHost; break;
    case CURLE_COULDNT_CONNECT:           code = NSURLErrorCannotConnectToHost; break;
    case CURLE_OPERATION_TIMEDOUT:        code = NSURLErrorTimedOut; break;
    case CURLE_PEER_FAILED_VERIFICATION:
    case CURLE_SSL_CACERT_BADFILE:        code = NSURLErrorServerCertificateUntrusted; break;
    case CURLE_SSL_CONNECT_ERROR:         code = NSURLErrorSecureConnectionFailed; break;
    case CURLE_UNSUPPORTED_PROTOCOL:      code = NSURLErrorUnsupportedURL; break;
    case CURLE_TOO_MANY_REDIRECTS:        code = NSURLErrorHTTPTooManyRedirects; break;
    case CURLE_HTTP_RETURNED_ERROR:       code = NSURLErrorBadServerResponse; break;
    default:                              code = NSURLErrorUnknown; break;
    }
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:
        [NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithFormat:@"%s", (eb && eb[0]) ? eb : curl_easy_strerror (rc)], NSLocalizedDescriptionKey,
            [url absoluteString], NSErrorFailingURLStringKey, nil]];
}

@implementation SUCurlURLProtocol

+ (void)load {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    curl_global_init (CURL_GLOBAL_DEFAULT);
    [NSURLProtocol registerClass:self];
    [pool release];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = [[[request URL] scheme] lowercaseString];
    NSString *method = [request HTTPMethod];
    return [NSURLProtocol propertyForKey:kTagKey inRequest:request] != nil
        && ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])
        && (method == nil || [method isEqualToString:@"GET"]);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)failWith:(CURLcode)rc message:(const char *)msg {
    done = YES;
    [[self client] URLProtocol:self didFailWithError:errorFor (rc, msg, [[self request] URL])];
}

- (void)startLoading {
    NSURLRequest *req = [self request];
    NSString *ca = caFile ();
    BOOL https = [[[[req URL] scheme] lowercaseString] isEqualToString:@"https"];
    long timeout = (long) [req timeoutInterval];
    NSDictionary *fields = [req allHTTPHeaderFields];
    NSEnumerator *e = [fields keyEnumerator];
    NSString *k;
    CFRunLoopTimerContext tc = { 0, self, NULL, NULL, NULL };

    if (ca == nil) {
        [self failWith:CURLE_SSL_CACERT_BADFILE message:"no CA bundle (Sparkle.framework/Resources/cacert.pem)"];
        return;
    }
    if (timeout <= 0) timeout = 60;
    errbuf[0] = 0;
    pending = [[NSMutableData alloc] init];
    easy = curl_easy_init ();
    multi = curl_multi_init ();
    if (easy == NULL || multi == NULL) {
        [self failWith:CURLE_FAILED_INIT message:NULL];
        return;
    }
    curl_easy_setopt (easy, CURLOPT_URL, [[[req URL] absoluteString] UTF8String]);
    curl_easy_setopt (easy, CURLOPT_CAINFO, [ca fileSystemRepresentation]);
    curl_easy_setopt (easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt (easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt (easy, CURLOPT_SSLVERSION, (long) CURL_SSLVERSION_TLSv1_2);
    curl_easy_setopt (easy, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt (easy, CURLOPT_REDIR_PROTOCOLS_STR, https ? "https" : "http,https");
    curl_easy_setopt (easy, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt (easy, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt (easy, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt (easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt (easy, CURLOPT_CONNECTTIMEOUT, timeout < 30 ? timeout : 30L);
    curl_easy_setopt (easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt (easy, CURLOPT_LOW_SPEED_TIME, timeout);
    curl_easy_setopt (easy, CURLOPT_ERRORBUFFER, errbuf);
    curl_easy_setopt (easy, CURLOPT_WRITEFUNCTION, writeCb);
    curl_easy_setopt (easy, CURLOPT_WRITEDATA, &pending);
    hctx[0] = easy;
    hctx[1] = &finalHeaders;
    curl_easy_setopt (easy, CURLOPT_HEADERFUNCTION, headerCb);
    curl_easy_setopt (easy, CURLOPT_HEADERDATA, hctx);
    while ((k = [e nextObject]) != nil)
        headers = curl_slist_append (headers,
            [[NSString stringWithFormat:@"%@: %@", k, [fields objectForKey:k]] UTF8String]);
    if ([fields objectForKey:@"User-Agent"] == nil)
        curl_easy_setopt (easy, CURLOPT_USERAGENT, "Sparkle/1.5");
    if (headers != NULL) curl_easy_setopt (easy, CURLOPT_HTTPHEADER, headers);
    curl_multi_add_handle (multi, easy);

    timer = CFRunLoopTimerCreate (NULL, CFAbsoluteTimeGetCurrent (), kTick, 0, 0, tickCb, &tc);
    CFRunLoopAddTimer (CFRunLoopGetCurrent (), timer, kCFRunLoopCommonModes);
}

- (void)cleanup {
    if (timer != NULL) {
        CFRunLoopTimerInvalidate (timer);
        CFRelease (timer);
        timer = NULL;
    }
    if (multi != NULL && easy != NULL) curl_multi_remove_handle (multi, easy);
    if (easy != NULL) curl_easy_cleanup (easy);
    if (multi != NULL) curl_multi_cleanup (multi);
    if (headers != NULL) curl_slist_free_all (headers);
    easy = NULL;
    multi = NULL;
    headers = NULL;
}

- (void)stopLoading {
    done = YES;
    [self cleanup];
}

- (void)dealloc {
    [self cleanup];
    [pending release];
    [super dealloc];
}

/* The response, sent once the final headers are in. Its URL is the requested one
 * (not the last redirect's), so NSURLDownload names the file after the link in the
 * feed: GitHub release links redirect to an opaque storage URL. */
- (void)sendResponse {
    char *ct = NULL;
    curl_off_t len = -1;
    NSString *type = nil, *mime = @"application/octet-stream", *charset = nil;
    NSURLResponse *r;
    responseSent = YES;
    curl_easy_getinfo (easy, CURLINFO_CONTENT_TYPE, &ct);
    curl_easy_getinfo (easy, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &len);
    if (ct != NULL) type = [NSString stringWithUTF8String:ct];
    if ([type length]) {
        NSArray *parts = [type componentsSeparatedByString:@";"];
        unsigned i;
        NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
        NSString *m = [[parts objectAtIndex:0] stringByTrimmingCharactersInSet:ws];
        if ([m length]) mime = [m lowercaseString];
        for (i = 1; i < [parts count]; i++) {
            NSString *p = [[parts objectAtIndex:i] stringByTrimmingCharactersInSet:ws];
            if ([[p lowercaseString] hasPrefix:@"charset="])
                charset = [[p substringFromIndex:8] stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"\"' "]];
        }
    }
    r = [[NSURLResponse alloc] initWithURL:[[self request] URL] MIMEType:mime
                     expectedContentLength:(len >= 0 && len < 0x7fffffff) ? (int) len : -1
                          textEncodingName:charset];
    [[self client] URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [r release];
}

- (void)flush {
    if (responseSent && [pending length] > 0) {
        NSData *d = pending;
        pending = [[NSMutableData alloc] init];
        [[self client] URLProtocol:self didLoadData:d];
        [d release];
    }
}

- (void)tick {
    int running = 0, queued = 0;
    CURLMsg *m;
    if (done || multi == NULL) return;
    [[self retain] autorelease];   /* a client call may end with -stopLoading */
    curl_multi_perform (multi, &running);
    if (finalHeaders && !responseSent) [self sendResponse];
    if (done) return;
    [self flush];
    if (done) return;
    while ((m = curl_multi_info_read (multi, &queued)) != NULL) {
        if (m->msg != CURLMSG_DONE) continue;
        if (m->data.result == CURLE_OK) {
            if (!responseSent) [self sendResponse];
            if (done) return;
            [self flush];
            if (done) return;
            done = YES;
            [self cleanup];
            [[self client] URLProtocolDidFinishLoading:self];
        } else {
            CURLcode rc = m->data.result;
            char msg[CURL_ERROR_SIZE];
            strlcpy (msg, errbuf, sizeof msg);
            [self cleanup];
            [self failWith:rc message:msg];
        }
        return;
    }
}

@end
