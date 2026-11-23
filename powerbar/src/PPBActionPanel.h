/* PPBActionPanel: the general panel, for the pianobar features that are a chain of
 * list picks (History, Add Genre Station).
 *
 * It shows pianobar's question, its numbered list (" 3) Artist - Title") as a table
 * (double-click picks, typing searches), and turns the question into the right
 * control: a text field, or buttons for "[s]ong or [a]rtist", yes/no, or the
 * song actions. It sizes itself to what it shows. An empty answer backs out, which
 * is what Cancel and the close box send (and they close at once). */
#import <Cocoa/Cocoa.h>

@class PPBActionPanel;

@interface NSObject (PPBActionPanelDelegate)
- (void)actionPanel:(PPBActionPanel *)panel answerLine:(NSString *)line;
- (void)actionPanel:(PPBActionPanel *)panel answerKey:(NSString *)key;
- (void)actionPanelCancel:(PPBActionPanel *)panel;
@end

@interface PPBActionPanel : NSObject {
    id delegate;                     /* not retained */
    NSPanel *panel;
    NSTableView *table;
    NSTextField *questionLabel, *input;
    NSSecureTextField *secureInput;
    NSView *optionRow, *bottomRow;
    NSButton *okButton, *cancelButton;
    NSMutableArray *rows;            /* NSArray (index NSNumber or NSNull, text) */
    NSString *question;
    BOOL listStale;                  /* next list item starts a new list */
    BOOL stationList;
    BOOL positioned;
}
- (id)initWithDelegate:(id)aDelegate;
- (void)setDelegate:(id)aDelegate;
- (id)delegate;

/* Start an action: clear everything, set the title, show the panel. */
- (void)beginAction:(NSString *)title nearWindow:(NSWindow *)window;
- (BOOL)isVisible;
- (NSPanel *)panelWindow;
- (BOOL)hasQuestion;
/* Hide without telling the delegate. */
- (void)close;

- (void)addListItem:(NSString *)item;
- (void)askQuestion:(NSString *)prompt;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
@end
