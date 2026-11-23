/* SUEdDSAVerifier: Ed25519 update signatures on OpenSSL 3, in current Sparkle's
 * format: SUPublicEDKey (Info.plist) is the raw 32-byte public key in base64, and
 * sparkle:edSignature (the appcast's <enclosure>) the raw 64-byte signature of the
 * whole archive in base64. Keys and signatures from Sparkle 2's generate_keys and
 * sign_update work unchanged, as do ours (bin/generate_keys, bin/sign_update). */
#import <Foundation/Foundation.h>

@interface SUEdDSAVerifier : NSObject
/* YES only if signature is a valid Ed25519 signature of the file at path by
 * publicKey. A missing or malformed key or signature is a NO. */
+ (BOOL)validatePath:(NSString *)path withEncodedEdSignature:(NSString *)signature
     withPublicEdKey:(NSString *)publicKey;
@end
