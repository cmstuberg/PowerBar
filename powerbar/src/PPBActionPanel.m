#import "PPBActionPanel.h"
#import "PPBUI.h"

#define W 420.0

/* Station lists carry three flag columns: "qQS Name" (q: in Shuffle, Q: is the
 * Shuffle station, S: shared). */
static NSString *stationText (NSString *raw) {
    if ([raw length] < 5 || [raw characterAtIndex:3] != ' ') return raw;
    unichar q = [raw characterAtIndex:0], Q = [raw characterAtIndex:1], S = [raw characterAtIndex:2];
    if ((q != ' ' && q != 'q') || (Q != ' ' && Q != 'Q') || (S != ' ' && S != 'S')) return raw;
    NSMutableString *t = [NSMutableString stringWithString:[raw substringFromIndex:4]];
    if (Q == 'Q') [t appendString:@"  (Shuffle)"];
    if (S == 'S') [t appendString:@"  (shared)"];
    return t;
}

@implementation PPBActionPanel

- (id)initWithDelegate:(id)aDelegate {
    if (!(self = [super init])) return nil;
    delegate = aDelegate;
    rows = [[NSMutableArray alloc] init];

    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, W, 300)
                                       styleMask:NSTitledWindowMask | NSClosableWindowMask
                                         backing:NSBackingStoreBuffered defer:YES];
    [panel setReleasedWhenClosed:NO];
    [panel setHidesOnDeactivate:NO];
    [panel setDelegate:self];
    NSView *v = [panel contentView];

    questionLabel = PPBWrappingLabel (v, NSMakeRect (0, 0, W - 28, 18), 13);
    [questionLabel setFont:[NSFont boldSystemFontOfSize:13]];
    table = PPBTable (v, NSMakeRect (0, 0, W - 28, 100), self, self, @selector(choose:));

    input = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, 0, W - 28, 22)] autorelease];
    [input setTarget:self];
    [input setAction:@selector(ok:)];
    [v addSubview:input];
    secureInput = [[[NSSecureTextField alloc] initWithFrame:[input frame]] autorelease];
    [secureInput setTarget:self];
    [secureInput setAction:@selector(ok:)];
    [v addSubview:secureInput];

    optionRow = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, W - 28, 32)] autorelease];
    [v addSubview:optionRow];

    cancelButton = PPBButton (v, NSZeroRect, @"Cancel", self, @selector(cancel:));
    okButton = PPBButton (v, NSZeroRect, @"OK", self, @selector(ok:));
    bottomRow = PPBButtonRow (W - 28, [NSArray arrayWithObjects:cancelButton, okButton, nil], NO);
    [cancelButton setKeyEquivalent:@"\033"];
    [okButton setKeyEquivalent:@"\r"];
    [v addSubview:bottomRow];
    [self askQuestion:nil];
    return self;
}

- (void)dealloc {
    [panel setDelegate:nil];
    [panel release];
    [rows release];
    [question release];
    [super dealloc];
}

- (void)setDelegate:(id)aDelegate { delegate = aDelegate; }
- (id)delegate { return delegate; }
- (BOOL)isVisible { return [panel isVisible]; }
- (NSPanel *)panelWindow { return panel; }
- (BOOL)hasQuestion { return question != nil; }

/* size the panel to the question, the list and the controls in use */
- (void)layout {
    [[table enclosingScrollView] setHidden:[rows count] == 0];
    /* Cancel sits on the right when there's no OK */
    NSRect cf = [cancelButton frame], of = [okButton frame];
    cf.origin.x = [okButton isHidden] ? NSMaxX (of) - cf.size.width : NSMinX (of) - cf.size.width;
    [cancelButton setFrame:cf];
    float qh = MAX (18, PPBFitHeight (questionLabel, W - 28));
    NSArray *views = [NSArray arrayWithObjects:questionLabel, [table enclosingScrollView],
                      input, secureInput, optionRow, bottomRow, nil];
    NSArray *heights = [NSArray arrayWithObjects:PPBH (qh), PPBH (PPBTableHeight (table, [rows count], 3, 14)),
                        PPBH (22), PPBH (22), PPBH ([optionRow frame].size.height), PPBH (32), nil];
    PPBStack (panel, W, views, heights);
}

- (void)beginAction:(NSString *)title nearWindow:(NSWindow *)window {
    [panel setTitle:title];
    [rows removeAllObjects];
    stationList = NO;
    listStale = NO;
    [table reloadData];
    [self askQuestion:nil];
    [questionLabel setStringValue:U ("Loading" ELLIPSIS)];
    [self layout];
    if (!positioned) {
        positioned = YES;
        NSRect wf = [window frame];
        [panel setFrameTopLeftPoint:NSMakePoint (NSMinX (wf) + 30, NSMaxY (wf) - 40)];
    }
    [panel orderFront:nil];
}

- (void)close {
    [question release];
    question = nil;
    [panel orderOut:nil];
}

- (void)addListItem:(NSString *)item {
    if (listStale) {
        [rows removeAllObjects];
        listStale = NO;
    }
    int i; NSString *t;
    if (PPBParseListItem (item, &i, &t))
        [rows addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:i], t, nil]];
    else
        [rows addObject:[NSArray arrayWithObjects:[NSNull null], t, nil]];
    [table reloadData];
}

/* --- the question --- */

/* Option buttons, left to right, wrapping into more rows if needed. */
- (void)setOptions:(NSArray *)options {
    NSArray *old = [[[optionRow subviews] copy] autorelease];
    unsigned i;
    for (i = 0; i < [old count]; i++) [[old objectAtIndex:i] removeFromSuperview];
    float x = 0, y = 0, rowsUsed = [options count] ? 1 : 0;
    NSMutableArray *made = [NSMutableArray array];
    for (i = 0; i < [options count]; i++) {
        NSArray *o = [options objectAtIndex:i];
        NSButton *b = PPBButton (optionRow, NSZeroRect, [o objectAtIndex:0], self, @selector(option:));
        [b sizeToFit];
        NSRect f = [b frame];
        f.size.width = MAX (f.size.width + 4, 64);
        f.size.height = 32;
        if (x + f.size.width > W - 28 && x > 0) { x = 0; rowsUsed++; }
        f.origin = NSMakePoint (x, -(rowsUsed - 1) * 34);
        [b setFrame:f];
        [[b cell] setRepresentedObject:[o objectAtIndex:1]];
        x += f.size.width;
        [made addObject:b];
    }
    float h = rowsUsed * 34;
    [optionRow setFrameSize:NSMakeSize (W - 28, MAX (h, 1))];
    for (i = 0; i < [made count]; i++) {      /* flip to top-down rows */
        NSButton *b = [made objectAtIndex:i];
        NSRect f = [b frame];
        f.origin.y += h - 34;
        [b setFrame:f];
    }
    [optionRow setHidden:[options count] == 0];
    (void) y;
}

/* "[s]ong or [a]rtist" -> (("Song","s"),("Artist","a")); "s[t]ation" -> "Station" */
- (NSArray *)bracketOptions:(NSString *)q {
    NSMutableArray *opts = [NSMutableArray array];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    unsigned i, n = [q length];
    for (i = 0; i + 2 < n; i++) {
        if ([q characterAtIndex:i] != '[' || [q characterAtIndex:i + 2] != ']') continue;
        unsigned a = i, b = i + 3;
        while (a > 0 && [letters characterIsMember:[q characterAtIndex:a - 1]]) a--;
        while (b < n && [letters characterIsMember:[q characterAtIndex:b]]) b++;
        NSString *key = [q substringWithRange:NSMakeRange (i + 1, 1)];
        NSString *word = [NSString stringWithFormat:@"%@%@%@",
            [q substringWithRange:NSMakeRange (a, i - a)], key,
            [q substringWithRange:NSMakeRange (i + 3, b - i - 3)]];
        [opts addObject:[NSArray arrayWithObjects:[word capitalizedString], key, nil]];
    }
    return opts;
}

/* The question without its "[s]ong or [a]rtist" key hints, for display. */
- (NSString *)plainQuestion:(NSString *)q {
    NSMutableString *s = [NSMutableString stringWithString:q];
    unsigned i;
    for (i = 0; i + 2 < [s length]; i++)
        if ([s characterAtIndex:i] == '[' && [s characterAtIndex:i + 2] == ']')
            [s replaceCharactersInRange:NSMakeRange (i, 3) withString:[s substringWithRange:NSMakeRange (i + 1, 1)]];
    [s replaceOccurrencesOfString:@" yN" withString:@"" options:0 range:NSMakeRange (0, [s length])];
    [s replaceOccurrencesOfString:@" Yn" withString:@"" options:0 range:NSMakeRange (0, [s length])];
    [s replaceOccurrencesOfString:@" yn" withString:@"" options:0 range:NSMakeRange (0, [s length])];
    return s;
}

- (void)askQuestion:(NSString *)prompt {
    [question release];
    question = [prompt copy];
    [input setHidden:YES];
    [secureInput setHidden:YES];
    [okButton setHidden:YES];
    [self setOptions:[NSArray array]];
    if (prompt == nil) {
        [questionLabel setStringValue:U ("Working" ELLIPSIS)];
        if ([panel isVisible]) [self layout];
        return;
    }
    stationList = [prompt rangeOfString:@"station" options:NSCaseInsensitiveSearch].location != NSNotFound;
    [table reloadData];

    if ([prompt rangeOfString:@"[yN]" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [questionLabel setStringValue:[self plainQuestion:prompt]];
        [self setOptions:[NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"Yes", @"y", nil], [NSArray arrayWithObjects:@"No", @"n", nil], nil]];
    } else if ([prompt hasPrefix:@"What to do with this song"]) {
        [questionLabel setStringValue:prompt];
        [self setOptions:[NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"Love", @"+", nil], [NSArray arrayWithObjects:@"Ban", @"-", nil],
            [NSArray arrayWithObjects:@"Tired", @"t", nil], [NSArray arrayWithObjects:@"Bookmark", @"b", nil],
            [NSArray arrayWithObjects:@"New Station", @"v", nil], nil]];
    } else if ([[self bracketOptions:prompt] count] > 0) {
        [questionLabel setStringValue:[self plainQuestion:prompt]];
        [self setOptions:[self bracketOptions:prompt]];
    } else {
        [questionLabel setStringValue:prompt];
        BOOL secret = [prompt rangeOfString:@"password" options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSTextField *f = secret ? (NSTextField *) secureInput : input;
        [f setStringValue:@""];
        [[f cell] setPlaceholderString:[rows count] ? @"Double-click an item, or type to search" : nil];
        [f setHidden:NO];
        [okButton setHidden:NO];
        [self layout];
        [panel makeKeyAndOrderFront:nil];
        [panel makeFirstResponder:f];
        if ([rows count]) [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        return;
    }
    [self layout];
    [panel makeKeyAndOrderFront:nil];
}

- (void)answered {
    [self askQuestion:nil];
    listStale = YES;
}

- (IBAction)option:(id)sender {
    NSString *key = [[sender cell] representedObject];
    [self answered];
    if ([delegate respondsToSelector:@selector(actionPanel:answerKey:)])
        [delegate actionPanel:self answerKey:key];
}

- (void)sendLine:(NSString *)line {
    [self answered];
    if ([delegate respondsToSelector:@selector(actionPanel:answerLine:)])
        [delegate actionPanel:self answerLine:line];
}

- (IBAction)ok:(id)sender {
    if (question == nil) return;
    NSTextField *f = [secureInput isHidden] ? input : (NSTextField *) secureInput;
    NSString *text = [f stringValue];
    int r = [table selectedRow];
    if ([text length] == 0 && r >= 0 && [[[rows objectAtIndex:r] objectAtIndex:0] isKindOfClass:[NSNumber class]])
        text = [[[rows objectAtIndex:r] objectAtIndex:0] stringValue];
    [f setStringValue:@""];
    [self sendLine:text];   /* empty = back out, like pianobar */
}

- (IBAction)choose:(id)sender {
    int r = [table clickedRow];
    /* only when pianobar wants a line (a number picks the row) */
    if (question == nil || [okButton isHidden] || r < 0 || r >= (int) [rows count]) return;
    id index = [[rows objectAtIndex:r] objectAtIndex:0];
    if ([index isKindOfClass:[NSNumber class]]) [self sendLine:[index stringValue]];
}

/* Cancel (and the close box) back out of whatever is running and close at once. */
- (IBAction)cancel:(id)sender {
    [self close];
    if ([delegate respondsToSelector:@selector(actionPanelCancel:)])
        [delegate actionPanelCancel:self];
}

- (BOOL)windowShouldClose:(id)sender {
    [question release];
    question = nil;
    if ([delegate respondsToSelector:@selector(actionPanelCancel:)])
        [delegate actionPanelCancel:self];
    return YES;
}

/* --- table data source --- */

- (int)numberOfRowsInTableView:(NSTableView *)tv {
    return [rows count];
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(int)row {
    NSArray *r = [rows objectAtIndex:row];
    NSString *text = [r objectAtIndex:1];
    return stationList ? stationText (text) : text;
}

@end
