#import "PPBEngine.h"
#import "PPBText.h"
#include <sys/stat.h>

@interface PPBEngine (Private)
- (void)finishIfDone;
@end

static BOOL makeDirs (NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    if ([fm fileExistsAtPath:path isDirectory:&isDir]) return isDir;
    if (!makeDirs ([path stringByDeletingLastPathComponent])) return NO;
    return [fm createDirectoryAtPath:path attributes:nil];
}

/* Remove any other ANSI escape sequences (readline editing, ESC[D ESC[K). */
static NSString *stripEscapes (NSString *s) {
    if ([s rangeOfString:@"\033"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString stringWithCapacity:[s length]];
    unsigned i, n = [s length];
    for (i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == 0x1b && i + 1 < n && [s characterAtIndex:i + 1] == '[') {
            i += 2;
            while (i < n && !([s characterAtIndex:i] >= '@' && [s characterAtIndex:i] <= '~')) i++;
            continue;
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

static NSString *decode (const char *bytes, unsigned len) {
    NSString *s = [[[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding] autorelease];
    if (s == nil)
        s = [[[NSString alloc] initWithBytes:bytes length:len encoding:NSISOLatin1StringEncoding] autorelease];
    return s;
}

static int parseClock (NSString *s) {
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if ([parts count] != 2) return 0;
    return [[parts objectAtIndex:0] intValue] * 60 + [[parts objectAtIndex:1] intValue];
}

static NSString *trim (NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@implementation PPBEngine

+ (NSString *)defaultSupportDirectory {
    const char *env = getenv ("PPB_SUPPORT_DIR");
    if (env != NULL && *env) return [NSString stringWithUTF8String:env];
    NSArray *dirs = NSSearchPathForDirectoriesInDomains (NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString *base = [dirs count] ? [dirs objectAtIndex:0]
                                  : [NSHomeDirectory () stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *dir = [base stringByAppendingPathComponent:@"PowerBar"];
    /* up to 0.4 the app was called PandoraPowerBar: bring its settings and state along */
    NSString *old = [base stringByAppendingPathComponent:@"PandoraPowerBar"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir] && [fm fileExistsAtPath:old])
        [fm movePath:old toPath:dir handler:nil];
    return dir;
}

- (id)initWithDelegate:(id)aDelegate supportDirectory:(NSString *)dir {
    if ((self = [super init])) {
        delegate = aDelegate;
        supportDir = [dir copy];
        pending = [[NSMutableData alloc] init];
        pendingStation = -1;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if ([task isRunning]) [task terminate];
    [task release];
    [toEngine release];
    [fromEngine release];
    [pending release];
    [password release];
    [eventType release];
    [eventInfo release];
    [prompt release];
    [supportDir release];
    [super dealloc];
}

- (BOOL)isRunning {
    return task != nil && [task isRunning];
}

- (NSString *)prompt {
    return prompt;
}

- (void)setPrompt:(NSString *)p {
    if (p == prompt) return;
    [prompt release];
    prompt = [p copy];
}

- (NSString *)configText:(NSString *)user quality:(NSString *)quality
            eventCommand:(NSString *)eventCmd {
    NSMutableString *c = [NSMutableString string];
    [c appendString:@"# Written by PowerBar at every launch; edits are overwritten.\n"];
    [c appendString:@"# pianobar keeps the last station and volume in ./state.\n"];
    [c appendFormat:@"user = %@\n", user];
    [c appendFormat:@"audio_quality = %@\n", quality];
    /* Fixed level, no per-track boost: pianobar adds Pandora's trackGain (often
     * several dB) to the volume before converting to 16-bit, which clips loud
     * songs. -3 dB leaves headroom for lossy-decode overs; loudness is the system
     * volume's job. Overrides the volume in ./state. */
    [c appendString:@"volume = -3\ngain_mul = 0\n"];
    /* rating marks in song lists (history, upcoming): symbols, not "<3" */
    [c appendFormat:@"love_icon = %@\nban_icon = %@\ntired_icon = %@\n",
        U (" \xe2\x99\xa5"), @" (banned)", @" (tired)"];
    [c appendFormat:@"event_command = %@\n", eventCmd];
    /* no FIFO: we control pianobar through its stdin */
    [c appendFormat:@"fifo = %@\n", [supportDir stringByAppendingPathComponent:@"unused-ctl"]];
    [c appendString:@"format_time = %e/%t\n"];
    [c appendString:@"format_msg_none = %s\n"];
    [c appendString:@"format_msg_info = PPB:INFO %s\n"];
    [c appendString:@"format_msg_nowplaying = PPB:PLAY %s\n"];
    [c appendString:@"format_msg_time = PPB:TIME %s\n"];
    [c appendString:@"format_msg_err = PPB:ERR %s\n"];
    [c appendString:@"format_msg_question = PPB:ASK %s\n"];
    [c appendString:@"format_msg_list = PPB:LIST %s\n"];
    /* pin every key we send, in case upstream defaults change */
    [c appendString:
        @"act_songlove = +\nact_songban = -\nact_songtired = t\nact_songnext = n\n"
        @"act_songpause = S\nact_songplay = P\nact_stationchange = s\nact_quit = q\n"
        @"act_volup = disabled\nact_voldown = disabled\nact_volreset = disabled\n"
        @"act_songexplain = e\nact_songinfo = i\nact_bookmark = b\n"
        @"act_stationcreatefromsong = v\nact_upcoming = u\nact_history = h\n"
        @"act_stationcreate = c\nact_stationaddmusic = a\nact_stationaddbygenre = g\n"
        @"act_addshared = j\nact_stationrename = r\nact_stationdelete = d\n"
        @"act_stationselectquickmix = x\nact_managestation = =\nact_settings = !\n"];
    return c;
}

- (BOOL)startWithUser:(NSString *)user password:(NSString *)pass
              quality:(NSString *)quality error:(NSString **)error {
    if ([self isRunning]) return YES;
    NSBundle *b = [NSBundle mainBundle];
    NSString *engine = [b pathForAuxiliaryExecutable:@"pianobar"];
    NSString *eventCmd = [b pathForResource:@"ppb-event" ofType:nil];
    NSString *cacert = [b pathForResource:@"cacert" ofType:@"pem"];
    const char *testEngine = getenv ("PPB_ENGINE");   /* tests: a scripted stand-in */
    if (testEngine != NULL && *testEngine) {
        engine = [NSString stringWithUTF8String:testEngine];
        if (eventCmd == nil) eventCmd = @"/usr/bin/true";
        if (cacert == nil) cacert = @"/dev/null";
    }
    if (engine == nil || eventCmd == nil || cacert == nil) {
        if (error) *error = @"The app is incomplete: pianobar, ppb-event or cacert.pem is missing.";
        return NO;
    }
    NSCharacterSet *nl = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    if ([user rangeOfCharacterFromSet:nl].location != NSNotFound ||
        [pass rangeOfCharacterFromSet:nl].location != NSNotFound) {
        if (error) *error = @"Email and password can't contain line breaks.";
        return NO;
    }

    NSString *confDir = [supportDir stringByAppendingPathComponent:@"pianobar"];
    NSString *conf = [confDir stringByAppendingPathComponent:@"config"];
    if (!makeDirs (confDir) ||
        ![[self configText:user quality:quality eventCommand:eventCmd]
            writeToFile:conf atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        if (error) *error = [NSString stringWithFormat:@"Can't write %@.", conf];
        return NO;
    }
    chmod ([conf fileSystemRepresentation], 0600);

    NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    [env setObject:supportDir forKey:@"XDG_CONFIG_HOME"];
    [env setObject:cacert forKey:@"PPC_TLS_CAFILE"];
    [env setObject:@"dumb" forKey:@"TERM"];
    [env setObject:@"1" forKey:@"PIANOBAR_EXIT_ON_EOF"];

    NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe];
    [task release];
    task = [[NSTask alloc] init];
    [task setLaunchPath:engine];
    [task setArguments:[NSArray array]];
    [task setEnvironment:env];
    [task setCurrentDirectoryPath:supportDir];
    [task setStandardInput:in];
    [task setStandardOutput:out];
    [task setStandardError:out];

    [toEngine release];
    toEngine = [[in fileHandleForWriting] retain];
    [fromEngine release];
    fromEngine = [[out fileHandleForReading] retain];
    [pending setLength:0];
    [password release];
    password = [pass copy];
    [self setPrompt:nil];
    [eventType release]; eventType = nil;
    [eventInfo release]; eventInfo = nil;
    pendingStation = -1;
    promptSeen = NO;
    sawEOF = exited = NO;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
    [nc addObserver:self selector:@selector(readCompleted:)
               name:NSFileHandleReadCompletionNotification object:fromEngine];
    [nc addObserver:self selector:@selector(taskTerminated:)
               name:NSTaskDidTerminateNotification object:task];

    BOOL ok = YES;
    NS_DURING
        [task launch];
    NS_HANDLER
        ok = NO;
    NS_ENDHANDLER
    if (!ok) {
        if (error) *error = @"Couldn't start the pianobar engine.";
        [nc removeObserver:self];
        [task release];
        task = nil;
        return NO;
    }
    [fromEngine readInBackgroundAndNotify];
    return YES;
}

- (void)write:(NSString *)s {
    if (![self isRunning]) return;
    NS_DURING
        [toEngine writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    NS_HANDLER
        /* pipe closed: the engine is exiting, taskTerminated: will follow */
    NS_ENDHANDLER
}

- (BOOL)sendKeys:(NSString *)keys {
    if (prompt != nil || ![self isRunning]) return NO;
    [self write:keys];
    return YES;
}

- (void)answerLine:(NSString *)line {
    if (prompt == nil) return;
    [self setPrompt:nil];
    NSArray *parts = [line componentsSeparatedByString:@"\n"];
    line = [[[parts componentsJoinedByString:@" "] componentsSeparatedByString:@"\r"]
            componentsJoinedByString:@" "];
    [self write:[line stringByAppendingString:@"\n"]];
}

- (void)answerKey:(NSString *)key {
    if (prompt == nil || [key length] == 0) return;
    [self setPrompt:nil];
    [self write:[key substringToIndex:1]];
}

- (void)cancelPrompt {
    if (prompt == nil) return;
    [self setPrompt:nil];
    [self write:@"\n"];
}

- (void)selectStationAtIndex:(int)index {
    if (index < 0) return;
    if ([prompt hasPrefix:@"Select station"]) {
        [self answerLine:[NSString stringWithFormat:@"%d", index]];
    } else if (prompt == nil) {
        pendingStation = index;
        [self write:@"s"];
    }
}

- (void)stop {
    if (![self isRunning]) return;
    /* back out of any open prompt (they can nest a few levels deep; an empty
     * answer in the main loop does nothing), then quit */
    [self setPrompt:nil];
    [self write:@"\n\n\n\n"];
    [self write:@"q"];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while ([task isRunning] && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if ([task isRunning]) [task terminate];
}

/* --- output parsing --- */

- (void)handlePrompt:(NSString *)p {
    [self setPrompt:p];
    if ([p hasPrefix:@"Password"] && password != nil) {
        /* the login prompt: answer it once, then forget the password */
        NSString *pw = [[password retain] autorelease];
        [password release];
        password = nil;
        [self answerLine:pw];
        return;
    }
    if ([p hasPrefix:@"Select station"] && pendingStation >= 0) {
        int i = pendingStation;
        pendingStation = -1;
        [self answerLine:[NSString stringWithFormat:@"%d", i]];
        return;
    }
    if ([delegate respondsToSelector:@selector(engine:prompt:)])
        [delegate engine:self prompt:p];
    else
        [self cancelPrompt];
}

- (void)handleLine:(NSString *)line {
    line = stripEscapes (line);
    if (eventType != nil) {
        if ([line isEqualToString:@"PPB:END"]) {
            if ([delegate respondsToSelector:@selector(engine:event:info:)])
                [delegate engine:self event:eventType info:eventInfo];
            [eventType release]; eventType = nil;
            [eventInfo release]; eventInfo = nil;
        } else {
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location != NSNotFound)
                [eventInfo setObject:[line substringFromIndex:eq.location + 1]
                              forKey:[line substringToIndex:eq.location]];
        }
        return;
    }
    if ([line hasPrefix:@"PPB:EVENT "]) {
        eventType = [[line substringFromIndex:10] copy];
        eventInfo = [[NSMutableDictionary alloc] init];
    } else if ([line hasPrefix:@"PPB:TIME "]) {
        NSArray *p = [[line substringFromIndex:9] componentsSeparatedByString:@"/"];
        if ([p count] == 2 && [delegate respondsToSelector:@selector(engine:elapsed:total:)])
            [delegate engine:self elapsed:parseClock ([p objectAtIndex:0])
                       total:parseClock ([p objectAtIndex:1])];
    } else if ([line hasPrefix:@"PPB:LIST "]) {
        NSString *item = [line substringFromIndex:9];
        if ([trim (item) length] && [delegate respondsToSelector:@selector(engine:listItem:)])
            [delegate engine:self listItem:item];
    } else if ([line hasPrefix:@"PPB:ERR "] || [line hasPrefix:@"PPB:INFO "] || [line hasPrefix:@"PPB:PLAY "]) {
        PPBMessageKind kind = [line hasPrefix:@"PPB:ERR "] ? PPBMessageError :
                              [line hasPrefix:@"PPB:INFO "] ? PPBMessageInfo : PPBMessagePlaying;
        NSString *text = trim ([line substringFromIndex:[line rangeOfString:@" "].location + 1]);
        if ([text length] && [delegate respondsToSelector:@selector(engine:message:kind:)])
            [delegate engine:self message:text kind:kind];
    }
    /* A PPB:ASK line that ends (newline, or the next message) was already handled
     * as a prompt while it was open; plain lines are pianobar echoing input. */
}

/* Split the output into lines at \n, \r and ESC[2K, and spot an open prompt (a
 * PPB:ASK with nothing after it yet). */
- (void)processPending {
    const char *bytes = [pending bytes];
    unsigned len = [pending length], start = 0, i = 0;
    while (i < len) {
        unsigned skip = 0;
        if (bytes[i] == '\n' || bytes[i] == '\r') skip = 1;
        else if (bytes[i] == 0x1b && i + 3 < len && bytes[i + 1] == '[' && bytes[i + 2] == '2' && bytes[i + 3] == 'K') skip = 4;
        else if (bytes[i] == 0x1b && i + 3 >= len) break;     /* maybe a split ESC[2K: wait */
        if (skip) {
            if (i > start) [self handleLine:decode (bytes + start, i - start)];
            i += skip;
            start = i;
            promptSeen = NO;
        } else {
            i++;
        }
    }
    [pending replaceBytesInRange:NSMakeRange (0, start) withBytes:NULL length:0];

    if (!promptSeen && [pending length] > 0) {
        NSString *rest = stripEscapes (decode ([pending bytes], [pending length]));
        if ([rest hasPrefix:@"PPB:ASK "] && [rest hasSuffix:@" "]) {
            promptSeen = YES;
            [self handlePrompt:trim ([rest substringFromIndex:8])];
        }
    }
}

- (void)readCompleted:(NSNotification *)note {
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] == 0) {
        /* EOF: everything the engine wrote has been handled */
        sawEOF = YES;
        [self finishIfDone];
        return;
    }
    [pending appendData:data];
    [self processPending];
    [fromEngine readInBackgroundAndNotify];
}

- (void)taskTerminated:(NSNotification *)note {
    exited = YES;
    [self finishIfDone];
}

/* Report the exit only once the task is gone *and* its output is read, so the
 * last events (e.g. a failed login) always arrive before engineDidExit. */
- (void)finishIfDone {
    if (!sawEOF || !exited) return;
    int status = [task terminationStatus];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [password release];
    password = nil;
    [self setPrompt:nil];
    if ([delegate respondsToSelector:@selector(engineDidExit:status:)])
        [delegate engineDidExit:self status:status];
}

@end
