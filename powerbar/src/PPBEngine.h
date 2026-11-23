/* PPBEngine: runs the bundled pianobar and talks to it.
 *
 * pianobar is started with a config this class writes, under
 * ~/Library/Application Support/PowerBar/pianobar/. Control goes in on
 * pianobar's stdin (the same key commands as its FIFO, but private to us). Everything
 * comes back on its stdout, made machine-readable by the config:
 *
 *   PPB:EVENT <type> / key=value lines / PPB:END    (event_command = ppb-event)
 *   PPB:TIME 01:23/03:45                             (elapsed/total, every second)
 *   PPB:ASK <prompt>                                 (pianobar waits for input)
 *   PPB:LIST <item>                                  (e.g. " 3) Artist - Title")
 *   PPB:INFO / PPB:ERR / PPB:PLAY <text>
 *
 * Every pianobar message starts with ESC[2K (clear line), and single-key answers
 * aren't followed by a newline, so ESC[2K also ends a line here.
 *
 * The login password is typed into pianobar's own prompt, so it never touches disk,
 * argv or the environment. Mac OS X 10.4+, manual retain/release. */
#import <Cocoa/Cocoa.h>

@class PPBEngine;

typedef enum { PPBMessageInfo, PPBMessageError, PPBMessagePlaying } PPBMessageKind;

@interface NSObject (PPBEngineDelegate)
/* type is pianobar's event name (songstart, userlogin, usergetstations...). */
- (void)engine:(PPBEngine *)engine event:(NSString *)type info:(NSDictionary *)info;
- (void)engine:(PPBEngine *)engine elapsed:(int)elapsed total:(int)total;
/* pianobar is waiting for an answer the engine doesn't give itself. Answer with
 * answerLine:, answerKey: or cancelPrompt. */
- (void)engine:(PPBEngine *)engine prompt:(NSString *)prompt;
- (void)engine:(PPBEngine *)engine listItem:(NSString *)item;
- (void)engine:(PPBEngine *)engine message:(NSString *)text kind:(PPBMessageKind)kind;
- (void)engineDidExit:(PPBEngine *)engine status:(int)status;
@end

@interface PPBEngine : NSObject {
    id delegate;                 /* not retained */
    NSString *supportDir;
    NSTask *task;
    NSFileHandle *toEngine, *fromEngine;
    NSMutableData *pending;
    NSString *password;          /* only until pianobar's login prompt */
    NSString *eventType;
    NSMutableDictionary *eventInfo;
    NSString *prompt;            /* the open prompt, or nil */
    int pendingStation;          /* index to answer the next "Select station" with */
    BOOL promptSeen;             /* the current partial line's prompt was handled */
    BOOL sawEOF, exited;
}
/* ~/Library/Application Support/PowerBar ($PPB_SUPPORT_DIR overrides it). */
+ (NSString *)defaultSupportDirectory;

- (id)initWithDelegate:(id)aDelegate supportDirectory:(NSString *)dir;
/* quality: low | medium | high. Returns NO with *error set if it can't start. */
- (BOOL)startWithUser:(NSString *)user password:(NSString *)pass
              quality:(NSString *)quality error:(NSString **)error;
- (BOOL)isRunning;

/* Key commands for pianobar's main loop, e.g. @"n" (next), @"+" (love). Refused
 * (returns NO) while a prompt is open, so keys can't land in an answer. */
- (BOOL)sendKeys:(NSString *)keys;
/* Index into the station list from the last event that carried one. */
- (void)selectStationAtIndex:(int)index;

/* The open prompt (e.g. "New name:"), or nil. */
- (NSString *)prompt;
- (void)answerLine:(NSString *)line;   /* text + Return */
- (void)answerKey:(NSString *)key;     /* one key, no Return (y/n, [s]ong...) */
- (void)cancelPrompt;                  /* an empty answer: pianobar backs out */

/* Ask pianobar to quit (so it saves its state), then make sure it does. */
- (void)stop;
@end
