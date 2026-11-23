#import "PPBController.h"
#import "PPBKeychain.h"
#import "PPBFetch.h"
#import "PPBUI.h"
#import <Sparkle/Sparkle.h>

#define PIANO_RET_OK 1
#define kAccountKey @"Account"
#define kQualityKey @"AudioQuality"
#define kElapsedKey @"ShowElapsedTime"

/* What a feature needs before it can run. */
typedef enum { NeedEngine, NeedSong, NeedStation } Need;

static NSMenuItem *addItem (NSMenu *menu, NSString *title, SEL action, NSString *key, id target) {
    NSMenuItem *i = [menu addItemWithTitle:title action:action keyEquivalent:key];
    [i setTarget:target];
    return i;
}

static NSString *fkey (unichar c) {
    return [NSString stringWithFormat:@"%C", c];
}

static NSString *clockText (int s) {
    return [NSString stringWithFormat:@"%d:%02d", s / 60, s % 60];
}

/* A JSON string literal (the widget eval()s the file, so escape everything odd). */
static NSString *jsonString (NSString *s) {
    NSMutableString *o = [NSMutableString stringWithString:@"\""];
    unsigned i, n = [s length];
    for (i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '\\') [o appendFormat:@"\\%C", c];
        else if (c < 0x20 || c == 0x2028 || c == 0x2029 || c > 0x7e) [o appendFormat:@"\\u%04x", c];
        else [o appendFormat:@"%C", c];
    }
    [o appendString:@"\""];
    return o;
}

static void selftestResult (BOOL pass, NSString *detail) {
    printf ("selftest: %s: %s\n", pass ? "PASS" : "FAIL", [detail UTF8String]);
    fflush (stdout);
}

/* --- player window: plain keys --- */

@implementation PPBPlayerWindow

- (void)setKeyTarget:(id)target {
    keyTarget = target;
}

- (void)sendEvent:(NSEvent *)e {
    if ([e type] == NSKeyDown && [self attachedSheet] == nil &&
        !([e modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask))) {
        NSString *k = [e charactersIgnoringModifiers];
        unichar c = [k length] ? [k characterAtIndex:0] : 0;
        SEL a = NULL;
        if (c == ' ' && ![e isARepeat]) a = @selector(playPause:);
        else if (c == NSRightArrowFunctionKey && ![e isARepeat]) a = @selector(next:);
        if (a != NULL) {
            [keyTarget performSelector:a withObject:self];
            return;
        }
    }
    [super sendEvent:e];
}

@end

@implementation PPBController

- (id)initWithSelftest:(BOOL)flag {
    if ((self = [super init])) {
        selftest = flag;
        /* up to 0.4 the app was PandoraPowerBar, with its own preferences domain */
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (!flag && [d objectForKey:kAccountKey] == nil) {
            NSDictionary *old = [d persistentDomainForName:@"io.github.cmstuberg.PandoraPowerBar"];
            NSEnumerator *e = [old keyEnumerator];
            id k;
            while ((k = [e nextObject])) [d setObject:[old objectForKey:k] forKey:k];
            if ([old count]) [d synchronize];
        }
        [[NSUserDefaults standardUserDefaults] registerDefaults:
            [NSDictionary dictionaryWithObjectsAndKeys:@"high", kQualityKey,
                [NSNumber numberWithBool:NO], kElapsedKey, nil]];
    }
    return self;
}

- (void)setSnapshotPath:(NSString *)path {
    [snapshotPath release];
    snapshotPath = [path copy];
}

- (void)dealloc {
    [snapshotPath release];
    [upNextText release];
    [artFile release];
    [flow release];
    [engine release];
    [actionPanel release];
    [window release];
    [loginSheet release];
    [inputSheet release];
    [account release];
    [artURL release];
    [stationNames release];
    [currentStation release];
    [super dealloc];
}

/* --- building the UI --- */

/* The Song and Station features; also listed under the window's Actions button. */
- (void)addSongItems:(NSMenu *)m {
    addItem (m, @"Why Is This Song Playing?", @selector(explain:), @"", self);
    addItem (m, U ("Bookmark Song or Artist" ELLIPSIS), @selector(bookmark:), @"", self);
    addItem (m, U ("History" ELLIPSIS), @selector(history:), @"", self);
}

- (void)addStationItems:(NSMenu *)m {
    addItem (m, U ("New Station" ELLIPSIS), @selector(newStation:), @"", self);
    addItem (m, U ("New Station from Song or Artist" ELLIPSIS), @selector(newStationFromSong:), @"", self);
    addItem (m, U ("Add Genre Station" ELLIPSIS), @selector(genreStation:), @"", self);
    addItem (m, U ("Add Shared Station" ELLIPSIS), @selector(sharedStation:), @"", self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, U ("Add Music to Station" ELLIPSIS), @selector(addMusic:), @"", self);
    addItem (m, U ("Rename Station" ELLIPSIS), @selector(renameStation:), @"", self);
    addItem (m, U ("Delete Station" ELLIPSIS), @selector(deleteStation:), @"", self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, U ("Station Mode" ELLIPSIS), @selector(stationMode:), @"", self);
    addItem (m, U ("Station Seeds" ELLIPSIS), @selector(stationSeeds:), @"", self);
    addItem (m, U ("Thumbs Up & Down" ELLIPSIS), @selector(thumbs:), @"", self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, U ("Shuffle Stations" ELLIPSIS), @selector(shuffle:), @"", self);
}

- (void)buildMenus {
    NSString *name = @"PowerBar";
    NSMenu *bar = [[[NSMenu alloc] init] autorelease];

    NSMenu *m = [[[NSMenu alloc] initWithTitle:name] autorelease];
    addItem (m, [@"About " stringByAppendingString:name], @selector(about:), @"", self);
    addItem (m, U ("Check for Updates" ELLIPSIS), @selector(checkForUpdates:), @"", self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, U ("Explicit Content" ELLIPSIS), @selector(explicitContent:), @"", self);
    addItem (m, U ("Install Dashboard Widget" ELLIPSIS), @selector(installWidget:), @"", self);
    addItem (m, U ("Sign Out" ELLIPSIS), @selector(signOut:), @"", self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, [@"Hide " stringByAppendingString:name], @selector(hide:), @"h", NSApp);
    addItem (m, @"Hide Others", @selector(hideOtherApplications:), @"h", NSApp);
    [[[m itemArray] lastObject] setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    addItem (m, @"Show All", @selector(unhideAllApplications:), @"", NSApp);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, [@"Quit " stringByAppendingString:name], @selector(terminate:), @"q", NSApp);
    [[bar addItemWithTitle:name action:NULL keyEquivalent:@""] setSubmenu:m];
    /* Without a nib, this registers our menu as the application menu; otherwise
     * OS X adds its own (empty) one in front of it. */
    if ([NSApp respondsToSelector:@selector(setAppleMenu:)])
        [NSApp performSelector:@selector(setAppleMenu:) withObject:m];

    /* Edit: so copy/paste work in the text fields */
    m = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    [m addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [m addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [m addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [m addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [[bar addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""] setSubmenu:m];

    m = [[[NSMenu alloc] initWithTitle:@"Controls"] autorelease];
    addItem (m, @"Play/Pause (Space)", @selector(playPause:), @"p", self);
    addItem (m, U ("Next Song (\xe2\x86\x92)"), @selector(next:), fkey (NSRightArrowFunctionKey), self);
    [m addItem:[NSMenuItem separatorItem]];
    addItem (m, @"Love Song", @selector(love:), @"l", self);
    addItem (m, @"Ban Song", @selector(ban:), @"b", self);
    addItem (m, @"Tired of Song", @selector(tired:), @"t", self);
    [m addItem:[NSMenuItem separatorItem]];
    NSMenu *q = [[[NSMenu alloc] initWithTitle:@"Audio Quality"] autorelease];
    NSArray *qs = [NSArray arrayWithObjects:@"low", @"medium", @"high", nil];
    unsigned i;
    for (i = 0; i < [qs count]; i++) {
        NSMenuItem *it = addItem (q, [[qs objectAtIndex:i] capitalizedString], @selector(setQuality:), @"", self);
        [it setRepresentedObject:[qs objectAtIndex:i]];
    }
    [[m addItemWithTitle:@"Audio Quality" action:NULL keyEquivalent:@""] setSubmenu:q];
    addItem (m, @"Reconnect", @selector(reconnect:), @"", self);
    [[bar addItemWithTitle:@"Controls" action:NULL keyEquivalent:@""] setSubmenu:m];

    m = [[[NSMenu alloc] initWithTitle:@"Song"] autorelease];
    [self addSongItems:m];
    [[bar addItemWithTitle:@"Song" action:NULL keyEquivalent:@""] setSubmenu:m];

    m = [[[NSMenu alloc] initWithTitle:@"Station"] autorelease];
    [self addStationItems:m];
    [[bar addItemWithTitle:@"Station" action:NULL keyEquivalent:@""] setSubmenu:m];

    m = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    [m addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    addItem (m, @"Player", @selector(showPlayer:), @"1", self);
    [[bar addItemWithTitle:@"Window" action:NULL keyEquivalent:@""] setSubmenu:m];
    [NSApp setWindowsMenu:m];

    [NSApp setMainMenu:bar];
}

- (void)buildWindow {
    window = [[PPBPlayerWindow alloc] initWithContentRect:NSMakeRect (0, 0, 586, 236)
                                                styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                                  backing:NSBackingStoreBuffered defer:NO];
    [window setKeyTarget:self];
    [window setTitle:@"PowerBar"];
    [window setReleasedWhenClosed:NO];
    NSView *v = [window contentView];

    /* top at the station menu, bottom at the buttons */
    art = [[[NSImageView alloc] initWithFrame:NSMakeRect (16, 12, 206, 206)] autorelease];
    [art setImageFrameStyle:NSImageFrameGrayBezel];
    [art setImageScaling:NSScaleProportionally];
    [art setEditable:NO];
    [v addSubview:art];

    const float x = 238, w = 332;
    stations = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (x - 3, 192, w - 160, 26) pullsDown:NO] autorelease];
    [stations setTarget:self];
    [stations setAction:@selector(stationChosen:)];
    [stations addItemWithTitle:@"No stations yet"];
    [stations setEnabled:NO];
    [v addSubview:stations];

    /* the station's mode gets its own button */
    modeButton = PPBButton (v, NSMakeRect (x + w - 161, 191, 76, 28), U ("Mode" ELLIPSIS), self, @selector(stationMode:));

    /* every other feature */
    actions = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (x + w - 86, 192, 89, 26) pullsDown:YES] autorelease];
    [actions addItemWithTitle:@"Actions"];
    [self addSongItems:[actions menu]];
    [[actions menu] addItem:[NSMenuItem separatorItem]];
    [self addStationItems:[actions menu]];
    [v addSubview:actions];

    titleLabel  = PPBLabel (v, NSMakeRect (x, 162, w, 22), 15, YES);
    artistLabel = PPBLabel (v, NSMakeRect (x, 140, w, 20), 13, NO);
    albumLabel  = PPBLabel (v, NSMakeRect (x, 121, w, 18), 11, NO);
    [albumLabel setTextColor:[NSColor grayColor]];

    progress = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect (x, 96, w - 98, 12)] autorelease];
    [progress setIndeterminate:NO];
    [progress setControlSize:NSSmallControlSize];
    [progress setMinValue:0];
    [progress setMaxValue:1];
    [v addSubview:progress];

    /* click: switch between time remaining (pianobar's style) and elapsed */
    timeButton = [[[NSButton alloc] initWithFrame:NSMakeRect (x + w - 94, 92, 94, 18)] autorelease];
    [timeButton setBordered:NO];
    [timeButton setButtonType:NSMomentaryChangeButton];
    [timeButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [timeButton setAlignment:NSRightTextAlignment];
    [timeButton setTitle:@""];
    [timeButton setTarget:self];
    [timeButton setAction:@selector(toggleTimeDisplay:)];
    [v addSubview:timeButton];

    /* "Up next" bar: a quiet line above the buttons, with Next at its end */
    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect (x, 77, w, 1)] autorelease];
    [line setBoxType:NSBoxSeparator];
    [v addSubview:line];
    upNextLabel = PPBLabel (v, NSMakeRect (x, 54, w - 70, 16), [NSFont smallSystemFontSize], NO);
    [upNextLabel setTextColor:[NSColor grayColor]];
    nextButton  = PPBSmallButton (v, NSMakeRect (x + w - 62, 48, 66, 28), @"Next", self, @selector(next:));

    float bx = x - 4;
    playButton  = PPBSmallButton (v, NSMakeRect (bx, 12, 70, 28), @"Pause", self, @selector(playPause:)); bx += 76;
    loveButton  = PPBSmallButton (v, NSMakeRect (bx, 12, 70, 28), @"Love", self, @selector(love:)); bx += 76;
    banButton   = PPBSmallButton (v, NSMakeRect (bx, 12, 62, 28), @"Ban", self, @selector(ban:)); bx += 68;
    tiredButton = PPBSmallButton (v, NSMakeRect (bx, 12, 66, 28), @"Tired", self, @selector(tired:));

    if (![window setFrameUsingName:@"Player"]) [window center];
    [window setFrameAutosaveName:@"Player"];
}

- (void)buildLoginSheet {
    loginSheet = PPBSheetPanel (360, 180);
    NSView *v = [loginSheet contentView];
    [PPBLabel (v, NSMakeRect (18, 140, 324, 22), 13, YES) setStringValue:@"Sign in with your Pandora account"];
    [PPBLabel (v, NSMakeRect (18, 106, 80, 18), 12, NO) setStringValue:@"Email:"];
    emailField = [[[NSTextField alloc] initWithFrame:NSMakeRect (100, 104, 240, 22)] autorelease];
    [v addSubview:emailField];
    [PPBLabel (v, NSMakeRect (18, 74, 80, 18), 12, NO) setStringValue:@"Password:"];
    passwordField = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect (100, 72, 240, 22)] autorelease];
    [v addSubview:passwordField];
    [emailField setNextKeyView:passwordField];
    [passwordField setNextKeyView:emailField];
    loginStatus = PPBLabel (v, NSMakeRect (18, 44, 324, 18), [NSFont smallSystemFontSize], NO);
    [loginStatus setTextColor:[NSColor redColor]];
    NSButton *ok = PPBButton (v, NSMakeRect (250, 10, 96, 30), @"Sign In", self, @selector(signIn:));
    [ok setKeyEquivalent:@"\r"];
    PPBButton (v, NSMakeRect (154, 10, 96, 30), @"Quit", NSApp, @selector(terminate:));
}

- (void)buildInputSheet {
    inputSheet = PPBSheetPanel (360, 120);
    NSView *v = [inputSheet contentView];
    inputLabel = PPBLabel (v, NSMakeRect (18, 82, 324, 20), 13, YES);
    inputField = [[[NSTextField alloc] initWithFrame:NSMakeRect (20, 52, 320, 22)] autorelease];
    [v addSubview:inputField];
    NSButton *ok = PPBButton (v, NSMakeRect (250, 10, 96, 30), @"OK", self, @selector(inputOK:));
    [ok setKeyEquivalent:@"\r"];
    NSButton *cancel = PPBButton (v, NSMakeRect (154, 10, 96, 30), @"Cancel", self, @selector(inputCancel:));
    [cancel setKeyEquivalent:@"\033"];
}

/* --- state helpers --- */

/* Messages show for a few seconds in the up-next line, then it goes back to the
 * next song. With no song playing they stay. */
- (void)restoreUpNext {
    [upNextLabel setStringValue:upNextText ? upNextText : @""];
    [upNextLabel setTextColor:[NSColor grayColor]];
}

- (void)setStatus:(NSString *)s {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restoreUpNext) object:nil];
    if ([s length] == 0) {
        [self restoreUpNext];
        return;
    }
    [upNextLabel setStringValue:s];
    [upNextLabel setTextColor:[NSColor controlTextColor]];
    if (songLoaded) [self performSelector:@selector(restoreUpNext) withObject:nil afterDelay:5.0];
}

- (void)showTime {
    if (total <= 0) {
        [timeButton setTitle:@""];
        return;
    }
    BOOL showElapsed = [[NSUserDefaults standardUserDefaults] boolForKey:kElapsedKey];
    NSString *t;
    if (showElapsed)
        t = [NSString stringWithFormat:@"%@ / %@", clockText (elapsed), clockText (total)];
    else if (elapsed <= total)
        t = [NSString stringWithFormat:@"-%@ / %@", clockText (total - elapsed), clockText (total)];
    else
        t = [NSString stringWithFormat:@"+%@ / %@", clockText (elapsed - total), clockText (total)];
    [timeButton setTitle:t];
}

/* --- Dashboard widget --- */

/* nowplaying.json: what the widget shows. Written on every change and every 10 s
 * (the widget treats a file older than 30 s as "PowerBar isn't running"). */
- (void)writeNowPlaying:(BOOL)running {
    if (snapshotPath) return;
    NSString *dir = [PPBEngine defaultSupportDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir attributes:nil];
    NSString *json = [NSString stringWithFormat:
        @"{\"running\": %@, \"written\": %.3f, \"title\": %@, \"artist\": %@, \"album\": %@, "
        @"\"station\": %@, \"elapsed\": %d, \"total\": %d, \"paused\": %@, \"loved\": %@, "
        @"\"art\": %@, \"upnext\": %@}\n",
        running ? @"true" : @"false", [[NSDate date] timeIntervalSince1970],
        jsonString (songLoaded ? [titleLabel stringValue] : @""),
        jsonString (songLoaded ? [artistLabel stringValue] : @""),
        jsonString (songLoaded ? [albumLabel stringValue] : @""),
        jsonString (currentStation ? currentStation : @""),
        songLoaded ? elapsed : 0, songLoaded ? total : 0,
        paused ? @"true" : @"false", songLoaded && loved ? @"true" : @"false",
        jsonString (songLoaded && artFile ? artFile : @""),
        jsonString (upNextText ? upNextText : @"")];
    [json writeToFile:[dir stringByAppendingPathComponent:@"nowplaying.json"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    nowPlayingWritten = [NSDate timeIntervalSinceReferenceDate];
}

- (void)widgetCommand:(NSNotification *)n {
    NSString *c = [n object];
    if ([c isEqualToString:@"playpause"]) [self playPause:nil];
    else if ([c isEqualToString:@"next"]) [self next:nil];
    else if ([c isEqualToString:@"love"]) [self love:nil];
    else if ([c isEqualToString:@"ban"]) [self ban:nil];
    else if ([c isEqualToString:@"tired"]) [self tired:nil];
    else if ([c isEqualToString:@"show"]) {
        [NSApp activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:nil];
    }
}

/* --- updates (Sparkle 1.5-ppc, ../sparkle) --- */

/* The updater is created here or at the end of a normal launch, never in the test
 * modes, so Sparkle's "check automatically?" question can't appear mid-test. */
- (IBAction)checkForUpdates:(id)sender {
    [[SUUpdater sharedUpdater] checkForUpdates:sender];
}

/* Where Dashboard keeps the user's widgets ($PPB_WIDGETS_DIR for the tests). */
static NSString *widgetsDirectory (void) {
    const char *env = getenv ("PPB_WIDGETS_DIR");
    if (env != NULL && *env) return [NSString stringWithUTF8String:env];
    return [NSHomeDirectory () stringByAppendingPathComponent:@"Library/Widgets"];
}

/* An update replaces the app, but not the copy of the widget that Dashboard installed
 * in ~/Library/Widgets. The build stamps the widget with the app's build number, so at
 * launch an older installed widget is swapped for the one inside the app. A widget
 * that was never installed is left alone. */
- (void)refreshInstalledWidget {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *mine = [[NSBundle mainBundle] pathForResource:@"PowerBar" ofType:@"wdgt"];
    NSString *theirs = [widgetsDirectory () stringByAppendingPathComponent:@"PowerBar.wdgt"];
    NSString *tmp = [theirs stringByAppendingString:@".new"];
    int have, want;
    if (mine == nil || ![fm fileExistsAtPath:theirs]) return;
    have = [[[NSDictionary dictionaryWithContentsOfFile:[theirs stringByAppendingPathComponent:@"Info.plist"]]
             objectForKey:@"CFBundleVersion"] intValue];
    want = [[[NSDictionary dictionaryWithContentsOfFile:[mine stringByAppendingPathComponent:@"Info.plist"]]
             objectForKey:@"CFBundleVersion"] intValue];
    if (have >= want) return;
    [fm removeFileAtPath:tmp handler:nil];
    if (![fm copyPath:mine toPath:tmp handler:nil]) {
        NSLog (@"PowerBar: couldn't copy the Dashboard widget to %@", tmp);
        [fm removeFileAtPath:tmp handler:nil];
        return;
    }
    if (![fm removeFileAtPath:theirs handler:nil] || ![fm movePath:tmp toPath:theirs handler:nil])
        NSLog (@"PowerBar: couldn't replace the installed Dashboard widget at %@", theirs);
    else
        NSLog (@"PowerBar: updated the installed Dashboard widget (build %d -> %d)", have, want);
}

- (IBAction)installWidget:(id)sender {
    NSString *w = [[NSBundle mainBundle] pathForResource:@"PowerBar" ofType:@"wdgt"];
    if (w == nil || ![[NSWorkspace sharedWorkspace] openFile:w]) NSBeep ();
}

- (void)clearSong {
    songLoaded = NO;
    elapsed = total = 0;
    [titleLabel setStringValue:@""];
    [artistLabel setStringValue:@""];
    [albumLabel setStringValue:@""];
    [self showTime];
    [progress setDoubleValue:0];
    [art setImage:nil];
    [loveButton setTitle:@"Love"];
    [upNextText release];
    upNextText = nil;
    [self restoreUpNext];
    [upNextLabel setToolTip:nil];
    [window setTitle:@"PowerBar"];
}

/* songstart lists the queued songs as titleNext0, artistNext0, titleNext1... */
- (void)showUpNext:(NSDictionary *)info {
    NSMutableArray *queue = [NSMutableArray array];
    int i;
    for (i = 0; ; i++) {
        NSString *t = [info objectForKey:[NSString stringWithFormat:@"titleNext%d", i]];
        if (t == nil) break;
        NSString *a = [info objectForKey:[NSString stringWithFormat:@"artistNext%d", i]];
        [queue addObject:[NSString stringWithFormat:@"%@ %@ %@", t, U (DASH), a ? a : @""]];
    }
    [upNextText release];
    if ([queue count] == 0) {
        upNextText = [U ("Up next: a new batch from Pandora" ELLIPSIS) retain];
        [upNextLabel setToolTip:nil];
    } else {
        upNextText = [[@"Up next: " stringByAppendingString:[queue objectAtIndex:0]] retain];
        [upNextLabel setToolTip:[queue componentsJoinedByString:@"\n"]];
    }
    [self restoreUpNext];
}

- (BOOL)idle {
    return [engine isRunning] && [engine prompt] == nil;
}

- (void)updateControls {
    BOOL on = [engine isRunning];
    [playButton setTitle:paused ? @"Play" : @"Pause"];
    [playButton setEnabled:on && songLoaded];
    [nextButton setEnabled:on && songLoaded];
    [loveButton setEnabled:on && songLoaded];
    [banButton setEnabled:on && songLoaded];
    [tiredButton setEnabled:on && songLoaded];
    [stations setEnabled:on && [stationNames count] > 0];
    [actions setEnabled:on];
    [modeButton setEnabled:on && currentStation != nil];
}

- (Need)needFor:(SEL)a {
    if (a == @selector(explain:) || a == @selector(bookmark:) || a == @selector(newStationFromSong:))
        return NeedSong;
    if (a == @selector(addMusic:) || a == @selector(renameStation:) || a == @selector(deleteStation:) ||
        a == @selector(stationMode:) || a == @selector(stationSeeds:) || a == @selector(thumbs:))
        return NeedStation;
    return NeedEngine;
}

- (BOOL)isFeature:(SEL)a {
    return a == @selector(explain:) || a == @selector(bookmark:) || a == @selector(history:) ||
           a == @selector(newStation:) || a == @selector(newStationFromSong:) || a == @selector(genreStation:) ||
           a == @selector(sharedStation:) || a == @selector(addMusic:) || a == @selector(renameStation:) ||
           a == @selector(deleteStation:) || a == @selector(stationMode:) || a == @selector(stationSeeds:) ||
           a == @selector(thumbs:) || a == @selector(shuffle:) || a == @selector(explicitContent:);
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = [item action];
    if (a == @selector(setQuality:)) {
        NSString *q = [[NSUserDefaults standardUserDefaults] stringForKey:kQualityKey];
        [item setState:[[item representedObject] isEqualToString:q] ? NSOnState : NSOffState];
        return YES;
    }
    if ([self isFeature:a]) {
        /* a running feature with an open question must be finished first */
        if (![engine isRunning] || (flow != nil && [engine prompt] != nil)) return NO;
        Need n = [self needFor:a];
        return n == NeedEngine || (n == NeedSong ? songLoaded : currentStation != nil);
    }
    if (a == @selector(playPause:) || a == @selector(next:) || a == @selector(love:) ||
        a == @selector(ban:) || a == @selector(tired:))
        return [self idle] && songLoaded;
    if (a == @selector(signOut:)) return account != nil && !selftest;
    if (a == @selector(reconnect:)) return account != nil && ![engine isRunning];
    return YES;
}

- (void)showLoginWithMessage:(NSString *)msg {
    if (selftest) return;
    [emailField setStringValue:account ? account : @""];
    [passwordField setStringValue:@""];
    [loginStatus setStringValue:msg ? msg : @""];
    if (![loginSheet isVisible]) {
        [window makeKeyAndOrderFront:nil];
        [NSApp beginSheet:loginSheet modalForWindow:window modalDelegate:nil
           didEndSelector:NULL contextInfo:NULL];
    }
    [loginSheet makeFirstResponder:[account length] ? (id) passwordField : (id) emailField];
}

- (void)startEngineWithPassword:(NSString *)pw {
    if ([engine isRunning]) return;
    loginFailed = NO;
    [self setStatus:U ("Signing in" ELLIPSIS)];
    NSString *err = nil;
    NSString *quality = [[NSUserDefaults standardUserDefaults] stringForKey:kQualityKey];
    if (![engine startWithUser:account password:pw quality:quality error:&err]) {
        [self setStatus:err];
        if (selftest) { selftestResult (NO, err); exit (1); }
    }
    [self updateControls];
}

- (void)startEngine {
    NSString *pw = [PPBKeychain passwordForAccount:account];
    if (account == nil || pw == nil) {
        [self showLoginWithMessage:nil];
        return;
    }
    [self startEngineWithPassword:pw];
}

/* Send main-loop keys; refused while pianobar is asking something. */
- (BOOL)send:(NSString *)keys {
    if ([engine sendKeys:keys]) return YES;
    if ([engine prompt] != nil) {
        NSBeep ();
        [flow bringToFront];
        [self setStatus:@"Finish or cancel the open window first."];
    }
    return NO;
}

/* --- features --- */

/* Make room for a new feature: an open one that isn't waiting on a question is
 * simply closed. Returns NO if the user has to deal with the open one first. */
- (BOOL)clearFlow {
    if (flow == nil) return [self idle];
    if ([engine prompt] != nil) {
        NSBeep ();
        [flow bringToFront];
        return NO;
    }
    [flow cancel];
    return [self idle];
}

- (void)runFlow:(PPBFlow *)f {
    if (![self clearFlow]) return;
    [flow release];
    flow = [f retain];
    [flow start];
}

- (PPBScriptFlow *)scriptKey:(NSString *)k prompt:(NSString *)prefix answer:(NSString *)answer
                       asKey:(BOOL)asKey events:(NSArray *)events success:(NSString *)text {
    NSArray *a = [NSArray arrayWithObject:[NSArray arrayWithObjects:prefix, answer, asKey ? @"key" : @"line", nil]];
    return [[[PPBScriptFlow alloc] initWithHost:self key:k answers:a doneEvents:events success:text] autorelease];
}

- (IBAction)explain:(id)sender {
    [self runFlow:[[[PPBExplainFlow alloc] initWithHost:self] autorelease]];
}

- (IBAction)bookmark:(id)sender {
    if (![self clearFlow]) return;
    PPBChoiceSheet (window, @"Bookmark this song or its artist?", @"Bookmarks are saved to your Pandora account.",
                    [NSArray arrayWithObjects:@"Song", @"Artist", @"Cancel", nil], self, @selector(bookmarkChose:));
}

- (void)bookmarkChose:(NSNumber *)button {
    if ([button intValue] == 2) return;
    BOOL song = [button intValue] == 0;
    [self runFlow:[self scriptKey:@"b" prompt:@"Bookmark" answer:song ? @"s" : @"a" asKey:YES
                           events:[NSArray arrayWithObjects:@"songbookmark", @"artistbookmark", nil]
                          success:song ? @"Song bookmarked." : @"Artist bookmarked."]];
}

- (IBAction)newStationFromSong:(id)sender {
    if (![self clearFlow]) return;
    PPBChoiceSheet (window, @"New station from this song or its artist?",
                    [NSString stringWithFormat:@"\"%@\" by %@", [titleLabel stringValue], [artistLabel stringValue]],
                    [NSArray arrayWithObjects:@"Song", @"Artist", @"Cancel", nil], self, @selector(fromSongChose:));
}

- (void)fromSongChose:(NSNumber *)button {
    if ([button intValue] == 2) return;
    PPBScriptFlow *f = [self scriptKey:@"v" prompt:@"Create station from"
                                answer:[button intValue] == 0 ? @"s" : @"a" asKey:YES
                                events:[NSArray arrayWithObject:@"stationcreate"] success:@"Station created."];
    [f tuneToNewStation];
    [self runFlow:f];
}

- (IBAction)deleteStation:(id)sender {
    if (![self clearFlow]) return;
    NSAlert *a = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Really delete \"%@\"?", currentStation]
                                 defaultButton:@"Delete" alternateButton:@"Cancel" otherButton:nil
                     informativeTextWithFormat:@"The station is removed from your Pandora account. This can't be undone."];
    [a beginSheetModalForWindow:window modalDelegate:self
                 didEndSelector:@selector(deleteEnded:code:context:) contextInfo:NULL];
}

- (void)deleteEnded:(NSAlert *)a code:(int)code context:(void *)ctx {
    if (code != NSAlertDefaultReturn) return;
    [self runFlow:[self scriptKey:@"d" prompt:@"Really delete" answer:@"y" asKey:YES
                           events:[NSArray arrayWithObject:@"stationdelete"]
                          success:@"Station deleted. Choose another."]];
}

- (void)askForText:(NSString *)label initial:(NSString *)initial then:(SEL)done {
    if (![self clearFlow]) return;
    inputDone = done;
    [inputLabel setStringValue:label];
    [inputField setStringValue:initial ? initial : @""];
    [NSApp beginSheet:inputSheet modalForWindow:window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    [inputSheet makeFirstResponder:inputField];
}

- (IBAction)inputOK:(id)sender {
    NSString *text = [[inputField stringValue] stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0) { NSBeep (); return; }
    [NSApp endSheet:inputSheet];
    [inputSheet orderOut:nil];
    [self performSelector:inputDone withObject:text];
}

- (IBAction)inputCancel:(id)sender {
    [NSApp endSheet:inputSheet];
    [inputSheet orderOut:nil];
}

- (IBAction)renameStation:(id)sender {
    [self askForText:@"New name for this station:" initial:currentStation then:@selector(renameWith:)];
}

- (void)renameWith:(NSString *)name {
    [self runFlow:[self scriptKey:@"r" prompt:@"New name" answer:name asKey:NO
                           events:[NSArray arrayWithObject:@"stationrename"] success:@"Station renamed."]];
}

- (IBAction)sharedStation:(id)sender {
    [self askForText:@"Shared station ID (the number in its link):" initial:nil then:@selector(sharedWith:)];
}

- (void)sharedWith:(NSString *)stationId {
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([stationId rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        [self setStatus:@"A station ID is all digits."];
        return;
    }
    [self runFlow:[self scriptKey:@"j" prompt:@"Station id" answer:stationId asKey:NO
                           events:[NSArray arrayWithObject:@"stationaddshared"] success:@"Shared station added."]];
}

- (IBAction)newStation:(id)sender {
    [self runFlow:[[[PPBSearchFlow alloc] initWithHost:self addMusic:NO] autorelease]];
}

- (IBAction)addMusic:(id)sender {
    [self runFlow:[[[PPBSearchFlow alloc] initWithHost:self addMusic:YES] autorelease]];
}

- (IBAction)stationMode:(id)sender {
    [self runFlow:[[[PPBModeFlow alloc] initWithHost:self] autorelease]];
}

- (IBAction)stationSeeds:(id)sender {
    [self runFlow:[[[PPBStationInfoFlow alloc] initWithHost:self feedback:NO] autorelease]];
}

- (IBAction)thumbs:(id)sender {
    [self runFlow:[[[PPBStationInfoFlow alloc] initWithHost:self feedback:YES] autorelease]];
}

- (IBAction)shuffle:(id)sender {
    [self runFlow:[[[PPBShuffleFlow alloc] initWithHost:self] autorelease]];
}

- (void)panelFlow:(NSString *)k title:(NSString *)t {
    [self runFlow:[[[PPBPanelFlow alloc] initWithHost:self panel:actionPanel key:k title:t] autorelease]];
}

- (IBAction)history:(id)sender         { [self panelFlow:@"h" title:@"History"]; }
- (IBAction)genreStation:(id)sender    { [self panelFlow:@"g" title:@"Add Genre Station"]; }
- (IBAction)explicitContent:(id)sender {
    [self runFlow:[[[PPBExplicitFlow alloc] initWithHost:self] autorelease]];
}

/* --- flow host --- */

- (PPBEngine *)engine { return engine; }
- (NSWindow *)playerWindow { return window; }
- (NSString *)currentStationName { return currentStation; }
- (NSArray *)stationNameList { return stationNames; }

- (void)flowFinished:(PPBFlow *)f {
    if (f != flow) return;
    /* anything pianobar still asks for the finished flow gets backed out of,
     * until its main loop shows up again */
    drainPrompts = YES;
    [flow autorelease];
    flow = nil;
}

- (void)tuneToStationNamed:(NSString *)name {
    if (![stationNames containsObject:name]) return;
    paused = NO;
    [stations selectItemAtIndex:[stationNames indexOfObject:name]];
    [engine selectStationAtIndex:[stationNames indexOfObject:name]];
}

/* --- app delegate --- */

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildMenus];
    [self buildWindow];
    [self buildLoginSheet];
    [self buildInputSheet];
    [self clearSong];
    engine = [[PPBEngine alloc] initWithDelegate:self
                                supportDirectory:[PPBEngine defaultSupportDirectory]];
    actionPanel = [[PPBActionPanel alloc] initWithDelegate:nil];
    /* the Dashboard widget's buttons (powerbar-ctl), also while we're in the background */
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(widgetCommand:)
        name:@"io.github.cmstuberg.PowerBar.command" object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [self updateControls];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (!selftest && snapshotPath == nil) [self refreshInstalledWidget];

    if (snapshotPath) {
        [self performSelector:@selector(snapshot) withObject:nil afterDelay:0.5];
        return;
    }
    if ([self uiTestRequested]) {
        [self performSelector:@selector(runUITest) withObject:nil afterDelay:0.3];
        return;
    }
    if (selftest) {
        account = [@"nobody@example.invalid" retain];
        [self startEngineWithPassword:@"not-a-real-password"];
        [self performSelector:@selector(selftestTimeout) withObject:nil afterDelay:90];
        return;
    }
    account = [[[NSUserDefaults standardUserDefaults] stringForKey:kAccountKey] copy];
    [self startEngine];
    /* scheduled update checks; Sparkle asks on the second launch whether to check */
    [SUUpdater sharedUpdater];
}

- (void)selftestTimeout {
    selftestResult (NO, @"no login answer within 90 s");
    exit (1);
}

- (BOOL)writeSnapshotOf:(NSView *)v to:(NSString *)path {
    [v display];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    BOOL ok = [png writeToFile:path atomically:YES];
    printf ("snapshot: %s %s\n", ok ? "wrote" : "FAILED", [path UTF8String]);
    fflush (stdout);
    return ok;
}

/* Fill the window with sample data and save a PNG (docs, layout checks). Draws
 * offscreen, so it works in a background login session. */
- (void)snapshot {
    [self engine:nil event:@"usergetstations" info:[NSDictionary dictionaryWithObjectsAndKeys:
        @"3", @"stationCount", @"Miles Davis Radio", @"station0",
        @"QuickMix", @"station1", @"Today's Hits Radio", @"station2", nil]];
    songLoaded = YES;
    [currentStation release];
    currentStation = [@"Miles Davis Radio" retain];
    [titleLabel setStringValue:@"So What"];
    [artistLabel setStringValue:@"Miles Davis"];
    [albumLabel setStringValue:@"Kind of Blue (Legacy Edition)"];
    [stations selectItemAtIndex:0];
    [art setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    [progress setMaxValue:562];
    [self engine:nil elapsed:154 total:562];
    [self setStatus:@"Loved. Pandora will play more like it."];
    [loveButton setTitle:@"Loved"];
    [self showUpNext:[NSDictionary dictionaryWithObjectsAndKeys:
        @"Blue in Green", @"titleNext0", @"Miles Davis", @"artistNext0", nil]];
    NSArray *b = [NSArray arrayWithObjects:playButton, nextButton, loveButton, banButton, tiredButton,
                  stations, actions, modeButton, nil];
    unsigned i;
    for (i = 0; i < [b count]; i++) [[b objectAtIndex:i] setEnabled:YES];
    exit ([self writeSnapshotOf:[window contentView] to:snapshotPath] ? 0 : 1);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    quitting = YES;
    [engine stop];
    songLoaded = NO;
    [self writeNowPlaying:NO];
    return NSTerminateNow;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag {
    [window makeKeyAndOrderFront:nil];
    return NO;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)app {
    NSMenu *m = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    if (songLoaded) {
        NSString *now = [NSString stringWithFormat:@"%@ %@ %@", [titleLabel stringValue], U (DASH), [artistLabel stringValue]];
        [m addItemWithTitle:now action:NULL keyEquivalent:@""];
        [m addItem:[NSMenuItem separatorItem]];
    }
    addItem (m, paused ? @"Play" : @"Pause", @selector(playPause:), @"", self);
    addItem (m, @"Next Song", @selector(next:), @"", self);
    addItem (m, @"Love Song", @selector(love:), @"", self);
    addItem (m, @"Ban Song", @selector(ban:), @"", self);
    addItem (m, @"Tired of Song", @selector(tired:), @"", self);
    return m;
}

/* --- transport --- */

- (IBAction)playPause:(id)sender {
    if (!songLoaded || ![self send:paused ? @"P" : @"S"]) return;
    paused = !paused;
    [self setStatus:paused ? @"Paused." : @""];
    [self updateControls];
    [self writeNowPlaying:YES];
}
- (IBAction)next:(id)sender {
    if (songLoaded && [self send:@"n"]) [self setStatus:U ("Skipping" ELLIPSIS)];
}
- (IBAction)love:(id)sender  { if (songLoaded) [self send:@"+"]; }
- (IBAction)ban:(id)sender   { if (songLoaded) [self send:@"-"]; }
- (IBAction)tired:(id)sender { if (songLoaded) [self send:@"t"]; }

- (IBAction)toggleTimeDisplay:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:kElapsedKey] forKey:kElapsedKey];
    [self showTime];
}

- (IBAction)stationChosen:(id)sender {
    int i = [stations indexOfSelectedItem];
    if (i < 0 || i >= (int) [stationNames count]) return;
    NSString *p = [engine prompt];
    if (p != nil && ![p hasPrefix:@"Select station"]) {
        NSBeep ();
        [flow bringToFront];
        [self setStatus:@"Finish or cancel the open window first."];
        return;
    }
    [self setStatus:[NSString stringWithFormat:@"Tuning to %@%@", [stationNames objectAtIndex:i], U (ELLIPSIS)]];
    paused = NO;
    [engine selectStationAtIndex:i];
}

- (IBAction)setQuality:(id)sender {
    NSString *q = [sender representedObject];
    [[NSUserDefaults standardUserDefaults] setObject:q forKey:kQualityKey];
    if ([engine isRunning]) {
        /* pianobar reads the quality at startup */
        [self setStatus:[NSString stringWithFormat:@"Audio quality: %@. Reconnecting%@", q, U (ELLIPSIS)]];
        restarts = 0;
        [flow cancel];
        [engine stop];   /* engineDidExit restarts it */
    }
}

- (IBAction)reconnect:(id)sender {
    restarts = 0;
    [self startEngine];
}

- (IBAction)signIn:(id)sender {
    NSString *email = [[emailField stringValue] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pw = [passwordField stringValue];
    if ([email length] == 0 || [pw length] == 0) {
        [loginStatus setStringValue:@"Enter your email address and password."];
        return;
    }
    [account release];
    account = [email copy];
    [[NSUserDefaults standardUserDefaults] setObject:account forKey:kAccountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (![PPBKeychain setPassword:pw forAccount:account])
        NSLog (@"PowerBar: couldn't save the password in the keychain");
    [NSApp endSheet:loginSheet];
    [loginSheet orderOut:nil];
    [passwordField setStringValue:@""];
    restarts = 0;
    [self startEngineWithPassword:pw];
}

- (IBAction)signOut:(id)sender {
    quitting = YES;          /* not a crash: don't auto-restart */
    [flow cancel];
    [engine stop];
    quitting = NO;
    [PPBKeychain removePasswordForAccount:account];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kAccountKey];
    [self clearSong];
    [currentStation release]; currentStation = nil;
    [stationNames release]; stationNames = nil;
    [stations removeAllItems];
    [stations addItemWithTitle:@"No stations yet"];
    [self setStatus:@"Signed out."];
    [self updateControls];
    [self showLoginWithMessage:nil];
}

- (IBAction)showPlayer:(id)sender {
    [window makeKeyAndOrderFront:nil];
}

- (IBAction)about:(id)sender {
    NSString *credits =
        @"A Mac OS X 10.4+ PowerPC front end for pianobar.\n\n"
        @"Built on pianobar (MIT), ffmpeg (LGPL 2.1+), OpenSSL (Apache 2.0), curl, "
        @"zlib and json-c (MIT). Licences are in the app's Resources/Licenses folder.\n\n"
        @"Not affiliated with or endorsed by Pandora Media. Pandora is a trademark "
        @"of Pandora Media, LLC.";
    NSAttributedString *a = [[[NSAttributedString alloc] initWithString:credits attributes:
        [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]
                                    forKey:NSFontAttributeName]] autorelease];
    [NSApp orderFrontStandardAboutPanelWithOptions:
        [NSDictionary dictionaryWithObject:a forKey:@"Credits"]];
}

/* --- engine delegate --- */

- (NSString *)errorText:(NSDictionary *)info {
    if ([[info objectForKey:@"wRet"] intValue] != 0) return [info objectForKey:@"wRetStr"];
    if ([info objectForKey:@"pRet"] && [[info objectForKey:@"pRet"] intValue] != PIANO_RET_OK)
        return [info objectForKey:@"pRetStr"];
    return nil;
}

- (void)artArrived:(NSArray *)result {
    if (![[result objectAtIndex:0] isEqualToString:artURL]) return;   /* stale */
    id data = [result objectAtIndex:1];
    if (data == [NSNull null]) return;
    NSImage *img = [[[NSImage alloc] initWithData:data] autorelease];
    if (img) [art setImage:img];
    /* a copy for the widget, under a new name each time so it never shows a stale one */
    NSString *dir = [PPBEngine defaultSupportDirectory];
    NSString *name = [NSString stringWithFormat:@"cover-%d", ++artSerial % 2];
    if (img && [data writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES]) {
        [artFile release];
        artFile = [name copy];
        [self writeNowPlaying:YES];
    }
}

/* Every event carries the station list; keep the menu in step with it (stations
 * get created, renamed and deleted from the feature windows). */
- (void)updateStations:(NSDictionary *)info {
    NSString *countStr = [info objectForKey:@"stationCount"];
    if (countStr == nil) return;
    int n = [countStr intValue], i;
    if (n == 0 && [stationNames count] == 0) return;
    NSMutableArray *names = [NSMutableArray array];
    for (i = 0; i < n; i++) {
        NSString *s = [info objectForKey:[NSString stringWithFormat:@"station%d", i]];
        [names addObject:s ? s : @"?"];
    }
    if ([names isEqualToArray:stationNames]) return;
    [stationNames release];
    stationNames = [names retain];
    [stations removeAllItems];
    for (i = 0; i < n; i++) {
        /* addItemWithTitle: drops duplicate titles; add, then set the title */
        [stations addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
        [[stations lastItem] setTitle:[names objectAtIndex:i]];
    }
    if (n == 0) [stations addItemWithTitle:@"No stations"];
    if (currentStation && [names containsObject:currentStation])
        [stations selectItemAtIndex:[names indexOfObject:currentStation]];
    [self updateControls];
}

- (void)engine:(PPBEngine *)e event:(NSString *)type info:(NSDictionary *)info {
    NSString *err = [self errorText:info];
    [self updateStations:info];
    NSString *st = [info objectForKey:@"stationName"];
    if ([st length] && ![type isEqualToString:@"stationdelete"] && ![st isEqualToString:currentStation]) {
        [currentStation release];
        currentStation = [st copy];
        if ([stationNames containsObject:st]) [stations selectItemAtIndex:[stationNames indexOfObject:st]];
        [self updateControls];
    }

    if ([type isEqualToString:@"userlogin"]) {
        if (selftest) {
            BOOL pass = err != nil && [[info objectForKey:@"wRet"] intValue] == 0 &&
                        [err rangeOfString:@"password"].location != NSNotFound;
            selftestResult (pass, [NSString stringWithFormat:@"login answer \"%@\" (pRet=%@ wRet=%@)",
                                   err, [info objectForKey:@"pRet"], [info objectForKey:@"wRet"]]);
            exit (pass ? 0 : 1);
        }
        if (err) {
            loginFailed = YES;
            [self setStatus:err];
            [self showLoginWithMessage:err];
        } else {
            restarts = 0;
            [self setStatus:U ("Signed in. Loading stations" ELLIPSIS)];
        }
    } else if ([type isEqualToString:@"songstart"]) {
        songLoaded = YES;
        paused = NO;
        [titleLabel setStringValue:[info objectForKey:@"title"] ? [info objectForKey:@"title"] : @""];
        [artistLabel setStringValue:[info objectForKey:@"artist"] ? [info objectForKey:@"artist"] : @""];
        [albumLabel setStringValue:[info objectForKey:@"album"] ? [info objectForKey:@"album"] : @""];
        loved = [[info objectForKey:@"rating"] intValue] == 1;
        [loveButton setTitle:loved ? @"Loved" : @"Love"];
        elapsed = 0;
        total = [[info objectForKey:@"songDuration"] intValue];
        [progress setMaxValue:total > 0 ? total : 1];
        [progress setDoubleValue:0];
        [self showTime];
        [window setTitle:[NSString stringWithFormat:@"%@ %@ %@",
                          [titleLabel stringValue], U (DASH), [artistLabel stringValue]]];
        NSString *st = [info objectForKey:@"stationName"];
        if ([st length]) {
            [currentStation release];
            currentStation = [st copy];
            if ([stationNames containsObject:st])
                [stations selectItemAtIndex:[stationNames indexOfObject:st]];
        }
        [self showUpNext:info];
        [art setImage:nil];
        [artURL release];
        artURL = [[info objectForKey:@"coverArt"] copy];
        if ([artURL length]) [PPBFetch fetchURL:artURL target:self selector:@selector(artArrived:)];
        [artFile release];
        artFile = nil;
        [self writeNowPlaying:YES];
        if (flow == nil) [self setStatus:err];
        [self updateControls];
    } else if ([type isEqualToString:@"songlove"]) {
        if (!err) {
            loved = YES;
            [loveButton setTitle:@"Loved"];
            [self writeNowPlaying:YES];
        }
        [self setStatus:err ? err : @"Loved. Pandora will play more like it."];
    } else if ([type isEqualToString:@"songban"]) {
        [self setStatus:err ? err : @"Banned. It won't play on this station again."];
    } else if ([type isEqualToString:@"songshelf"]) {
        [self setStatus:err ? err : @"Shelved for a month."];
    } else if ([type isEqualToString:@"stationdelete"] && !err) {
        [currentStation release];
        currentStation = nil;
        [self clearSong];
        [self updateControls];
    } else if (err && flow == nil) {
        [self setStatus:err];
    }
    [flow event:type info:info];
}

- (void)engine:(PPBEngine *)e elapsed:(int)el total:(int)tot {
    drainPrompts = NO;            /* pianobar's main loop is running */
    elapsed = el;
    if (tot > 0) total = tot;
    if (total > 0 && [progress maxValue] != total) [progress setMaxValue:total];
    [progress setDoubleValue:elapsed];
    [self showTime];
    if ([NSDate timeIntervalSinceReferenceDate] - nowPlayingWritten >= 10) [self writeNowPlaying:YES];
    [flow mainLoop];
}

- (void)engine:(PPBEngine *)e prompt:(NSString *)prompt {
    if (flow != nil) {
        [flow prompt:prompt];
    } else if (drainPrompts) {
        [engine cancelPrompt];
    } else if ([prompt hasPrefix:@"Select station"]) {
        /* startup without a remembered station, or after one was deleted */
        [self setStatus:@"Choose a station."];
        [window makeKeyAndOrderFront:nil];
    } else {
        /* nothing of ours asked this; back out rather than leave pianobar waiting */
        [engine cancelPrompt];
    }
}

- (void)engine:(PPBEngine *)e listItem:(NSString *)item {
    [flow listItem:item];         /* the startup station list goes nowhere */
}

- (void)engine:(PPBEngine *)e message:(NSString *)text kind:(PPBMessageKind)kind {
    if (flow != nil) {
        [flow message:text kind:kind];
        return;
    }
    if (kind != PPBMessageError) return;
    if ([text rangeOfString:@"quality is not available"].location != NSNotFound &&
        ![[[NSUserDefaults standardUserDefaults] stringForKey:kQualityKey] isEqualToString:@"medium"]) {
        /* e.g. "high" on an account that doesn't offer it */
        [[NSUserDefaults standardUserDefaults] setObject:@"medium" forKey:kQualityKey];
        [self setStatus:@"High quality isn't available on this account; using medium."];
        [engine stop];
        return;
    }
    [self setStatus:text];
}

- (void)engineDidExit:(PPBEngine *)e status:(int)status {
    songLoaded = NO;
    [self writeNowPlaying:YES];
    [flow cancel];
    [actionPanel close];
    [self updateControls];
    if (selftest) {
        selftestResult (NO, [NSString stringWithFormat:@"engine exited (%d) before answering", status]);
        exit (1);
    }
    if (quitting || loginFailed || account == nil) return;
    songLoaded = NO;
    if (restarts < 3) {
        restarts++;
        [self setStatus:U ("Reconnecting" ELLIPSIS)];
        [self performSelector:@selector(startEngine) withObject:nil afterDelay:restarts == 1 ? 0.5 : 5.0];
    } else {
        [self setStatus:@"The connection keeps dropping. Use Controls > Reconnect."];
    }
}

@end
