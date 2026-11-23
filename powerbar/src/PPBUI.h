/* Small Cocoa helpers shared by the windows (10.4 APIs, nib-less). */
#import <Cocoa/Cocoa.h>
#import "PPBText.h"

#define ELLIPSIS "\xe2\x80\xa6"
#define DASH     "\xe2\x80\x93"

NSTextField *PPBLabel (NSView *parent, NSRect frame, float size, BOOL bold);
/* A label that wraps (for explanations). */
NSTextField *PPBWrappingLabel (NSView *parent, NSRect frame, float size);
NSButton *PPBButton (NSView *parent, NSRect frame, NSString *title, id target, SEL action);
NSButton *PPBSmallButton (NSView *parent, NSRect frame, NSString *title, id target, SEL action);
/* A one-column table in a scroll view; the table is returned, data source = source. */
NSTableView *PPBTable (NSView *parent, NSRect frame, id source, id target, SEL doubleAction);
/* A plain panel (titled, closable) of the given content size. */
NSPanel *PPBPanel (float w, float h, NSString *title, id delegate);
/* A non-closable panel for use as a sheet. */
NSPanel *PPBSheetPanel (float w, float h);

/* " 3) Artist - Title" -> 3 and "Artist - Title"; returns NO if there's no index. */
BOOL PPBParseListItem (NSString *item, int *index, NSString **text);
/* pianobar prints progress as "Doing something... Ok." */
BOOL PPBIsProgress (NSString *text);

/* --- layout: windows sized to their content --- */

/* Height a wrapping label needs at the given width for its current text. */
float PPBFitHeight (NSTextField *label, float width);
/* Height for a table showing rows (clamped to minRows..maxRows) plus its border. */
float PPBTableHeight (NSTableView *t, int rows, int minRows, int maxRows);
/* A strip of buttons, right-aligned, left to right in the given order, each sized
 * to its title. The last one answers Escape if escLast. */
NSView *PPBButtonRow (float width, NSArray *buttons, BOOL escLast);
/* Stack views top to bottom (hidden ones skipped) with the given heights, size the
 * window's content to fit them (width fixed), keeping the window's top-left corner
 * where it is. */
void PPBStack (NSWindow *w, float width, NSArray *views, NSArray *heights);
#define PPBH(x) [NSNumber numberWithFloat:(x)]

/* A sheet with the app icon, a bold message, smaller text, and buttons left to right
 * (put Cancel last: it sits on the right and answers Escape). Calls
 * [target selector:(NSNumber *) index of the button]. */
void PPBChoiceSheet (NSWindow *window, NSString *message, NSString *info,
                     NSArray *buttons, id target, SEL selector);
