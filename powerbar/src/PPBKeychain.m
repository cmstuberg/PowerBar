#import "PPBKeychain.h"
#include <Security/Security.h>

static const char kService[] = "PowerBar";
static const char kOldService[] = "PandoraPowerBar";    /* the app's name up to 0.4 */

@implementation PPBKeychain

+ (SecKeychainItemRef)itemForAccount:(NSString *)account service:(const char *)service
                            password:(NSString **)password {  /* caller releases */
    const char *acc = [account UTF8String];
    UInt32 len = 0;
    void *data = NULL;
    SecKeychainItemRef item = NULL;
    OSStatus st = SecKeychainFindGenericPassword (NULL, strlen (service), service,
            strlen (acc), acc, password ? &len : NULL, password ? &data : NULL, &item);
    if (st != noErr) return NULL;
    if (password) {
        *password = [[[NSString alloc] initWithBytes:data length:len
                                            encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent (NULL, data);
    }
    return item;
}

+ (NSString *)passwordForAccount:(NSString *)account {
    if ([account length] == 0) return nil;
    NSString *pw = nil;
    SecKeychainItemRef item = [self itemForAccount:account service:kService password:&pw];
    if (item) {
        CFRelease (item);
        return pw;
    }
    /* saved by PandoraPowerBar (0.4 and earlier): move it under the new name */
    item = [self itemForAccount:account service:kOldService password:&pw];
    if (item) {
        if ([self setPassword:pw forAccount:account]) SecKeychainItemDelete (item);
        CFRelease (item);
    }
    return pw;
}

+ (BOOL)setPassword:(NSString *)password forAccount:(NSString *)account {
    if ([account length] == 0) return NO;
    const char *acc = [account UTF8String];
    const char *pw = [password UTF8String];
    SecKeychainItemRef item = [self itemForAccount:account service:kService password:NULL];
    OSStatus st;
    if (item) {
        st = SecKeychainItemModifyAttributesAndData (item, NULL, strlen (pw), pw);
        CFRelease (item);
    } else {
        st = SecKeychainAddGenericPassword (NULL, strlen (kService), kService,
                strlen (acc), acc, strlen (pw), pw, NULL);
    }
    return st == noErr;
}

+ (void)removePasswordForAccount:(NSString *)account {
    if ([account length] == 0) return;
    SecKeychainItemRef item = [self itemForAccount:account service:kService password:NULL];
    if (item) {
        SecKeychainItemDelete (item);
        CFRelease (item);
    }
}

@end
