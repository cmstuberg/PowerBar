#import "PPBFetch.h"
#include "ppctls.h"

#define MAX_BYTES (4 * 1024 * 1024)

static size_t appendCb (char *ptr, size_t size, size_t nmemb, void *ctx) {
    NSMutableData *d = ctx;
    if ([d length] + size * nmemb > MAX_BYTES) return 0;
    [d appendBytes:ptr length:size * nmemb];
    return size * nmemb;
}

@implementation PPBFetch

+ (void)initialize {
    if (self == [PPBFetch class]) ppctls_global_init ();
}

+ (void)fetchURL:(NSString *)url target:(id)target selector:(SEL)selector {
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:
        url, @"url", target, @"target", NSStringFromSelector (selector), @"selector", nil];
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:job];
}

+ (void)run:(NSDictionary *)job {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *url = [job objectForKey:@"url"];
    NSMutableData *data = [NSMutableData data];
    BOOL ok = NO;
    CURL *h = curl_easy_init ();
    if (h != NULL && ppctls_curl_setup (h) == CURLE_OK) {
        curl_easy_setopt (h, CURLOPT_URL, [url UTF8String]);
        curl_easy_setopt (h, CURLOPT_WRITEFUNCTION, appendCb);
        curl_easy_setopt (h, CURLOPT_WRITEDATA, data);
        curl_easy_setopt (h, CURLOPT_FAILONERROR, 1L);
        curl_easy_setopt (h, CURLOPT_TIMEOUT, 30L);
        curl_easy_setopt (h, CURLOPT_NOSIGNAL, 1L);
        ok = curl_easy_perform (h) == CURLE_OK && [data length] > 0;
    }
    if (h != NULL) curl_easy_cleanup (h);
    NSArray *result = [NSArray arrayWithObjects:url, ok ? (id) data : (id) [NSNull null], nil];
    [[job objectForKey:@"target"] performSelectorOnMainThread:NSSelectorFromString ([job objectForKey:@"selector"])
                                                   withObject:result waitUntilDone:NO];
    [pool release];
}

@end
