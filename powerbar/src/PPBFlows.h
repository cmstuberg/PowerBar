/* Flows: one per pianobar feature, each with its own small window or sheet.
 *
 * A flow sends one pianobar key, then answers the questions pianobar asks by itself
 * (from what the user chose in the flow's window), so the user only ever sees a
 * native dialog. While a flow runs, the controller hands it everything the engine
 * reports. Cancel always backs out and closes at once. Windows size themselves to
 * their content (PPBStack). */
#import <Cocoa/Cocoa.h>
#import "PPBEngine.h"
#import "PPBActionPanel.h"

@class PPBFlow;

/* What a flow needs from the controller. */
@interface NSObject (PPBFlowHost)
- (PPBEngine *)engine;
- (NSWindow *)playerWindow;
- (void)setStatus:(NSString *)s;
- (void)flowFinished:(PPBFlow *)flow;
- (NSString *)currentStationName;
- (NSArray *)stationNameList;
- (void)tuneToStationNamed:(NSString *)name;
@end

@interface PPBFlow : NSObject {
    id host;                   /* not retained */
    PPBEngine *engine;
    BOOL done, outputSeen;
}
- (id)initWithHost:(id)aHost;
- (void)start;
/* Back out: cancel any open question, close, finish. */
- (void)cancel;
- (void)finish;
- (BOOL)isDone;
- (void)bringToFront;

/* engine reports, while this flow runs */
- (void)prompt:(NSString *)p;
- (void)listItem:(NSString *)item;
- (void)message:(NSString *)text kind:(PPBMessageKind)kind;
- (void)event:(NSString *)type info:(NSDictionary *)info;
- (void)mainLoop;          /* pianobar is back in its main loop (time ticks) */
@end

/* Send a key, answer known questions in order, report the result in the status line.
 * answers: arrays of (prompt prefix, answer, @"key" or @"line"). */
@interface PPBScriptFlow : PPBFlow {
    NSString *key;
    NSArray *answers;
    NSArray *doneEvents;
    NSString *success;
    unsigned next;
    NSArray *stationsBefore;   /* set: tune to the station this creates */
}
- (id)initWithHost:(id)aHost key:(NSString *)k answers:(NSArray *)a
        doneEvents:(NSArray *)events success:(NSString *)text;
- (void)tuneToNewStation;
@end

@interface PPBExplainFlow : PPBFlow {
    NSPanel *panel;
    NSTextField *text;
    NSView *buttons;
}
@end

/* New Station (key c) and Add Music (key a): search, pick, create/add. */
@interface PPBSearchFlow : PPBFlow {
    BOOL addMusic;
    NSPanel *panel;
    NSTextField *query, *info;
    NSPopUpButton *scope;
    NSTableView *table;
    NSButton *commit;
    NSMutableArray *rows;      /* (NSNumber index, NSString text) */
    NSArray *stationsBefore;
    int state;
}
- (id)initWithHost:(id)aHost addMusic:(BOOL)flag;
@end

/* Shuffle (QuickMix): which stations the Shuffle station mixes. */
@interface PPBShuffleFlow : PPBFlow {
    NSPanel *panel;
    NSTextField *info;
    NSTableView *table;
    NSView *buttons;
    NSButton *save, *closeButton;
    NSMutableArray *rows;      /* NSMutableDictionary: index, name, inMix, isShuffle, want */
    NSString *shuffleName;
    NSMutableArray *toggles;
    int state;
}
@end

/* Station seeds (artists/songs/stations it was built from) or your thumbs. */
@interface PPBStationInfoFlow : PPBFlow {
    BOOL feedback;
    NSPanel *panel;
    NSTextField *info;
    NSPopUpButton *category;
    NSTableView *table;
    NSView *buttons;
    NSButton *removeButton;
    NSMutableArray *rows;
    NSString *catKey;
    int state;
}
- (id)initWithHost:(id)aHost feedback:(BOOL)flag;
@end

@interface PPBModeFlow : PPBFlow {
    NSPanel *panel;
    NSTextField *info;
    NSTableView *table;
    NSView *buttons;
    NSButton *use;
    NSMutableArray *rows;      /* (index, name, description, active) */
    int state;
}
@end

/* Explicit content on/off: pianobar's settings menu, item 2 (a *filter*, so
 * "explicit content on" = filter off). */
@interface PPBExplicitFlow : PPBFlow {
    int filterOn;              /* -1 unknown, 0/1 from pianobar's settings list */
    int want;                  /* -1 not chosen, 0/1 = filter wanted off/on */
    int state;
}
@end

/* History and Add Genre Station: the general panel. */
@interface PPBPanelFlow : PPBFlow {
    PPBActionPanel *panel;     /* owned by the host, shared */
    NSString *key, *title;
}
- (id)initWithHost:(id)aHost panel:(PPBActionPanel *)p key:(NSString *)k title:(NSString *)t;
@end
