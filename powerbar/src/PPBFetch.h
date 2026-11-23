/* Background HTTPS GETs (cover art) through our curl + OpenSSL 3 (tls/), since the
 * system's networking can't talk to modern servers on 10.4/10.5. */
#import <Foundation/Foundation.h>

@interface PPBFetch : NSObject
/* Fetches url on a background thread, then calls [target selector:result] on the
 * main thread. result is an NSArray: (url, data), where data is NSNull on failure. */
+ (void)fetchURL:(NSString *)url target:(id)target selector:(SEL)selector;
@end
