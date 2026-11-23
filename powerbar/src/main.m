/* PowerBar: a Cocoa front end for pianobar, for Mac OS X 10.4+ on PowerPC.
 * Nib-less, manual retain/release, no 10.5+ APIs.
 *
 *   PowerBar.app/Contents/MacOS/PowerBar --selftest
 * signs in with a dummy account through the whole app (bundled engine, TLS, event
 * script, parser) and exits 0 when Pandora's "wrong password" answer arrives. */
#import <Cocoa/Cocoa.h>
#include <signal.h>
#import "PPBController.h"

int main (int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    BOOL selftest = NO;
    int i;
    const char *snapshot = NULL, *uitest = NULL;
    for (i = 1; i < argc; i++) {
        if (strcmp (argv[i], "--selftest") == 0) selftest = YES;
        if (strcmp (argv[i], "--snapshot") == 0 && i + 1 < argc) snapshot = argv[++i];
        if (strcmp (argv[i], "--uitest") == 0 && i + 1 < argc) uitest = argv[++i];
    }

    /* writing to a dead engine must not kill the app */
    signal (SIGPIPE, SIG_IGN);

    [NSApplication sharedApplication];
    PPBController *c = [[PPBController alloc] initWithSelftest:selftest];
    if (snapshot) [c setSnapshotPath:[NSString stringWithUTF8String:snapshot]];
    if (uitest) [c setUITestDir:[NSString stringWithUTF8String:uitest]];
    [NSApp setDelegate:c];
    [NSApp run];
    [c release];
    [pool release];
    return 0;
}
