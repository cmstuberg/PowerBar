/* PPBController: the app delegate, the player window, the sign-in sheet, and the
 * menus that start pianobar's features (each runs as a PPBFlow). */
#import <Cocoa/Cocoa.h>
#import "PPBEngine.h"
#import "PPBActionPanel.h"
#import "PPBFlows.h"

/* The player window: plain Space plays/pauses and Right Arrow skips. (The window has
 * no text fields, so these keys are free.) */
@interface PPBPlayerWindow : NSWindow {
    id keyTarget;
}
- (void)setKeyTarget:(id)target;
@end

@interface PPBController : NSObject {
    PPBEngine *engine;
    PPBPlayerWindow *window;
    NSImageView *art;
    NSPopUpButton *stations, *actions;
    NSButton *modeButton;
    NSTextField *titleLabel, *artistLabel, *albumLabel, *upNextLabel;
    NSString *upNextText;          /* what the up-next line shows between messages */

    /* for the Dashboard widget: nowplaying.json + the cover, in the support folder */
    NSString *artFile;
    int artSerial;
    BOOL loved;
    NSTimeInterval nowPlayingWritten;
    NSButton *timeButton;
    NSProgressIndicator *progress;
    NSButton *playButton, *nextButton, *loveButton, *banButton, *tiredButton;

    NSPanel *loginSheet;
    NSTextField *emailField, *loginStatus;
    NSSecureTextField *passwordField;

    NSPanel *inputSheet;         /* one text field: rename, shared station ID */
    NSTextField *inputLabel, *inputField;
    SEL inputDone;

    PPBActionPanel *actionPanel; /* the general panel (history, genres, settings) */
    PPBFlow *flow;               /* the feature running now, if any */
    BOOL drainPrompts;           /* a flow ended early: back out of stray questions */
    PPBFlow *pendingFlow;        /* started while draining: runs at the main loop */

    NSString *account;
    NSString *artURL;
    NSArray *stationNames;
    NSString *currentStation;
    int elapsed, total;
    BOOL paused, songLoaded, loginFailed, quitting;
    int restarts;

    /* --selftest: sign in with a dummy account; pass when Pandora's
     * "wrong password" answer comes back through the whole app. */
    BOOL selftest;
    NSString *snapshotPath;   /* --snapshot PATH: render sample UI to PNGs, quit */
}
- (id)initWithSelftest:(BOOL)flag;
- (void)setSnapshotPath:(NSString *)path;

- (IBAction)playPause:(id)sender;
- (IBAction)next:(id)sender;
- (IBAction)love:(id)sender;
- (IBAction)ban:(id)sender;
- (IBAction)tired:(id)sender;

- (IBAction)explain:(id)sender;
- (IBAction)bookmark:(id)sender;
- (IBAction)history:(id)sender;
- (IBAction)newStation:(id)sender;
- (IBAction)newStationFromSong:(id)sender;
- (IBAction)genreStation:(id)sender;
- (IBAction)sharedStation:(id)sender;
- (IBAction)addMusic:(id)sender;
- (IBAction)renameStation:(id)sender;
- (IBAction)deleteStation:(id)sender;
- (IBAction)stationMode:(id)sender;
- (IBAction)stationSeeds:(id)sender;
- (IBAction)thumbs:(id)sender;
- (IBAction)shuffle:(id)sender;
- (IBAction)explicitContent:(id)sender;
- (IBAction)installWidget:(id)sender;

- (IBAction)toggleTimeDisplay:(id)sender;
- (IBAction)stationChosen:(id)sender;
- (IBAction)signIn:(id)sender;
- (IBAction)signOut:(id)sender;
- (IBAction)showPlayer:(id)sender;
- (IBAction)about:(id)sender;

/* for flows */
- (PPBEngine *)engine;
- (NSWindow *)playerWindow;
- (void)setStatus:(NSString *)s;
- (void)flowFinished:(PPBFlow *)f;
- (NSString *)currentStationName;
- (NSArray *)stationNameList;
- (void)tuneToStationNamed:(NSString *)name;
@end

/* --uitest (PPBUITest.m) */
@interface PPBController (UITest)
- (void)setUITestDir:(NSString *)dir;
- (BOOL)uiTestRequested;
- (void)runUITest;
@end
