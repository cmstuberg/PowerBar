#import "PPBUI.h"

NSTextField *PPBLabel (NSView *parent, NSRect frame, float size, BOOL bold) {
    NSTextField *l = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [l setBezeled:NO];
    [l setDrawsBackground:NO];
    [l setEditable:NO];
    [l setSelectable:NO];
    [l setFont:bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]];
    [[l cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [parent addSubview:l];
    return l;
}

NSTextField *PPBWrappingLabel (NSView *parent, NSRect frame, float size) {
    NSTextField *l = PPBLabel (parent, frame, size, NO);
    [[l cell] setWraps:YES];
    [[l cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return l;
}

NSButton *PPBButton (NSView *parent, NSRect frame, NSString *title, id target, SEL action) {
    NSButton *b = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTitle:title];
    [b setTarget:target];
    [b setAction:action];
    [parent addSubview:b];
    return b;
}

NSButton *PPBSmallButton (NSView *parent, NSRect frame, NSString *title, id target, SEL action) {
    NSButton *b = PPBButton (parent, frame, title, target, action);
    [b setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [[b cell] setControlSize:NSSmallControlSize];
    return b;
}

NSTableView *PPBTable (NSView *parent, NSRect frame, id source, id target, SEL doubleAction) {
    NSScrollView *s = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
    [s setHasVerticalScroller:YES];
    [s setBorderType:NSBezelBorder];
    NSTableView *t = [[[NSTableView alloc] initWithFrame:[[s contentView] bounds]] autorelease];
    NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier:@"text"] autorelease];
    [c setWidth:[s contentSize].width - 4];
    [c setEditable:NO];
    [[c dataCell] setFont:[NSFont systemFontOfSize:12]];
    [t addTableColumn:c];
    [t setHeaderView:nil];
    [t setUsesAlternatingRowBackgroundColors:YES];
    [t setDataSource:source];
    [t setTarget:target];
    [t setDoubleAction:doubleAction];
    [s setDocumentView:t];
    [parent addSubview:s];
    return t;
}

NSPanel *PPBPanel (float w, float h, NSString *title, id delegate) {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, w, h)
                                            styleMask:NSTitledWindowMask | NSClosableWindowMask
                                              backing:NSBackingStoreBuffered defer:YES];
    [p setTitle:title];
    [p setReleasedWhenClosed:NO];
    [p setHidesOnDeactivate:NO];
    [p setDelegate:delegate];
    return p;
}

NSPanel *PPBSheetPanel (float w, float h) {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, w, h)
                                            styleMask:NSTitledWindowMask
                                              backing:NSBackingStoreBuffered defer:YES];
    [p setReleasedWhenClosed:NO];
    return p;
}

BOOL PPBParseListItem (NSString *item, int *index, NSString **text) {
    NSScanner *s = [NSScanner scannerWithString:item];
    [s setCharactersToBeSkipped:nil];
    [s scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
    int i;
    if (![s scanInt:&i] || ![s scanString:@")" intoString:NULL]) {
        if (text) *text = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        return NO;
    }
    NSString *rest = [item substringFromIndex:[s scanLocation]];
    if ([rest hasPrefix:@" "]) rest = [rest substringFromIndex:1];
    if (index) *index = i;
    if (text) *text = rest;
    return YES;
}

BOOL PPBIsProgress (NSString *text) {
    return [text hasSuffix:@"..."] || [text hasSuffix:@"... Ok."] || [text hasSuffix:@"Ok."];
}

/* --- layout --- */

#define MARGIN 16.0
#define GAP 10.0

float PPBFitHeight (NSTextField *label, float width) {
    return ceil ([[label cell] cellSizeForBounds:NSMakeRect (0, 0, width, 10000)].height);
}

float PPBTableHeight (NSTableView *t, int rows, int minRows, int maxRows) {
    if (rows < minRows) rows = minRows;
    if (rows > maxRows) rows = maxRows;
    return rows * ([t rowHeight] + [t intercellSpacing].height) + 4;
}

NSView *PPBButtonRow (float width, NSArray *buttons, BOOL escLast) {
    NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, width, 32)] autorelease];
    float x = width;
    int i;
    for (i = [buttons count] - 1; i >= 0; i--) {
        NSButton *b = [buttons objectAtIndex:i];
        [b sizeToFit];
        NSRect f = [b frame];
        f.size.width = MAX (f.size.width + 12, 86);
        f.size.height = 32;
        x -= f.size.width;
        f.origin = NSMakePoint (x, 0);   /* rounded buttons draw inset, which spaces them */
        [b setFrame:f];
        [row addSubview:b];
    }
    if (escLast && [buttons count]) [[buttons lastObject] setKeyEquivalent:@"\033"];
    return row;
}

void PPBStack (NSWindow *w, float width, NSArray *views, NSArray *heights) {
    float total = MARGIN;
    unsigned i, n = [views count];
    BOOL any = NO;
    for (i = 0; i < n; i++) {
        if ([[views objectAtIndex:i] isHidden]) continue;
        total += [[heights objectAtIndex:i] floatValue] + (any ? GAP : 0);
        any = YES;
    }
    total += 12;
    NSRect old = [w frame];
    NSRect nf = [w frameRectForContentRect:NSMakeRect (0, 0, width, total)];
    nf.origin = NSMakePoint (NSMinX (old), NSMaxY (old) - NSHeight (nf));
    [w setFrame:nf display:[w isVisible]];
    float y = total - MARGIN;
    for (i = 0; i < n; i++) {
        NSView *v = [views objectAtIndex:i];
        if ([v isHidden]) continue;
        float h = [[heights objectAtIndex:i] floatValue];
        y -= h;
        [v setFrame:NSMakeRect (14, y, width - 28, h)];
        if ([v superview] == nil) [[w contentView] addSubview:v];
        y -= GAP;
    }
}

/* --- choice sheet --- */

@interface PPBChoice : NSObject {
@public
    NSPanel *sheet;
    id target;
    SEL selector;
}
@end

@implementation PPBChoice
- (IBAction)chose:(id)sender {
    [NSApp endSheet:sheet];
    [sheet orderOut:nil];
    [target performSelector:selector withObject:[NSNumber numberWithInt:[sender tag]]];
    [sheet autorelease];
    [self autorelease];
}
@end

void PPBChoiceSheet (NSWindow *window, NSString *message, NSString *info,
                     NSArray *titles, id target, SEL selector) {
    const float W = 420, textX = 96, textW = W - textX - 18;
    PPBChoice *c = [[PPBChoice alloc] init];
    c->target = target;
    c->selector = selector;
    c->sheet = PPBSheetPanel (W, 100);
    NSView *v = [c->sheet contentView];

    NSTextField *m = PPBWrappingLabel (v, NSMakeRect (textX, 0, textW, 10), 13);
    [m setFont:[NSFont boldSystemFontOfSize:13]];
    [m setStringValue:message];
    NSTextField *t = PPBWrappingLabel (v, NSMakeRect (textX, 0, textW, 10), 11);
    [t setStringValue:info ? info : @""];
    float mh = PPBFitHeight (m, textW), th = [info length] ? PPBFitHeight (t, textW) : 0;

    NSMutableArray *buttons = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < [titles count]; i++) {
        NSButton *b = PPBButton (v, NSZeroRect, [titles objectAtIndex:i], c, @selector(chose:));
        [b setTag:i];
        [buttons addObject:b];
    }
    NSView *row = PPBButtonRow (W - 28, buttons, YES);

    float textH = mh + (th ? 6 + th : 0);
    float top = MAX (64, textH);
    float H = 18 + top + 10 + 32 + 12;
    [c->sheet setContentSize:NSMakeSize (W, H)];
    NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSMakeRect (20, H - 18 - 64, 64, 64)] autorelease];
    [icon setImage:[NSApp applicationIconImage]];
    [v addSubview:icon];
    [m setFrame:NSMakeRect (textX, H - 18 - mh, textW, mh)];
    [t setFrame:NSMakeRect (textX, H - 18 - mh - 6 - th, textW, th)];
    [row setFrame:NSMakeRect (14, 12, W - 28, 32)];
    [v addSubview:row];
    [NSApp beginSheet:c->sheet modalForWindow:window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}
