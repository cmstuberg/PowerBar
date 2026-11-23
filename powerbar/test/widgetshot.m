/* widgetshot WIDGET.html FRAGMENT OUT.png [W H]
 * Render the Dashboard widget's page in an offscreen WebView and save it as a PNG
 * with transparency. FRAGMENT goes after '#' ("empty" for Default.png, or
 * "state=/path/to/folder/" to show a nowplaying.json). Run it in a GUI session
 * (tools/gui-run). */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static NSString *outPath;
static WebView *web;

@interface Shot : NSObject
@end

@implementation Shot
- (void)webView:(WebView *)v didFinishLoadForFrame:(WebFrame *)f {
    if (f == [v mainFrame]) [self performSelector:@selector(capture) withObject:nil afterDelay:2.0];
}
- (void)capture {
    NSRect r = [web bounds];
    NSBitmapImageRep *rep = [web bitmapImageRepForCachingDisplayInRect:r];
    [web cacheDisplayInRect:r toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    BOOL ok = [png writeToFile:outPath atomically:YES];
    printf ("widgetshot: %s %s\n", ok ? "wrote" : "FAILED", [outPath UTF8String]);
    exit (ok ? 0 : 1);
}
- (void)timeout {
    printf ("widgetshot: page never finished loading\n");
    exit (1);
}
@end

int main (int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (argc < 4) { fprintf (stderr, "usage: widgetshot page.html fragment out.png [w h]\n"); return 2; }
    float w = argc > 5 ? atof (argv[4]) : 330, h = argc > 5 ? atof (argv[5]) : 124;
    [NSApplication sharedApplication];
    outPath = [[NSString stringWithUTF8String:argv[3]] retain];
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect (-2000, -2000, w, h)
                                                styleMask:NSBorderlessWindowMask
                                                  backing:NSBackingStoreBuffered defer:NO];
    [win setOpaque:NO];
    [win setBackgroundColor:[NSColor clearColor]];
    web = [[WebView alloc] initWithFrame:NSMakeRect (0, 0, w, h)];
    [web setDrawsBackground:NO];
    [win setContentView:web];
    [win orderBack:nil];
    Shot *s = [[Shot alloc] init];
    [web setFrameLoadDelegate:s];
    NSURL *page = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@#%s", [page absoluteString], argv[2]]];
    [[web mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
    [s performSelector:@selector(timeout) withObject:nil afterDelay:20];
    [NSApp run];
    [pool release];
    return 0;
}
