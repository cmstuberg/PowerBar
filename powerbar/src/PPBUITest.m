/* --uitest DIR: drive the real app against test/fake-pianobar-full (PPB_ENGINE).
 * Opens every feature, clicks the real buttons, checks what the app shows, and
 * saves window snapshots to DIR. Exit 0 = every step passed. */
#import "PPBController.h"
#import "PPBUI.h"
#import "PPBEngine.h"

static int failures, steps;
static NSString *snapDir;

static void spin (double t) {
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:t]];
}

#define WAIT(cond, secs) ({ NSDate *u_ = [NSDate dateWithTimeIntervalSinceNow:(secs)]; \
    while (!(cond) && [u_ timeIntervalSinceNow] > 0) spin (0.05); (BOOL) (cond); })

static void expect (const char *what, BOOL ok) {
    steps++;
    if (!ok) failures++;
    printf ("  %s  %s\n", ok ? "ok  " : "FAIL", what);
    fflush (stdout);
}

static NSButton *findButton (NSView *v, NSString *title) {
    if ([v isKindOfClass:[NSButton class]] && [[(NSButton *) v title] isEqualToString:title]) return (NSButton *) v;
    NSArray *sub = [v subviews];
    unsigned i;
    for (i = 0; i < [sub count]; i++) {
        NSButton *b = findButton ([sub objectAtIndex:i], title);
        if (b) return b;
    }
    return nil;
}

static BOOL click (NSWindow *w, NSString *title) {
    NSButton *b = findButton ([w contentView], title);
    if (b == nil) {
        printf ("        (no \"%s\" button in \"%s\")\n", [title UTF8String], [[w title] UTF8String]);
        return NO;
    }
    [b performClick:nil];
    return YES;
}

static void snap (NSWindow *w, NSString *name) {
    NSView *v = [w contentView];
    [v display];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    [[rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:[snapDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}

static void selectRow (NSTableView *t, int r) {
    [t selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
}

@interface PPBController (UITestPrivate)
- (void)startEngineWithPassword:(NSString *)pw;
@end

@implementation PPBController (UITest)

- (void)setUITestDir:(NSString *)dir {
    snapDir = [dir copy];
}

- (BOOL)uiTestRequested {
    return snapDir != nil;
}

- (BOOL)statusIs:(NSString *)s { return [[upNextLabel stringValue] isEqualToString:s]; }
- (BOOL)statusHas:(NSString *)s { return [[upNextLabel stringValue] rangeOfString:s].location != NSNotFound; }
- (NSWindow *)flowWindow { return [flow valueForKey:@"panel"]; }
- (BOOL)nowPlaying:(NSString *)path has:(NSString *)text {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return s != nil && [s rangeOfString:text].location != NSNotFound;
}
- (int)flowRows { return [[flow valueForKey:@"rows"] count]; }
- (NSString *)panelQuestion { return [actionPanel valueForKey:@"question"]; }

- (void)runUITest {
    printf ("uitest: driving the app against the scripted pianobar\n");
    account = [@"uitest@example.invalid" retain];
    [self startEngineWithPassword:@"pw"];
    expect ("signs in and plays", WAIT (songLoaded && [currentStation isEqualToString:@"Rock Radio"], 20));
    snap (window, @"main");

    /* The Dashboard widget: nowplaying.json tracks the song, and the bundled
     * powerbar-ctl drives the app (a distributed notification). */
    NSString *np = [[PPBEngine defaultSupportDirectory] stringByAppendingPathComponent:@"nowplaying.json"];
    NSString *ctl = [[[NSBundle mainBundle] pathForResource:@"PowerBar" ofType:@"wdgt"]
                     stringByAppendingPathComponent:@"powerbar-ctl"];
    expect ("widget: nowplaying.json has the song", WAIT ([self nowPlaying:np has:@"\"title\": \"Song 1\""] &&
                                                         [self nowPlaying:np has:@"\"running\": true"], 10));
    [[NSTask launchedTaskWithLaunchPath:ctl arguments:[NSArray arrayWithObject:@"love"]] waitUntilExit];
    expect ("widget: heart loves the song", WAIT ([self statusHas:@"Loved"] && [self nowPlaying:np has:@"\"loved\": true"], 10));
    [[NSTask launchedTaskWithLaunchPath:ctl arguments:[NSArray arrayWithObject:@"playpause"]] waitUntilExit];
    expect ("widget: pause", WAIT (paused && [self nowPlaying:np has:@"\"paused\": true"], 10));
    [[NSTask launchedTaskWithLaunchPath:ctl arguments:[NSArray arrayWithObject:@"playpause"]] waitUntilExit];
    expect ("widget: play", WAIT (!paused && [self nowPlaying:np has:@"\"paused\": false"], 10));
    [[NSTask launchedTaskWithLaunchPath:ctl arguments:[NSArray arrayWithObject:@"next"]] waitUntilExit];
    expect ("widget: next song", WAIT ([self nowPlaying:np has:@"\"title\": \"Song 2\""], 10));

    /* Why is this song playing? */
    [self explain:nil];
    expect ("explain: shows the reason", WAIT (flow && [[[flow valueForKey:@"text"] stringValue]
        rangeOfString:@"laid-back"].location != NSNotFound, 10));
    snap ([self flowWindow], @"explain");
    click ([self flowWindow], @"Close");
    expect ("explain: Close closes", WAIT (flow == nil, 5));

    /* Bookmark: a sheet with Song / Artist / Cancel */
    [self bookmark:nil];
    expect ("bookmark: sheet", WAIT ([window attachedSheet] != nil, 5));
    snap ([window attachedSheet], @"bookmark");
    click ([window attachedSheet], @"Artist");
    expect ("bookmark: artist bookmarked", WAIT ([self statusIs:@"Artist bookmarked."] && flow == nil, 10));

    /* New station from song: sheet, then tuned to the new station */
    [self newStationFromSong:nil];
    expect ("from song: sheet", WAIT ([window attachedSheet] != nil, 5));
    click ([window attachedSheet], @"Song");
    expect ("from song: created and tuned in", WAIT ([currentStation hasPrefix:@"Song "] && flow == nil, 10));

    /* Rename: one field */
    [self renameStation:nil];
    expect ("rename: sheet with the current name", WAIT ([window attachedSheet] == inputSheet, 5) &&
           [[inputField stringValue] isEqualToString:currentStation]);
    snap (inputSheet, @"rename");
    [inputField setStringValue:@"Renamed Radio"];
    click (inputSheet, @"OK");
    expect ("rename: renamed", WAIT ([self statusIs:@"Station renamed."] && [stationNames containsObject:@"Renamed Radio"]
                                    && [currentStation isEqualToString:@"Renamed Radio"], 10));

    /* Rename, cancelled */
    [self renameStation:nil];
    WAIT ([window attachedSheet] == inputSheet, 5);
    click (inputSheet, @"Cancel");
    expect ("rename: Cancel closes, nothing sent", WAIT ([window attachedSheet] == nil, 5) && flow == nil && [engine prompt] == nil);

    /* Shared station by ID */
    [self sharedStation:nil];
    WAIT ([window attachedSheet] == inputSheet, 5);
    [inputField setStringValue:@"12345"];
    click (inputSheet, @"OK");
    expect ("shared: added", WAIT ([self statusIs:@"Shared station added."] && [stationNames containsObject:@"Shared 12345"], 10));

    /* New station by search */
    [self newStation:nil];
    WAIT (flow != nil, 5);
    [[flow valueForKey:@"query"] setStringValue:@"miles"];
    click ([self flowWindow], @"Search");
    expect ("search: results", WAIT ([self flowRows] == 2 && [[flow valueForKey:@"commit"] isEnabled], 10));
    snap ([self flowWindow], @"newstation");
    [[flow valueForKey:@"scope"] selectItemAtIndex:1];
    [flow performSelector:@selector(scopeChanged:) withObject:nil];
    expect ("search: switch to songs", WAIT ([self flowRows] == 2 && [[[[flow valueForKey:@"rows"] objectAtIndex:0]
        objectAtIndex:1] hasSuffix:@"So What"] && [[flow valueForKey:@"commit"] isEnabled], 10));
    [[flow valueForKey:@"scope"] selectItemAtIndex:0];
    [flow performSelector:@selector(scopeChanged:) withObject:nil];
    WAIT ([self flowRows] == 2 && [[flow valueForKey:@"commit"] isEnabled], 10);
    selectRow ([flow valueForKey:@"table"], 0);
    click ([self flowWindow], @"Create");
    expect ("search: created and tuned in", WAIT (flow == nil && [currentStation isEqualToString:@"Miles Davis Radio"], 10));

    /* Search, then Cancel: closes at once, and the next feature still works */
    [self newStation:nil];
    WAIT (flow != nil, 5);
    [[flow valueForKey:@"query"] setStringValue:@"miles"];
    click ([self flowWindow], @"Search");
    WAIT ([self flowRows] == 2, 10);
    click ([self flowWindow], @"Cancel");
    expect ("search: Cancel closes at once", flow == nil && [engine prompt] == nil);
    [self explain:nil];
    expect ("search: next feature works after Cancel", WAIT (flow && [[[flow valueForKey:@"text"] stringValue]
        rangeOfString:@"laid-back"].location != NSNotFound, 10));
    click ([self flowWindow], @"Close");
    WAIT (flow == nil, 5);

    /* Add music */
    [self addMusic:nil];
    WAIT (flow != nil, 5);
    [[flow valueForKey:@"query"] setStringValue:@"so what"];
    click ([self flowWindow], @"Search");
    WAIT ([self flowRows] == 2 && [[flow valueForKey:@"commit"] isEnabled], 10);
    selectRow ([flow valueForKey:@"table"], 0);
    click ([self flowWindow], @"Add");
    expect ("add music: added", WAIT ([self statusHas:@"Added"] && flow == nil, 10));

    /* Station mode (also the Mode... button) */
    [modeButton performClick:nil];
    expect ("mode: list of modes", WAIT ([self flowRows] == 2 && [[flow valueForKey:@"use"] isEnabled], 10));
    snap ([self flowWindow], @"mode");
    selectRow ([flow valueForKey:@"table"], 1);
    click ([self flowWindow], @"Use Mode");
    expect ("mode: changed", WAIT ([self statusIs:@"Mode: Deep Cuts."] && flow == nil, 10));

    /* Seeds */
    [self stationSeeds:nil];
    expect ("seeds: artists", WAIT ([self flowRows] == 2 && [[flow valueForKey:@"removeButton"] isEnabled], 10));
    snap ([self flowWindow], @"seeds");
    selectRow ([flow valueForKey:@"table"], 0);
    click ([self flowWindow], @"Remove");
    expect ("seeds: removed, list reloaded", WAIT ([self statusIs:@"Seed removed."] && [self flowRows] == 2 &&
                                                  [[flow valueForKey:@"removeButton"] isEnabled], 10));
    [[flow valueForKey:@"category"] selectItemAtIndex:1];
    [flow performSelector:@selector(categoryChanged:) withObject:nil];
    expect ("seeds: songs", WAIT ([self flowRows] == 1 && [[flow valueForKey:@"removeButton"] isEnabled], 10));
    click ([self flowWindow], @"Close");
    expect ("seeds: Close closes", WAIT (flow == nil && [engine prompt] == nil, 5));

    /* Thumbs */
    [self thumbs:nil];
    expect ("thumbs: your ratings", WAIT ([self flowRows] == 2 && [[flow valueForKey:@"removeButton"] isEnabled], 10));
    snap ([self flowWindow], @"thumbs");
    click ([self flowWindow], @"Close");
    WAIT (flow == nil, 5);

    /* Shuffle: not on the Shuffle station yet, so offer to switch */
    [self shuffle:nil];
    expect ("shuffle: offers to switch", WAIT ([[[flow valueForKey:@"save"] title] isEqualToString:@"Switch to It"] &&
                                                   [[flow valueForKey:@"save"] isEnabled], 10));
    snap ([self flowWindow], @"shuffle-switch");
    click ([self flowWindow], @"Switch to It");
    expect ("shuffle: checkboxes after switching", WAIT ([[[flow valueForKey:@"save"] title] isEqualToString:@"Save"] &&
                                                       [[flow valueForKey:@"save"] isEnabled], 15));
    snap ([self flowWindow], @"shuffle");
    NSTableView *t = [flow valueForKey:@"table"];
    NSTableColumn *want = [t tableColumnWithIdentifier:@"want"];
    id f = flow;
    int n = [f numberOfRowsInTableView:t], i;
    for (i = 0; i < n; i++) {     /* flip every station */
        BOOL cur = [[f tableView:t objectValueForTableColumn:want row:i] boolValue];
        [f tableView:t setObjectValue:[NSNumber numberWithBool:!cur] forTableColumn:want row:i];
    }
    click ([self flowWindow], @"Save");
    expect ("shuffle: saved", WAIT ([self statusIs:@"Shuffle updated."] && flow == nil, 15));

    /* History: the general panel */
    [self history:nil];
    expect ("history: songs", WAIT ([[self panelQuestion] hasPrefix:@"Select song"], 10));
    snap ([actionPanel panelWindow], @"history");
    selectRow ([actionPanel valueForKey:@"table"], 0);
    click ([actionPanel panelWindow], @"OK");
    expect ("history: song actions", WAIT ([[self panelQuestion] hasPrefix:@"What to do"], 10));
    snap ([actionPanel panelWindow], @"history-actions");
    click ([actionPanel panelWindow], @"Love");
    expect ("history: loved, panel closed", WAIT (flow == nil && ![[actionPanel panelWindow] isVisible] &&
                                                 [self statusHas:@"Lov"], 10));

    /* Genre station */
    [self genreStation:nil];
    WAIT ([[self panelQuestion] hasPrefix:@"Select category"], 10);
    snap ([actionPanel panelWindow], @"genre");
    selectRow ([actionPanel valueForKey:@"table"], 0);
    click ([actionPanel panelWindow], @"OK");
    WAIT ([[self panelQuestion] hasPrefix:@"Select genre"], 10);
    selectRow ([actionPanel valueForKey:@"table"], 0);
    click ([actionPanel panelWindow], @"OK");
    expect ("genre: added, panel closed", WAIT ([stationNames containsObject:@"Bebop Radio"] && flow == nil &&
                                               ![[actionPanel panelWindow] isVisible], 10));

    /* Explicit content: a sheet with On / Off / Cancel */
    [self explicitContent:nil];
    expect ("explicit: sheet says it's on", WAIT ([window attachedSheet] != nil, 10) &&
            findButton ([[window attachedSheet] contentView], @"Off") != nil);
    snap ([window attachedSheet], @"explicit");
    click ([window attachedSheet], @"Off");
    expect ("explicit: turned off", WAIT ([self statusIs:@"Explicit content off."] && flow == nil, 10));
    [self explicitContent:nil];
    WAIT ([window attachedSheet] != nil, 10);
    click ([window attachedSheet], @"Cancel");
    expect ("explicit: Cancel changes nothing", WAIT (flow == nil && [engine prompt] == nil &&
                                                     [window attachedSheet] == nil, 5));

    /* Delete */
    [self deleteStation:nil];
    WAIT ([window attachedSheet] != nil, 5);
    snap ([window attachedSheet], @"delete");
    click ([window attachedSheet], @"Delete");
    expect ("delete: deleted", WAIT ([self statusHas:@"Station deleted"] && flow == nil, 10));

    quitting = YES;
    [engine stop];
    expect ("quits cleanly", WAIT (![engine isRunning], 5));
    [self applicationShouldTerminate:NSApp];
    expect ("widget: quitting says not running", [self nowPlaying:np has:@"\"running\": false"]);
    printf ("uitest: %d/%d passed%s\n", steps - failures, steps, failures ? " - FAILED" : "");
    fflush (stdout);
    exit (failures ? 1 : 0);
}

@end
