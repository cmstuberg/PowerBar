/* powerbar-ctl COMMAND: tell a running PowerBar to do something, without bringing it
 * to the front. Used by the Dashboard widget. COMMAND is one of
 *   playpause next love ban tired show
 * It posts a distributed notification; PowerBar listens for it even in the
 * background. Mac OS X 10.4+. */
#import <Foundation/Foundation.h>

int main (int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (argc != 2) {
        fprintf (stderr, "usage: powerbar-ctl playpause|next|love|ban|tired|show\n");
        return 2;
    }
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"io.github.cmstuberg.PowerBar.command"
                      object:[NSString stringWithUTF8String:argv[1]]
                    userInfo:nil
          deliverImmediately:YES];
    [pool release];
    return 0;
}
