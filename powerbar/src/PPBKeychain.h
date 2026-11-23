/* The Pandora password, kept in the user's login keychain (Mac OS X 10.2+ API). */
#import <Foundation/Foundation.h>

@interface PPBKeychain : NSObject
+ (NSString *)passwordForAccount:(NSString *)account;
+ (BOOL)setPassword:(NSString *)password forAccount:(NSString *)account;
+ (void)removePasswordForAccount:(NSString *)account;
@end
