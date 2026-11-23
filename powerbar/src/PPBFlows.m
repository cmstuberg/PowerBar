#import "PPBFlows.h"
#import "PPBUI.h"

#define PIANO_RET_OK 1

@interface PPBShuffleFlow (Layout)
- (void)layout;
@end

static NSString *eventError (NSDictionary *info) {
    if ([[info objectForKey:@"wRet"] intValue] != 0) return [info objectForKey:@"wRetStr"];
    if ([info objectForKey:@"pRet"] && [[info objectForKey:@"pRet"] intValue] != PIANO_RET_OK)
        return [info objectForKey:@"pRetStr"];
    return nil;
}

/* The one-key options in a pianobar question: "Delete [a]rtist/[s]ong seeds?" -> "as" */
static NSString *bracketKeys (NSString *q) {
    NSMutableString *keys = [NSMutableString string];
    unsigned i, n = [q length];
    for (i = 0; i + 2 < n; i++)
        if ([q characterAtIndex:i] == '[' && [q characterAtIndex:i + 2] == ']')
            [keys appendFormat:@"%C", [q characterAtIndex:i + 1]];
    return keys;
}

/* Station lists carry three flag columns before the name: "qQS Name". */
static NSString *stripStationFlags (NSString *t) {
    if ([t length] > 4 && [t characterAtIndex:3] == ' ') {
        NSString *f = [t substringToIndex:3];
        if ([[f stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" qQS"]] length] == 0)
            return [t substringFromIndex:4];
    }
    return t;
}

/* Put a new flow window just inside the player window's top-left corner. */
static void placeNear (NSWindow *panel, NSWindow *main) {
    NSRect wf = [main frame];
    [panel setFrameTopLeftPoint:NSMakePoint (NSMinX (wf) + 30, NSMaxY (wf) - 40)];
}

/* ======================================================================== */

@implementation PPBFlow

- (id)initWithHost:(id)aHost {
    if ((self = [super init])) {
        host = aHost;
        engine = [aHost engine];
    }
    return self;
}

- (void)start {}
- (BOOL)isDone { return done; }
- (void)bringToFront {}
- (void)closeUI {}

- (void)finish {
    if (done) return;
    done = YES;
    [self closeUI];
    [host flowFinished:self];
}

- (void)cancel {
    if ([engine prompt] != nil) [engine cancelPrompt];
    [self finish];
}

- (BOOL)sendKey:(NSString *)k {
    if (![engine sendKeys:k]) {
        NSBeep ();
        [self finish];
        return NO;
    }
    return YES;
}

- (void)prompt:(NSString *)p {
    /* a question this flow doesn't know: back out */
    outputSeen = YES;
    [engine cancelPrompt];
}

- (void)listItem:(NSString *)item { outputSeen = YES; }

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if (k == PPBMessageError) [host setStatus:t];
}

- (void)event:(NSString *)type info:(NSDictionary *)info { outputSeen = YES; }

- (void)mainLoop {
    if (outputSeen && [engine prompt] == nil) [self finish];
}

/* window delegate: the close box backs out */
- (BOOL)windowShouldClose:(id)sender {
    [self cancel];
    return YES;
}

- (IBAction)cancelAction:(id)sender {
    [self cancel];
}

@end

/* ======================================================================== */

@implementation PPBScriptFlow

- (id)initWithHost:(id)aHost key:(NSString *)k answers:(NSArray *)a
        doneEvents:(NSArray *)events success:(NSString *)text {
    if ((self = [super initWithHost:aHost])) {
        key = [k copy];
        answers = [a retain];
        doneEvents = [events retain];
        success = [text copy];
    }
    return self;
}

- (void)dealloc {
    [key release]; [answers release]; [doneEvents release]; [success release];
    [stationsBefore release];
    [super dealloc];
}

- (void)tuneToNewStation {
    [stationsBefore release];
    stationsBefore = [[host stationNameList] copy];
}

- (void)start {
    [self sendKey:key];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if (next < [answers count]) {
        NSArray *a = [answers objectAtIndex:next];
        if ([p hasPrefix:[a objectAtIndex:0]]) {
            next++;
            if ([[a objectAtIndex:2] isEqualToString:@"key"]) [engine answerKey:[a objectAtIndex:1]];
            else [engine answerLine:[a objectAtIndex:1]];
            return;
        }
    }
    [engine cancelPrompt];
}

- (void)event:(NSString *)type info:(NSDictionary *)info {
    outputSeen = YES;
    if (![doneEvents containsObject:type]) return;
    NSString *err = eventError (info);
    [host setStatus:err ? err : success];
    if (!err && stationsBefore) {
        NSArray *now = [host stationNameList];
        unsigned i;
        for (i = 0; i < [now count]; i++)
            if (![stationsBefore containsObject:[now objectAtIndex:i]]) {
                [host setStatus:[NSString stringWithFormat:@"Created \"%@\".", [now objectAtIndex:i]]];
                [host tuneToStationNamed:[now objectAtIndex:i]];
                break;
            }
    }
    [self finish];
}

@end

/* ======================================================================== */

#define EW 400.0

@implementation PPBExplainFlow

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [super dealloc];
}

- (void)layout {
    PPBStack (panel, EW, [NSArray arrayWithObjects:text, buttons, nil],
              [NSArray arrayWithObjects:PPBH (PPBFitHeight (text, EW - 28)), PPBH (32), nil]);
}

- (void)start {
    panel = PPBPanel (EW, 100, @"Why Is This Song Playing?", self);
    NSView *v = [panel contentView];
    text = PPBWrappingLabel (v, NSMakeRect (0, 0, EW - 28, 18), 13);
    [text setSelectable:YES];
    [text setStringValue:U ("Asking Pandora" ELLIPSIS)];
    NSButton *b = PPBButton (v, NSZeroRect, @"Close", self, @selector(cancelAction:));
    buttons = PPBButtonRow (EW - 28, [NSArray arrayWithObject:b], NO);
    [b setKeyEquivalent:@"\r"];
    [v addSubview:buttons];
    [self layout];
    placeNear (panel, [host playerWindow]);
    [panel makeKeyAndOrderFront:nil];
    [self sendKey:@"e"];
}

- (void)bringToFront { [panel makeKeyAndOrderFront:nil]; }
- (void)closeUI { [panel orderOut:nil]; }

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if (k == PPBMessageError || !PPBIsProgress (t)) {
        [text setStringValue:t];
        [self layout];
    }
}

/* stays open to be read; Close (or another feature) ends it */
- (void)mainLoop {}

@end

/* ======================================================================== */

enum { SIdle, SWaitPrompt, SSearching, SChoosing, SCommitting };

@implementation PPBSearchFlow

- (id)initWithHost:(id)aHost addMusic:(BOOL)flag {
    if ((self = [super initWithHost:aHost])) {
        addMusic = flag;
        rows = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [rows release];
    [stationsBefore release];
    [super dealloc];
}

- (void)start {
    stationsBefore = [[host stationNameList] copy];
    NSString *title = addMusic
        ? [NSString stringWithFormat:@"Add Music to %@", [host currentStationName] ? [host currentStationName] : @"Station"]
        : @"New Station";
    panel = PPBPanel (420, 360, title, self);
    NSView *v = [panel contentView];
    [PPBLabel (v, NSMakeRect (12, 326, 396, 18), 12, NO) setStringValue:addMusic
        ? @"Find an artist or song to add to this station:"
        : @"Find an artist or song to start a station from:"];
    query = [[[NSTextField alloc] initWithFrame:NSMakeRect (14, 296, 296, 22)] autorelease];
    [query setTarget:self];
    [query setAction:@selector(search:)];
    [v addSubview:query];
    PPBButton (v, NSMakeRect (314, 292, 96, 30), @"Search", self, @selector(search:));

    scope = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (12, 258, 110, 26) pullsDown:NO] autorelease];
    [scope addItemWithTitle:@"Artists"];
    [scope addItemWithTitle:@"Songs"];
    [scope setTarget:self];
    [scope setAction:@selector(scopeChanged:)];
    [scope setHidden:YES];
    [v addSubview:scope];
    info = PPBLabel (v, NSMakeRect (130, 262, 278, 18), 11, NO);
    [info setTextColor:[NSColor grayColor]];

    table = PPBTable (v, NSMakeRect (14, 54, 392, 198), self, self, @selector(commit:));
    NSButton *cancel = PPBButton (v, NSMakeRect (214, 12, 96, 30), @"Cancel", self, @selector(cancelAction:));
    [cancel setKeyEquivalent:@"\033"];
    commit = PPBButton (v, NSMakeRect (314, 12, 96, 30), addMusic ? @"Add" : @"Create", self, @selector(commit:));
    [commit setEnabled:NO];
    placeNear (panel, [host playerWindow]);
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:query];
    state = SIdle;
}

- (void)bringToFront { [panel makeKeyAndOrderFront:nil]; }
- (void)closeUI { [panel orderOut:nil]; }

- (void)showRows {
    [table reloadData];
    [commit setEnabled:state == SChoosing && [rows count] > 0];
}

- (void)runSearch {
    if ([engine prompt] != nil) [engine cancelPrompt];
    [rows removeAllObjects];
    [self showRows];
    [info setStringValue:U ("Searching" ELLIPSIS)];
    outputSeen = NO;
    state = SWaitPrompt;
    if (![engine sendKeys:addMusic ? @"a" : @"c"]) {
        [info setStringValue:@"Pandora is busy; try again."];
        state = SIdle;
    }
}

- (IBAction)search:(id)sender {
    if ([[query stringValue] length] == 0) { NSBeep (); return; }
    [scope setHidden:YES];
    [scope selectItemAtIndex:0];
    [self runSearch];
}

- (IBAction)scopeChanged:(id)sender {
    if ([[query stringValue] length]) [self runSearch];
}

- (IBAction)commit:(id)sender {
    int r = [table selectedRow];
    if (state != SChoosing || r < 0 || r >= (int) [rows count]) { NSBeep (); return; }
    state = SCommitting;
    [commit setEnabled:NO];
    [info setStringValue:addMusic ? U ("Adding" ELLIPSIS) : U ("Creating the station" ELLIPSIS)];
    [engine answerLine:[[[rows objectAtIndex:r] objectAtIndex:0] stringValue]];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if ([p hasPrefix:@"Create station from"] || [p hasPrefix:@"Add artist or title"]) {
        state = SSearching;
        [engine answerLine:[query stringValue]];
    } else if ([p hasPrefix:@"Is this an [a]rtist"]) {
        /* both kinds matched: let the user switch between them */
        [scope setHidden:NO];
        [engine answerKey:[scope indexOfSelectedItem] == 0 ? @"a" : @"t"];
    } else if ([p hasPrefix:@"Select artist"] || [p hasPrefix:@"Select song"]) {
        if (state == SCommitting) { [engine cancelPrompt]; return; }
        state = SChoosing;
        [info setStringValue:[NSString stringWithFormat:@"Pick one, then click %@.", [commit title]]];
        [self showRows];
        if ([rows count]) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    } else {
        [engine cancelPrompt];
    }
}

- (void)listItem:(NSString *)item {
    outputSeen = YES;
    int i; NSString *t;
    if (PPBParseListItem (item, &i, &t))
        [rows addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:i], t, nil]];
}

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if ([t hasPrefix:@"Nothing found"]) {
        [info setStringValue:@"No matches. Try another search."];
        state = SIdle;
    } else if (k == PPBMessageError) {
        [info setStringValue:t];
    }
}

- (void)event:(NSString *)type info:(NSDictionary *)ev {
    outputSeen = YES;
    if (![type isEqualToString:addMusic ? @"stationaddmusic" : @"stationcreate"]) return;
    NSString *err = eventError (ev);
    if (err) {
        [info setStringValue:err];
        state = SIdle;
        return;
    }
    if (addMusic) {
        [host setStatus:@"Added. The station will start including it."];
    } else {
        /* tune to the station that wasn't there before */
        NSArray *now = [host stationNameList];
        unsigned i;
        for (i = 0; i < [now count]; i++) {
            NSString *n = [now objectAtIndex:i];
            if (![stationsBefore containsObject:n]) {
                [host setStatus:[NSString stringWithFormat:@"Created \"%@\".", n]];
                [host tuneToStationNamed:n];
                break;
            }
        }
    }
    [self finish];
}

/* search results stay open for picking; only Cancel/Create end this flow */
- (void)mainLoop {
    if (state == SSearching || state == SWaitPrompt) {
        if (outputSeen && [engine prompt] == nil) state = SIdle;
    }
}

- (int)numberOfRowsInTableView:(NSTableView *)tv { return [rows count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(int)r {
    return [[rows objectAtIndex:r] objectAtIndex:1];
}

@end

/* ======================================================================== */

enum { QProbe, QNoShuffle, QNeedSwitch, QSwitching, QLoading, QEditing, QSaving };
#define QW 360.0

@implementation PPBShuffleFlow

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [rows release];
    [toggles release];
    [shuffleName release];
    [super dealloc];
}

- (NSArray *)mixRows {
    NSMutableArray *a = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < [rows count]; i++)
        if (![[[rows objectAtIndex:i] objectForKey:@"isShuffle"] boolValue]) [a addObject:[rows objectAtIndex:i]];
    return a;
}

- (void)setInfo:(NSString *)s {
    [info setStringValue:s];
    [self layout];
}

- (void)layout {
    BOOL editing = state == QEditing || state == QSaving;
    [[table enclosingScrollView] setHidden:!editing];
    [table reloadData];
    PPBStack (panel, QW, [NSArray arrayWithObjects:info, [table enclosingScrollView], buttons, nil],
              [NSArray arrayWithObjects:PPBH (PPBFitHeight (info, QW - 28)),
               PPBH (PPBTableHeight (table, [[self mixRows] count], 3, 14)), PPBH (32), nil]);
}

- (void)start {
    rows = [[NSMutableArray alloc] init];
    panel = PPBPanel (QW, 100, @"Shuffle", self);
    NSView *v = [panel contentView];
    info = PPBWrappingLabel (v, NSMakeRect (0, 0, QW - 28, 18), 12);

    NSScrollView *s = [[[NSScrollView alloc] initWithFrame:NSMakeRect (0, 0, QW - 28, 100)] autorelease];
    [s setHasVerticalScroller:YES];
    [s setBorderType:NSBezelBorder];
    table = [[[NSTableView alloc] initWithFrame:[[s contentView] bounds]] autorelease];
    NSTableColumn *check = [[[NSTableColumn alloc] initWithIdentifier:@"want"] autorelease];
    NSButtonCell *cell = [[[NSButtonCell alloc] init] autorelease];
    [cell setButtonType:NSSwitchButton];
    [cell setTitle:@""];
    [check setDataCell:cell];
    [check setWidth:22];
    [table addTableColumn:check];
    NSTableColumn *name = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [name setWidth:[s contentSize].width - 30];
    [name setEditable:NO];
    [table addTableColumn:name];
    [table setHeaderView:nil];
    [table setUsesAlternatingRowBackgroundColors:YES];
    [table setDataSource:self];
    [s setDocumentView:table];
    [v addSubview:s];

    closeButton = PPBButton (v, NSZeroRect, @"Cancel", self, @selector(cancelAction:));
    save = PPBButton (v, NSZeroRect, @"Switch to It", self, @selector(save:));
    buttons = PPBButtonRow (QW - 28, [NSArray arrayWithObjects:closeButton, save, nil], NO);
    [closeButton setKeyEquivalent:@"\033"];
    [v addSubview:buttons];
    [save setEnabled:NO];

    state = QProbe;
    [self setInfo:U ("Shuffle plays songs from several of your stations, mixed. "
                     "Looking up your stations" ELLIPSIS)];
    placeNear (panel, [host playerWindow]);
    [panel makeKeyAndOrderFront:nil];
    [self sendKey:@"s"];        /* the station list, with its Shuffle flags */
}

- (void)bringToFront { [panel makeKeyAndOrderFront:nil]; }
- (void)closeUI { [panel orderOut:nil]; }

- (void)loadMix {
    state = QLoading;
    [rows removeAllObjects];
    [self setInfo:U ("Loading the mix" ELLIPSIS)];
    if (![engine sendKeys:@"x"]) {
        state = QNeedSwitch;
        [self setInfo:@"Pandora is busy; try again."];
    }
}

- (void)listItem:(NSString *)item {
    outputSeen = YES;
    if (state != QProbe && state != QLoading) return;   /* reprints while saving */
    int i; NSString *t;
    if (!PPBParseListItem (item, &i, &t) || [t length] < 5) return;
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    [r setObject:[NSNumber numberWithInt:i] forKey:@"index"];
    [r setObject:stripStationFlags (t) forKey:@"name"];
    [r setObject:[NSNumber numberWithBool:[t characterAtIndex:0] == 'q'] forKey:@"inMix"];
    [r setObject:[NSNumber numberWithBool:[t characterAtIndex:0] == 'q'] forKey:@"want"];
    [r setObject:[NSNumber numberWithBool:[t characterAtIndex:1] == 'Q'] forKey:@"isShuffle"];
    [rows addObject:r];
}

- (void)answerNextToggle {
    if ([toggles count]) {
        NSNumber *i = [[[toggles objectAtIndex:0] retain] autorelease];
        [toggles removeObjectAtIndex:0];
        [engine answerLine:[i stringValue]];
    } else {
        [engine answerLine:@""];      /* done toggling: pianobar saves the mix */
    }
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if (state == QProbe && [p hasPrefix:@"Select station"]) {
        [engine cancelPrompt];
        unsigned i;
        for (i = 0; i < [rows count]; i++)
            if ([[[rows objectAtIndex:i] objectForKey:@"isShuffle"] boolValue])
                shuffleName = [[[rows objectAtIndex:i] objectForKey:@"name"] copy];
        if (shuffleName == nil) {
            state = QNoShuffle;
            [closeButton setTitle:@"Close"];
            [save setHidden:YES];
            [self setInfo:@"Your account doesn't have a Shuffle station yet. Pandora adds one once you have two or more stations."];
        } else if ([shuffleName isEqualToString:[host currentStationName]]) {
            [self loadMix];
        } else {
            state = QNeedSwitch;
            [save setEnabled:YES];
            [self setInfo:[NSString stringWithFormat:
                @"Shuffle plays songs from several of your stations, mixed. It's a station of its own, "
                @"\"%@\". Switch to it to choose which stations it mixes.", shuffleName]];
        }
    } else if ([p hasPrefix:@"Toggle QuickMix"]) {
        if (state == QLoading) {
            state = QEditing;
            [save setTitle:@"Save"];
            [save setEnabled:YES];
            [self setInfo:@"Shuffle plays songs from the checked stations, mixed together."];
        } else if (state == QSaving) {
            [self answerNextToggle];
        } else {
            [engine cancelPrompt];
        }
    } else {
        [engine cancelPrompt];
    }
}

- (IBAction)save:(id)sender {
    if (state == QNeedSwitch) {
        state = QSwitching;
        [save setEnabled:NO];
        [self setInfo:[NSString stringWithFormat:@"Switching to \"%@\"%@", shuffleName, U (ELLIPSIS)]];
        [host tuneToStationNamed:shuffleName];
        return;
    }
    if (state != QEditing) return;
    [toggles release];
    toggles = [[NSMutableArray alloc] init];
    NSArray *mix = [self mixRows];
    unsigned i;
    for (i = 0; i < [mix count]; i++) {
        NSDictionary *r = [mix objectAtIndex:i];
        if ([[r objectForKey:@"want"] boolValue] != [[r objectForKey:@"inMix"] boolValue])
            [toggles addObject:[r objectForKey:@"index"]];
    }
    state = QSaving;
    [save setEnabled:NO];
    [self answerNextToggle];
}

- (void)event:(NSString *)type info:(NSDictionary *)ev {
    outputSeen = YES;
    if (state == QSwitching && [type isEqualToString:@"songstart"] &&
        [[ev objectForKey:@"stationName"] isEqualToString:shuffleName]) {
        [self loadMix];
    } else if ([type isEqualToString:@"stationquickmixtoggle"]) {
        NSString *err = eventError (ev);
        [host setStatus:err ? err : @"Shuffle updated."];
        [self finish];
    }
}

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if (k == PPBMessageError) [self setInfo:t];
}

- (void)mainLoop {}      /* waits for the user (or for the switch to finish) */

- (int)numberOfRowsInTableView:(NSTableView *)tv {
    return state == QEditing || state == QSaving ? [[self mixRows] count] : 0;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(int)r {
    NSDictionary *d = [[self mixRows] objectAtIndex:r];
    return [[c identifier] isEqualToString:@"want"] ? [d objectForKey:@"want"] : [d objectForKey:@"name"];
}

- (void)tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)c row:(int)r {
    if (state != QEditing || ![[c identifier] isEqualToString:@"want"]) return;
    [[[self mixRows] objectAtIndex:r] setObject:[NSNumber numberWithBool:[v boolValue]] forKey:@"want"];
}

@end

/* ======================================================================== */

enum { IAsking, IListing, IChoosing, IRemoving, IEmpty };
#define IW 420.0

@implementation PPBStationInfoFlow

- (id)initWithHost:(id)aHost feedback:(BOOL)flag {
    if ((self = [super initWithHost:aHost])) {
        feedback = flag;
        rows = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [rows release];
    [catKey release];
    [super dealloc];
}

- (NSString *)explanation {
    if (feedback)
        return @"Songs you gave a thumbs up or down on this station. Taking one back undoes the rating: "
               @"a banned song can play again, and a loved one stops steering the station.";
    if ([catKey isEqualToString:@"s"])
        return @"Songs this station was built from. Removing one stops Pandora from basing the station "
               @"on it; the song can still play.";
    if ([catKey isEqualToString:@"t"])
        return @"Other stations this one was built from. Removing one stops Pandora from basing this "
               @"station on it.";
    return @"Artists this station was built from. Removing one stops Pandora from basing the station "
           @"on that artist; their music can still play.";
}

- (void)layout {
    [[table enclosingScrollView] setHidden:state == IEmpty];
    [table reloadData];
    NSMutableArray *views = [NSMutableArray arrayWithObject:info];
    NSMutableArray *heights = [NSMutableArray arrayWithObject:PPBH (PPBFitHeight (info, IW - 28))];
    if (category) { [views addObject:category]; [heights addObject:PPBH (26)]; }
    [views addObject:[table enclosingScrollView]];
    [heights addObject:PPBH (PPBTableHeight (table, [rows count], 3, 14))];
    [views addObject:buttons];
    [heights addObject:PPBH (32)];
    PPBStack (panel, IW, views, heights);
    if (category) {     /* popups look best at their natural width */
        NSRect f = [category frame];
        f.size.width = 160;
        [category setFrame:f];
    }
}

- (void)run:(NSString *)k {
    if ([engine prompt] != nil) [engine cancelPrompt];
    [catKey release];
    catKey = [k copy];
    [info setStringValue:[self explanation]];
    [rows removeAllObjects];
    [removeButton setEnabled:NO];
    state = IAsking;
    [self layout];
    if (![engine sendKeys:@"="]) {
        state = IEmpty;
        [info setStringValue:@"Pandora is busy; try again."];
        [self layout];
    }
}

- (void)start {
    NSString *station = [host currentStationName] ? [host currentStationName] : @"Station";
    panel = PPBPanel (IW, 100, [NSString stringWithFormat:feedback ? @"Thumbs Up & Down: %@" : @"Seeds: %@", station], self);
    NSView *v = [panel contentView];
    info = PPBWrappingLabel (v, NSMakeRect (0, 0, IW - 28, 18), 12);
    if (!feedback) {
        category = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 0, 160, 26) pullsDown:NO] autorelease];
        [category addItemWithTitle:@"Artists"];
        [[category lastItem] setRepresentedObject:@"a"];
        [category addItemWithTitle:@"Songs"];
        [[category lastItem] setRepresentedObject:@"s"];
        [category addItemWithTitle:@"Stations"];
        [[category lastItem] setRepresentedObject:@"t"];
        [category setTarget:self];
        [category setAction:@selector(categoryChanged:)];
        [v addSubview:category];
    }
    table = PPBTable (v, NSMakeRect (0, 0, IW - 28, 100), self, nil, NULL);
    NSButton *close = PPBButton (v, NSZeroRect, @"Close", self, @selector(cancelAction:));
    removeButton = PPBButton (v, NSZeroRect, feedback ? @"Take Back" : @"Remove", self, @selector(remove:));
    buttons = PPBButtonRow (IW - 28, [NSArray arrayWithObjects:close, removeButton, nil], YES);
    [v addSubview:buttons];
    [self run:feedback ? @"f" : @"a"];
    placeNear (panel, [host playerWindow]);
    [panel makeKeyAndOrderFront:nil];
}

- (void)bringToFront { [panel makeKeyAndOrderFront:nil]; }
- (void)closeUI { [panel orderOut:nil]; }

- (IBAction)categoryChanged:(id)sender {
    [self run:[[category selectedItem] representedObject]];
}

- (IBAction)remove:(id)sender {
    int r = [table selectedRow];
    if (state != IChoosing || r < 0 || r >= (int) [rows count]) { NSBeep (); return; }
    state = IRemoving;
    [removeButton setEnabled:NO];
    [engine answerLine:[[[rows objectAtIndex:r] objectAtIndex:0] stringValue]];
}

- (void)none {
    state = IEmpty;
    [info setStringValue:[[self explanation] stringByAppendingString:@"\n\nThis station has none."]];
    [self layout];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if (state == IAsking) {
        /* "Delete [a]rtist/[s]ong seeds or [f]eedback? Manage [m]ode?" */
        if ([bracketKeys (p) rangeOfString:catKey].location != NSNotFound) {
            state = IListing;
            [engine answerKey:catKey];
        } else {
            [engine cancelPrompt];
            [self none];
        }
    } else if (state == IListing &&
               ([p hasPrefix:@"Select artist"] || [p hasPrefix:@"Select song"] || [p hasPrefix:@"Delete seed station"])) {
        state = IChoosing;
        [self layout];
        [removeButton setEnabled:[rows count] > 0];
    } else {
        [engine cancelPrompt];
    }
}

- (void)listItem:(NSString *)item {
    outputSeen = YES;
    if (state != IListing) return;
    int i; NSString *t;
    if (PPBParseListItem (item, &i, &t))
        [rows addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:i], stripStationFlags (t), nil]];
}

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if ([t hasPrefix:@"No actions available"]) {
        [self none];
    } else if (k == PPBMessageError) {
        [info setStringValue:t];
        [self layout];
    }
}

- (void)event:(NSString *)type info:(NSDictionary *)ev {
    outputSeen = YES;
    if (![type hasPrefix:@"stationdelete"] || [type isEqualToString:@"stationdelete"]) return;
    NSString *err = eventError (ev);
    [host setStatus:err ? err : (feedback ? @"Rating taken back." : @"Seed removed.")];
    [self run:catKey];      /* refresh the list */
}

- (void)mainLoop {}

- (int)numberOfRowsInTableView:(NSTableView *)tv { return [rows count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(int)r {
    return [[rows objectAtIndex:r] objectAtIndex:1];
}

@end

/* ======================================================================== */

enum { MAsking, MListing, MChoosing, MSetting, MNone };
#define MW 440.0

@implementation PPBModeFlow

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [rows release];
    [super dealloc];
}

- (void)layout {
    [[table enclosingScrollView] setHidden:state == MNone];
    [table reloadData];
    PPBStack (panel, MW, [NSArray arrayWithObjects:info, [table enclosingScrollView], buttons, nil],
              [NSArray arrayWithObjects:PPBH (PPBFitHeight (info, MW - 28)),
               PPBH (PPBTableHeight (table, [rows count], 2, 10)), PPBH (32), nil]);
}

- (void)start {
    rows = [[NSMutableArray alloc] init];
    NSString *station = [host currentStationName] ? [host currentStationName] : @"Station";
    panel = PPBPanel (MW, 100, [NSString stringWithFormat:@"Station Mode: %@", station], self);
    NSView *v = [panel contentView];
    info = PPBWrappingLabel (v, NSMakeRect (0, 0, MW - 28, 18), 12);
    [info setStringValue:U ("A station's mode changes how Pandora picks its songs. "
                            "Changing it starts a new song. Loading" ELLIPSIS)];
    table = PPBTable (v, NSMakeRect (0, 0, MW - 28, 100), self, self, @selector(use:));
    NSButton *cancel = PPBButton (v, NSZeroRect, @"Cancel", self, @selector(cancelAction:));
    use = PPBButton (v, NSZeroRect, @"Use Mode", self, @selector(use:));
    buttons = PPBButtonRow (MW - 28, [NSArray arrayWithObjects:cancel, use, nil], NO);
    [cancel setKeyEquivalent:@"\033"];
    [v addSubview:buttons];
    [use setEnabled:NO];
    state = MAsking;
    [self layout];
    placeNear (panel, [host playerWindow]);
    [panel makeKeyAndOrderFront:nil];
    [self sendKey:@"="];
}

- (void)bringToFront { [panel makeKeyAndOrderFront:nil]; }
- (void)closeUI { [panel orderOut:nil]; }

- (void)noModes {
    state = MNone;
    [info setStringValue:@"This station doesn't have modes. (Shuffle stations don't.)"];
    [use setHidden:YES];
    [self layout];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if (state == MAsking) {
        if ([bracketKeys (p) rangeOfString:@"m"].location != NSNotFound) {
            state = MListing;
            [engine answerKey:@"m"];
        } else {
            [engine cancelPrompt];
            [self noModes];
        }
    } else if (state == MListing && [p hasPrefix:@"Pick a new mode"]) {
        state = MChoosing;
        [info setStringValue:@"A station's mode changes how Pandora picks its songs. Changing it starts a new song."];
        [self layout];
        unsigned i;
        for (i = 0; i < [rows count]; i++)
            if ([[[rows objectAtIndex:i] objectAtIndex:3] boolValue])
                [table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
        [use setEnabled:YES];
    } else {
        [engine cancelPrompt];
    }
}

/* " 2) Deep Cuts: Explore less popular tracks (active)" */
- (void)listItem:(NSString *)item {
    outputSeen = YES;
    if (state != MListing) return;
    int i; NSString *t;
    if (!PPBParseListItem (item, &i, &t)) return;
    BOOL active = [t hasSuffix:@" (active)"];
    if (active) t = [t substringToIndex:[t length] - 9];
    NSRange colon = [t rangeOfString:@": "];
    NSString *name = colon.location == NSNotFound ? t : [t substringToIndex:colon.location];
    NSString *desc = colon.location == NSNotFound ? @"" : [t substringFromIndex:NSMaxRange (colon)];
    [rows addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:i], name, desc,
                     [NSNumber numberWithBool:active], nil]];
}

- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if ([t hasPrefix:@"No actions available"]) [self noModes];
    else if (k == PPBMessageError) { [info setStringValue:t]; [self layout]; }
}

- (IBAction)use:(id)sender {
    int r = [table selectedRow];
    if (state != MChoosing || r < 0 || r >= (int) [rows count]) { NSBeep (); return; }
    state = MSetting;
    [use setEnabled:NO];
    [engine answerLine:[[[rows objectAtIndex:r] objectAtIndex:0] stringValue]];
}

- (void)event:(NSString *)type info:(NSDictionary *)ev {
    outputSeen = YES;
    if (![type isEqualToString:@"stationsetmode"]) return;
    NSString *err = eventError (ev);
    int r = [table selectedRow];
    NSString *name = r >= 0 && r < (int) [rows count] ? [[rows objectAtIndex:r] objectAtIndex:1] : @"";
    [host setStatus:err ? err : [NSString stringWithFormat:@"Mode: %@.", name]];
    [self finish];
}

- (void)mainLoop {}

- (int)numberOfRowsInTableView:(NSTableView *)tv { return [rows count]; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(int)r {
    NSArray *m = [rows objectAtIndex:r];
    NSString *mark = [[m objectAtIndex:3] boolValue] ? U ("\xe2\x9c\x93 ") : @"    ";
    if ([[m objectAtIndex:2] length] == 0) return [mark stringByAppendingString:[m objectAtIndex:1]];
    return [NSString stringWithFormat:@"%@%@ %@ %@", mark, [m objectAtIndex:1], U (DASH), [m objectAtIndex:2]];
}

@end

/* ======================================================================== */

enum { XLoading, XAsking, XSetting, XSaving };

@implementation PPBExplicitFlow

- (void)start {
    filterOn = -1;
    want = -1;
    state = XLoading;
    [host setStatus:U ("Checking the explicit content setting" ELLIPSIS)];
    [self sendKey:@"!"];
}

/* " 2) Explicit content filter (yes)" */
- (void)listItem:(NSString *)item {
    outputSeen = YES;
    if ([item rangeOfString:@"Explicit content filter ("].location == NSNotFound) return;
    filterOn = [item rangeOfString:@"(yes)"].location != NSNotFound;
}

- (void)chose:(NSNumber *)button {
    int b = [button intValue];          /* 0 On, 1 Off, 2 Cancel */
    if (done) return;
    if (b == 2 || (filterOn >= 0 && (b == 0) == !filterOn)) {
        [self cancel];                  /* nothing to change */
        [host setStatus:nil];
        return;
    }
    want = b == 1;                      /* explicit off = filter on */
    state = XSetting;
    [engine answerLine:@"2"];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    if ([p hasPrefix:@"Change setting"]) {
        if (state == XLoading) {
            state = XAsking;
            [host setStatus:nil];
            NSString *now = filterOn < 0 ? @"" : filterOn
                ? @"It's off now: Pandora skips songs marked explicit."
                : @"It's on now: songs marked explicit can play.";
            PPBChoiceSheet ([host playerWindow], @"Explicit content", now,
                            [NSArray arrayWithObjects:@"On", @"Off", @"Cancel", nil], self, @selector(chose:));
        } else if (state == XSetting) {
            state = XSaving;
            [engine answerLine:@""];    /* leave the menu: pianobar saves */
        } else {
            [engine cancelPrompt];
        }
    } else if ([p hasPrefix:@"Enable explicit content filter"] && state == XSetting) {
        [engine answerKey:want ? @"y" : @"n"];
    } else {
        [engine cancelPrompt];
    }
}

- (void)event:(NSString *)type info:(NSDictionary *)ev {
    outputSeen = YES;
    if (![type isEqualToString:@"settingschange"]) return;
    NSString *err = eventError (ev);
    [host setStatus:err ? err : want ? @"Explicit content off." : @"Explicit content on."];
    [self finish];
}

/* the sheet is up until the user answers */
- (void)mainLoop {
    if (state == XLoading && outputSeen && [engine prompt] == nil) [self finish];
}

@end

/* ======================================================================== */

@implementation PPBPanelFlow

- (id)initWithHost:(id)aHost panel:(PPBActionPanel *)p key:(NSString *)k title:(NSString *)t {
    if ((self = [super initWithHost:aHost])) {
        panel = [p retain];
        key = [k copy];
        title = [t copy];
    }
    return self;
}

- (void)dealloc {
    if ([panel delegate] == self) [panel setDelegate:nil];
    [panel release];
    [key release];
    [title release];
    [super dealloc];
}

- (void)start {
    [panel setDelegate:self];
    [panel beginAction:title nearWindow:[host playerWindow]];
    [self sendKey:key];
}

- (void)bringToFront { [[panel panelWindow] makeKeyAndOrderFront:nil]; }

- (void)closeUI {
    [panel setDelegate:nil];
    [panel close];
}

- (void)prompt:(NSString *)p {
    outputSeen = YES;
    [panel askQuestion:p];
}

- (void)listItem:(NSString *)item {
    outputSeen = YES;
    [panel addListItem:item];
}

/* results go to the player window's status line */
- (void)message:(NSString *)t kind:(PPBMessageKind)k {
    outputSeen = YES;
    if (k == PPBMessageError || PPBIsProgress (t)) [host setStatus:t];
}

/* panel delegate */
- (void)actionPanel:(PPBActionPanel *)p answerLine:(NSString *)line { [engine answerLine:line]; }
- (void)actionPanel:(PPBActionPanel *)p answerKey:(NSString *)k     { [engine answerKey:k]; }
- (void)actionPanelCancel:(PPBActionPanel *)p                       { [self cancel]; }

@end
