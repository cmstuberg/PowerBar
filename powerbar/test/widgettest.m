/* widgettest WIDGET.html STATEDIR
 * Runs the Dashboard widget's real page in an offscreen WebView (as widgetshot does),
 * pointed at STATEDIR instead of PowerBar's support folder, and plays the app's part:
 * four songs, each with a solid-colour cover written the way PowerBar writes them
 * (alternating cover-1 / cover-0, then nowplaying.json naming it). After each song it
 * reads the colour back off the widget's art canvas. The widget must show every new
 * cover, including when a song reuses a cover file name that an earlier song had.
 * Prints "widgettest: ok/FAIL ..." per song; exits 0 only if all pass. Run it in a GUI
 * session (tools/gui-run). */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static WebView *web;
static NSString *dir;
static int song = 0, failures = 0;

static const struct { const char *name; int r, g, b; } colours[] = {
    { "red", 220, 30, 30 }, { "green", 30, 200, 40 }, { "blue", 30, 60, 230 }, { "yellow", 230, 210, 30 },
};
#define SONGS ((int) (sizeof colours / sizeof colours[0]))

static NSData *solidPNG (int r, int g, int b) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:32 * 3 bitsPerPixel:24] autorelease];
    unsigned char *p = [rep bitmapData];
    int i;
    for (i = 0; i < 32 * 32; i++) { p[3 * i] = r; p[3 * i + 1] = g; p[3 * i + 2] = b; }
    return [rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
}

@interface Run : NSObject
@end

@implementation Run
- (void)webView:(WebView *)v didFinishLoadForFrame:(WebFrame *)f {
    if (f == [v mainFrame]) [self performSelector:@selector(nextSong) withObject:nil afterDelay:1.0];
}

/* what PowerBar does on a new song: the cover file, then nowplaying.json naming it */
- (void)nextSong {
    NSString *cover = [NSString stringWithFormat:@"cover-%d", (song + 1) % 2];
    NSString *json = [NSString stringWithFormat:
        @"{\"running\": true, \"written\": %.3f, \"title\": \"Song %d\", \"artist\": \"Artist\", "
        @"\"album\": \"Album\", \"station\": \"Test Radio\", \"elapsed\": 0, \"total\": 180, "
        @"\"paused\": false, \"loved\": false, \"art\": \"%@\", \"upnext\": \"\"}\n",
        [[NSDate date] timeIntervalSince1970], song + 1, cover];
    [solidPNG (colours[song].r, colours[song].g, colours[song].b)
        writeToFile:[dir stringByAppendingPathComponent:cover] atomically:YES];
    [json writeToFile:[dir stringByAppendingPathComponent:@"nowplaying.json"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    /* the widget reads nowplaying.json once a second */
    [self performSelector:@selector(check) withObject:nil afterDelay:2.5];
}

- (void)check {
    /* below the gloss, away from the rounded border */
    NSString *px = [web stringByEvaluatingJavaScriptFromString:
        @"(function () { var d = document.getElementById ('art').getContext ('2d')"
        @".getImageData (42, 62, 1, 1).data; return d[0] + ',' + d[1] + ',' + d[2]; }) ()"];
    NSArray *c = [px componentsSeparatedByString:@","];
    int r = -999, g = -999, b = -999;
    BOOL ok;
    if ([c count] == 3) {
        r = [[c objectAtIndex:0] intValue]; g = [[c objectAtIndex:1] intValue]; b = [[c objectAtIndex:2] intValue];
    }
    ok = abs (r - colours[song].r) < 40 && abs (g - colours[song].g) < 40 && abs (b - colours[song].b) < 40;
    printf ("widgettest: %s song %d (cover-%d): want %s, canvas shows %d,%d,%d\n", ok ? "ok  " : "FAIL",
            song + 1, (song + 1) % 2, colours[song].name, r, g, b);
    if (!ok) failures++;
    if (++song < SONGS) {
        [self nextSong];
    } else {
        printf ("widgettest: %s (%d of %d failed)\n", failures ? "FAILED" : "all passed", failures, SONGS);
        exit (failures ? 1 : 0);
    }
}

- (void)timeout {
    printf ("widgettest: FAIL: page never finished loading\n");
    exit (1);
}
@end

int main (int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSWindow *win;
    NSURL *page, *url;
    Run *run;
    if (argc != 3) { fprintf (stderr, "usage: widgettest page.html statedir\n"); return 2; }
    [NSApplication sharedApplication];
    dir = [[NSString stringWithUTF8String:argv[2]] retain];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir attributes:nil];
    win = [[NSWindow alloc] initWithContentRect:NSMakeRect (-2000, -2000, 330, 124)
                                      styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    web = [[WebView alloc] initWithFrame:NSMakeRect (0, 0, 330, 124)];
    [win setContentView:web];
    [win orderBack:nil];
    run = [[Run alloc] init];
    [web setFrameLoadDelegate:run];
    page = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    url = [NSURL URLWithString:[NSString stringWithFormat:@"%@#state=%@/", [page absoluteString],
        [dir stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    [[web mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
    [run performSelector:@selector(timeout) withObject:nil afterDelay:20];
    [NSApp run];
    [pool release];
    return 0;
}
