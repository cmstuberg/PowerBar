/* fwtest: SparkleTest.app embeds build/Sparkle.framework the way a real app does
 * (Contents/Frameworks, linked by @loader_path) and checks, in a logged-in GUI session:
 *   - the framework loads from inside the app, with its resources
 *   - SUUpdater picks up the app's Info.plist (SUFeedURL, SUEnableAutomaticChecks)
 *   - Sparkle's version comparator orders build numbers as expected
 *   - the update alert window builds from its nib, with an item's title and notes
 * Prints "fwtest: PASS/FAIL: ..." per check; exits 0 only if all pass. */
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#import <WebKit/WebKit.h>
#import "SUBasicUpdateDriver.h"   /* from the Sparkle source tree (test/Makefile) */
#import "SUScheduledUpdateDriver.h"
#import "SUUpdateAlert.h"
#import "SUHost.h"

static int failures = 0;

static void expect (BOOL ok, NSString *what) {
    printf ("fwtest: %s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok) failures++;
}

/* private Sparkle classes, reached the way an app can't by accident */
@interface NSObject (FWTestPrivate)
+ (id)defaultComparator;
- (NSComparisonResult)compareVersion:(NSString *)a toVersion:(NSString *)b;
- (id)initWithBundle:(NSBundle *)b;
- (id)initWithAppcastItem:(SUAppcastItem *)item host:(id)host;
- (NSString *)version;
- (NSString *)displayVersion;
@end

/* ---- network modes (test/nettest.sh drives them) ---- */

/* exported by Sparkle.framework (src-ppc/SUCurlURLProtocol.h) */
extern void SUCurlTagRequest (NSMutableURLRequest *request);

@interface NSObject (FWTestDSA)
+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)sig withPublicDSAKey:(NSString *)key;
+ (BOOL)validatePath:(NSString *)path withEncodedEdSignature:(NSString *)sig withPublicEdKey:(NSString *)key;
@end

/* Runs the main run loop until *flag or secs pass, and records the longest gap
 * between run loop passes: networking must never block the main thread. */
static double maxStall;
static void runUntil (BOOL *flag, double secs) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:secs];
    NSDate *last = [NSDate date];
    maxStall = 0;
    while (!*flag && [limit timeIntervalSinceNow] > 0) {
        double gap;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        gap = -[last timeIntervalSinceNow];
        if (gap > maxStall) maxStall = gap;
        last = [NSDate date];
    }
}

/* --fetch URL: Sparkle's own SUAppcast fetch, as SUUpdater runs it */
@interface FWFetch : NSObject {
@public
    BOOL done;
    int result;
    NSDate *start;
}
@end

@implementation FWFetch
- (void)appcastDidFinishLoading:(SUAppcast *)appcast {
    printf ("fetch: OK: %u items (%.1f s, max stall %.2f s)\n", (unsigned) [[appcast items] count],
            -[start timeIntervalSinceNow], maxStall);
    result = [[appcast items] count] > 0 ? 0 : 1;
    done = YES;
}
- (void)appcast:(SUAppcast *)appcast failedToLoadWithError:(NSError *)error {
    printf ("fetch: FAIL: %s (%.1f s, max stall %.2f s)\n",
            [[[error userInfo] objectForKey:NSLocalizedFailureReasonErrorKey] UTF8String],
            -[start timeIntervalSinceNow], maxStall);
    result = 1;
    done = YES;
}
@end

static int fetch (const char *url) {
    FWFetch *f = [[FWFetch alloc] init];
    SUAppcast *a = [[SUAppcast alloc] init];
    int rc;
    f->start = [NSDate date];
    [a setDelegate:f];
    [a fetchAppcastFromURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]];
    runUntil (&f->done, 90);
    if (!f->done) printf ("fetch: FAIL: no answer in 90 s\n");
    rc = f->done ? f->result : 1;
    [a release];
    [f release];
    return rc;
}

/* --download URL DIR: an NSURLDownload set up the way SUBasicUpdateDriver does
 * (tagged request, its own User-Agent, no gzip decoding), reporting the file name
 * NSURLDownload picks, the expected length and the summed progress callbacks. */
@interface FWDownload : NSObject {
@public
    BOOL done;
    int result;
    NSString *dir, *path;
    long long expected, progress;
}
@end

@implementation FWDownload
- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name {
    path = [[dir stringByAppendingPathComponent:name] retain];
    [d setDestination:path allowOverwrite:YES];
}
- (void)download:(NSURLDownload *)d didReceiveResponse:(NSURLResponse *)r {
    expected = [r expectedContentLength];
}
- (void)download:(NSURLDownload *)d didReceiveDataOfLength:(unsigned)length {
    progress += length;
}
- (BOOL)download:(NSURLDownload *)d shouldDecodeSourceDataOfMIMEType:(NSString *)type {
    return NO;
}
- (void)downloadDidFinish:(NSURLDownload *)d {
    NSDictionary *at = [[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:NO];
    printf ("download: OK: name=%s bytes=%lld expected=%lld progress=%lld\n",
            [[path lastPathComponent] UTF8String], [[at objectForKey:NSFileSize] longLongValue],
            expected, progress);
    done = YES;
}
- (void)download:(NSURLDownload *)d didFailWithError:(NSError *)e {
    printf ("download: FAIL: %s\n", [[e localizedDescription] UTF8String]);
    result = 1;
    done = YES;
}
@end

static int download (const char *url, const char *dir) {
    FWDownload *f = [[FWDownload alloc] init];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[NSString stringWithUTF8String:url]]];
    NSURLDownload *d;
    int rc;
    f->dir = [NSString stringWithUTF8String:dir];
    [r setValue:@"SparkleTest/0.6 Sparkle/1.5" forHTTPHeaderField:@"User-Agent"];
    SUCurlTagRequest (r);
    d = [[NSURLDownload alloc] initWithRequest:r delegate:f];
    runUntil (&f->done, 120);
    if (!f->done) printf ("download: FAIL: no answer in 120 s\n");
    rc = f->done ? f->result : 1;
    [d release];
    [f release];
    return rc;
}

/* --notes URL MARKER: the real update alert with a release notes link; waits for
 * the WebView to finish and looks for MARKER in the page it got. */
static int notes (const char *url, const char *marker) {
    NSDictionary *enclosure = [NSDictionary dictionaryWithObjectsAndKeys:
        @"https://example.invalid/SparkleTest_7.zip", @"url", @"7", @"sparkle:version", nil];
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:@"SparkleTest 0.7", @"title",
        enclosure, @"enclosure", [NSString stringWithUTF8String:url], @"sparkle:releaseNotesLink", nil];
    SUAppcastItem *item = [[[SUAppcastItem alloc] initWithDictionary:d] autorelease];
    id host = [[[NSClassFromString (@"SUHost") alloc] initWithBundle:[NSBundle mainBundle]] autorelease];
    id alert = [[NSClassFromString (@"SUUpdateAlert") alloc] initWithAppcastItem:item host:host];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:60];
    BOOL finished = NO;
    NSData *page;
    NSString *html;
    [alert window];
    while (!finished && [limit timeIntervalSinceNow] > 0) {
        BOOL f = NO;
        runUntil (&f, 0.3);
        finished = [[alert valueForKey:@"webViewFinishedLoading"] boolValue];
    }
    page = [[[[alert valueForKey:@"releaseNotesView"] mainFrame] dataSource] data];
    html = page ? [[[NSString alloc] initWithData:page encoding:NSUTF8StringEncoding] autorelease] : nil;
    if (finished && html && [html rangeOfString:[NSString stringWithUTF8String:marker]].location != NSNotFound)
        printf ("notes: OK: %u bytes, marker found\n", (unsigned) [page length]);
    else
        printf ("notes: FAIL: finished=%d bytes=%u\n", finished, (unsigned) [page length]);
    [[alert window] close];
    [alert release];
    return finished && html && [html rangeOfString:[NSString stringWithUTF8String:marker]].location != NSNotFound ? 0 : 1;
}

/* --ed PUBKEY SIGNATURE FILE: the Ed25519 check (src-ppc/SUEdDSAVerifier.m) */
static int ed (const char *pub, const char *sig, const char *file) {
    BOOL ok = [NSClassFromString (@"SUEdDSAVerifier") validatePath:[NSString stringWithUTF8String:file]
               withEncodedEdSignature:[NSString stringWithUTF8String:sig]
                      withPublicEdKey:[NSString stringWithUTF8String:pub]];
    printf ("ed: %s\n", ok ? "OK" : "FAIL");
    return ok ? 0 : 1;
}

/* --driver FEED: Sparkle's own SUBasicUpdateDriver (no UI) checks FEED against this
 * app's Info.plist, downloads, checks the signature and extracts the archive, then
 * stops where it would install: "driver: INSTALL: version N" or "driver: ABORT: why". */
@interface FWDriver : SUBasicUpdateDriver {
@public
    BOOL done;
    int result;
}
@end

static BOOL realInstall = NO;   /* --install: go on and really install + relaunch */

@implementation FWDriver
- (void)installUpdate {
    printf ("driver: INSTALL: version %s\n", [[updateItem versionString] UTF8String]);
    fflush (stdout);
    if (realInstall) {
        [super installUpdate];   /* swaps the app on disk, relaunches it, quits us */
        return;
    }
    done = YES;
}
- (void)abortUpdateWithError:(NSError *)error {
    NSString *why = [[error userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
    if (!done)
        printf ("driver: ABORT: %s\n", [(why ? why : [error localizedDescription]) UTF8String]);
    result = 1;
    done = YES;
    [super abortUpdate];
}
@end

static int driver (const char *feed) {
    id host = [[NSClassFromString (@"SUHost") alloc] initWithBundle:[NSBundle mainBundle]];
    FWDriver *d = [[FWDriver alloc] initWithUpdater:nil];
    int rc;
    [d checkForUpdatesAtURL:[NSURL URLWithString:[NSString stringWithUTF8String:feed]] host:host];
    runUntil (&d->done, 120);
    if (!d->done) printf ("driver: FAIL: no result in 120 s\n");
    rc = d->done ? d->result : 1;
    [d release];
    [host release];
    return rc;
}

/* --scheduled FEED [skip]: Sparkle's scheduled (background) check, with its real
 * update window. If the window comes up it's answered "Skip This Version" (skip) or
 * "Remind Me Later"; prints "scheduled: ALERT: version N, skipped|later". If the check
 * ends without any window (nothing new, skipped, offline): "scheduled: QUIET". */
static BOOL scheduledDone;
@interface FWScheduledWatch : NSObject
@end
@implementation FWScheduledWatch
- (void)finished:(NSNotification *)n { scheduledDone = YES; }
@end

static id visibleAlert (void) {
    NSArray *ws = [NSApp windows];
    unsigned i;
    for (i = 0; i < [ws count]; i++) {
        NSWindow *w = [ws objectAtIndex:i];
        if ([w isVisible] && [[w windowController] isKindOfClass:[SUUpdateAlert class]])
            return [w windowController];
    }
    return nil;
}

static int scheduled (const char *feed, BOOL skip) {
    SUUpdater *u = [SUUpdater sharedUpdater];
    SUHost *host = [[SUHost alloc] initWithBundle:[NSBundle mainBundle]];
    SUScheduledUpdateDriver *d = [[SUScheduledUpdateDriver alloc] initWithUpdater:u];
    FWScheduledWatch *watch = [[FWScheduledWatch alloc] init];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:90];
    BOOL alerted = NO;
    unsigned i, shown = 0;
    /* we run the loop ourselves, so finish launching as [NSApp run] would: Sparkle only
     * shows its window while the app is active */
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];
    [[NSNotificationCenter defaultCenter] addObserver:watch selector:@selector(finished:)
        name:SUUpdateDriverFinishedNotification object:d];
    [d checkForUpdatesAtURL:[NSURL URLWithString:[NSString stringWithUTF8String:feed]] host:host];
    while (!scheduledDone && [limit timeIntervalSinceNow] > 0) {
        BOOL f = NO;
        id alert;
        runUntil (&f, 0.3);
        /* the alert as shown, or (if the app isn't frontmost yet) as the driver holds it */
        alert = visibleAlert ();
        if (alert == nil) alert = [d valueForKey:@"updateAlert"];
        if (!alerted && alert != nil) {
            alerted = YES;
            printf ("scheduled: ALERT: version %s, %s\n",
                    [[[alert valueForKey:@"updateItem"] versionString] UTF8String], skip ? "skipped" : "later");
            if (skip) [alert skipThisVersion:nil]; else [alert remindMeLater:nil];
        }
    }
    for (i = 0; i < [[NSApp windows] count]; i++)
        if ([[[NSApp windows] objectAtIndex:i] isVisible]) shown++;
    if (!scheduledDone) printf ("scheduled: FAIL: the check didn't finish in 90 s\n");
    else if (!alerted) printf ("scheduled: %s\n", shown ? "FAIL: a window was left open" : "QUIET");
    [[NSNotificationCenter defaultCenter] removeObserver:watch];
    /* Sparkle keeps "skip this version" in the app's user defaults, which a real app
     * saves when it quits; we return from main instead, so save them here */
    [[NSUserDefaults standardUserDefaults] synchronize];
    return scheduledDone && shown == 0 ? 0 : 1;
}

/* --dsa PUBKEY.pem SIGNATURE FILE: Sparkle's DSA check (patch 0002) */
static int dsa (const char *pem, const char *sig, const char *file) {
    NSString *key = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:pem]];
    BOOL ok = [NSClassFromString (@"SUDSAVerifier") validatePath:[NSString stringWithUTF8String:file]
               withEncodedDSASignature:[NSString stringWithUTF8String:sig] withPublicDSAKey:key];
    printf ("dsa: %s\n", ok ? "OK" : "FAIL");
    return ok ? 0 : 1;
}

static void versions (void) {
    id cmp = [NSClassFromString (@"SUStandardVersionComparator") defaultComparator];
    struct { NSString *a, *b; NSComparisonResult want; } t[] = {
        { @"6", @"7", NSOrderedAscending },
        { @"7", @"6", NSOrderedDescending },
        { @"6", @"6", NSOrderedSame },
        { @"1.9", @"1.10", NSOrderedAscending },
        { @"1.0b1", @"1.0", NSOrderedAscending },
        { @"1.0", @"1.0.1", NSOrderedAscending },
        { @"1.0b2", @"1.0rc1", NSOrderedAscending },
    };
    unsigned i;
    expect (cmp != nil, @"SUStandardVersionComparator present");
    for (i = 0; i < sizeof t / sizeof t[0]; i++) {
        NSComparisonResult r = [cmp compareVersion:t[i].a toVersion:t[i].b];
        expect (r == t[i].want, [NSString stringWithFormat:@"compare %@ vs %@ = %d", t[i].a, t[i].b, (int) r]);
    }
}

static void alertWindow (NSBundle *app) {
    NSDictionary *enclosure = [NSDictionary dictionaryWithObjectsAndKeys:
        @"https://example.invalid/SparkleTest_7.zip", @"url",
        @"7", @"sparkle:version", @"0.7", @"sparkle:shortVersionString", nil];
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        @"SparkleTest 0.7", @"title", enclosure, @"enclosure",
        @"<p>Test release notes.</p>", @"description", nil];
    SUAppcastItem *item = [[[SUAppcastItem alloc] initWithDictionary:d] autorelease];
    id host = [[[NSClassFromString (@"SUHost") alloc] initWithBundle:app] autorelease];
    id alert;
    NSWindow *w;
    expect (item != nil && [[item versionString] isEqualToString:@"7"]
           && [[item displayVersionString] isEqualToString:@"0.7"], @"SUAppcastItem from a feed dictionary");
    expect (host != nil && [[host version] isEqualToString:@"6"] && [[host displayVersion] isEqualToString:@"0.6"],
           @"SUHost reads the app's CFBundleVersion / short version");
    alert = [[NSClassFromString (@"SUUpdateAlert") alloc] initWithAppcastItem:item host:host];
    w = [alert window];
    expect (w != nil, @"update alert window loads from SUUpdateAlert.nib");
    expect ([[w title] length] > 0, [NSString stringWithFormat:@"update alert title: %@", [w title]]);
    [w close];
    [alert release];
}

int main (int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSBundle *app = [NSBundle mainBundle], *fw;
    NSString *fwPath, *relaunch;
    SUUpdater *u;
    NSArray *nibs;
    unsigned i;

    [NSApplication sharedApplication];
    if (argc > 1 && strncmp (argv[1], "--", 2) == 0) {
        int rc = 2;
        if (argc == 3 && strcmp (argv[1], "--fetch") == 0) rc = fetch (argv[2]);
        else if (argc == 4 && strcmp (argv[1], "--download") == 0) rc = download (argv[2], argv[3]);
        else if (argc == 4 && strcmp (argv[1], "--notes") == 0) rc = notes (argv[2], argv[3]);
        else if (argc == 5 && strcmp (argv[1], "--dsa") == 0) rc = dsa (argv[2], argv[3], argv[4]);
        else if (argc == 5 && strcmp (argv[1], "--ed") == 0) rc = ed (argv[2], argv[3], argv[4]);
        else if (argc == 3 && strcmp (argv[1], "--driver") == 0) rc = driver (argv[2]);
        else if (argc == 3 && strcmp (argv[1], "--install") == 0) { realInstall = YES; rc = driver (argv[2]); }
        else if (argc == 3 && strcmp (argv[1], "--scheduled") == 0) rc = scheduled (argv[2], NO);
        else if (argc == 4 && strcmp (argv[1], "--scheduled") == 0 && strcmp (argv[3], "skip") == 0)
            rc = scheduled (argv[2], YES);
        else fprintf (stderr, "usage: --fetch URL | --download URL DIR | --notes URL MARKER | --dsa PUB.pem SIG FILE | --ed PUB SIG FILE | --driver FEED | --install FEED | --scheduled FEED [skip]\n");
        [pool release];
        return rc;
    }

    /* A plain launch (as after Sparkle's relaunch) leaves "launched-<version>" next to
     * the app, so nettest.sh can see which version came back up. */
    [@"ok\n" writeToFile:[[[app bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:
        [@"launched-" stringByAppendingString:[app objectForInfoDictionaryKey:@"CFBundleVersion"]]] atomically:NO];

    fw = [NSBundle bundleWithIdentifier:@"org.andymatuschak.Sparkle"];
    fwPath = [[app privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
    expect (fw != nil, @"Sparkle.framework is loaded");
    expect ([[[fw bundlePath] stringByStandardizingPath] isEqualToString:[fwPath stringByStandardizingPath]],
           [NSString stringWithFormat:@"loaded from the app: %@", [fw bundlePath]]);
    expect ([[fw objectForInfoDictionaryKey:@"CFBundleVersion"] isEqualToString:@"1.5"], @"framework version 1.5");

    relaunch = [fw pathForResource:@"relaunch" ofType:@""];
    expect (relaunch != nil && [[NSFileManager defaultManager] isExecutableFileAtPath:relaunch],
           @"relaunch tool in Resources");
    nibs = [NSArray arrayWithObjects:@"SUUpdateAlert", @"SUAutomaticUpdateAlert",
            @"SUUpdatePermissionPrompt", @"SUStatus", nil];
    for (i = 0; i < [nibs count]; i++)
        expect ([fw pathForResource:[nibs objectAtIndex:i] ofType:@"nib"] != nil,
               [NSString stringWithFormat:@"%@.nib", [nibs objectAtIndex:i]]);
    expect ([[NSDictionary dictionaryWithContentsOfFile:[fw pathForResource:@"Sparkle" ofType:@"strings"]] count] > 10,
           @"Sparkle.strings (en) loads");

    u = [SUUpdater sharedUpdater];
    expect (u != nil, @"SUUpdater sharedUpdater");
    expect ([[[u feedURL] absoluteString] isEqualToString:[app objectForInfoDictionaryKey:@"SUFeedURL"]],
           [NSString stringWithFormat:@"feed URL from Info.plist: %@", [u feedURL]]);
    expect (![u automaticallyChecksForUpdates], @"SUEnableAutomaticChecks=NO honoured");

    versions ();
    alertWindow (app);

    printf ("fwtest: %s (%d failed) [%s slice]\n", failures ? "FAILED" : "all passed", failures, PPC_SLICE);
    [pool release];
    return failures ? 1 : 0;
}
