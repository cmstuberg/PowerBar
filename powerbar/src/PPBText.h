/* Non-ASCII UI strings. gcc-4.0 doesn't reliably treat @"" literals as UTF-8, so
 * they're written as UTF-8 byte escapes: U ("Working\xe2\x80\xa6").
 * Keep every @"" literal in the sources ASCII. */
#import <Foundation/Foundation.h>
#define U(s) [NSString stringWithUTF8String:(s)]
