/* enginetest: drives PPBEngine against test/fake-pianobar, which plays pianobar's
 * side of a session (login, station prompt, events, time, a one-key answer, a
 * typed answer, a cancelled prompt, quit) and checks every answer it receives.
 * This side checks what PPBEngine reported. Exit 0 = both sides agree. */
#import <Cocoa/Cocoa.h>
#import "PPBEngine.h"

@interface Driver : NSObject {
@public
    PPBEngine *engine;
    NSMutableArray *log;          /* what the delegate saw, in order */
    int ticks, lastElapsed, lastTotal, exitStatus;
    BOOL done;
    NSString *phase;
}
@end

@implementation Driver

- (void)note:(NSString *)s { [log addObject:s]; printf ("  %s\n", [s UTF8String]); }

- (void)engine:(PPBEngine *)e event:(NSString *)type info:(NSDictionary *)info {
    [self note:[NSString stringWithFormat:@"event %@ (%d keys)", type, (int) [info count]]];
    if ([type isEqualToString:@"songstart"])
        [self note:[NSString stringWithFormat:@"up next: %@ by %@",
                    [info objectForKey:@"titleNext0"], [info objectForKey:@"artistNext0"]]];
    if ([type isEqualToString:@"stationrename"])
        [self note:[NSString stringWithFormat:@"stations now: %@", [info objectForKey:@"station0"]]];
}

- (void)engine:(PPBEngine *)e elapsed:(int)el total:(int)tot {
    ticks++;
    lastElapsed = el; lastTotal = tot;
    [self note:[NSString stringWithFormat:@"time %d/%d", el, tot]];
    /* the main loop is running again: start the next step */
    if (el == 2) [engine sendKeys:@"b"];
    if (el == 3) [engine sendKeys:@"r"];
    if (el == 4) [engine sendKeys:@"h"];
    if (el == 5) [engine sendKeys:@"q"];
}

- (void)engine:(PPBEngine *)e prompt:(NSString *)p {
    [self note:[NSString stringWithFormat:@"prompt \"%@\"", p]];
    /* while a prompt is open, main-loop keys must be refused */
    if ([e sendKeys:@"x"]) [self note:@"ERROR: sendKeys accepted during a prompt"];
    if ([p hasPrefix:@"Select station"]) [e selectStationAtIndex:1];
    else if ([p hasPrefix:@"Bookmark"]) [e answerKey:@"s"];
    else if ([p hasPrefix:@"New name"]) [e answerLine:@"Jazz Mix"];
    else if ([p hasPrefix:@"Select song"]) [e cancelPrompt];
    else [self note:@"ERROR: unexpected prompt"];
}

- (void)engine:(PPBEngine *)e listItem:(NSString *)item {
    [self note:[NSString stringWithFormat:@"list \"%@\"", item]];
}

- (void)engine:(PPBEngine *)e message:(NSString *)text kind:(PPBMessageKind)kind {
    [self note:[NSString stringWithFormat:@"%@ \"%@\"",
                kind == PPBMessageError ? @"error" : kind == PPBMessageInfo ? @"info" : @"playing", text]];
}

- (void)engineDidExit:(PPBEngine *)e status:(int)status {
    exitStatus = status;
    [self note:[NSString stringWithFormat:@"exit %d", status]];
    done = YES;
}

@end

static BOOL has (NSArray *log, NSString *s) {
    return [log containsObject:s];
}

int main (int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (argc < 3) { fprintf (stderr, "usage: enginetest FAKE SUPPORTDIR\n"); return 2; }
    setenv ("PPB_ENGINE", argv[1], 1);
    Driver *d = [[Driver alloc] init];
    d->log = [[NSMutableArray alloc] init];
    d->engine = [[PPBEngine alloc] initWithDelegate:d
                                   supportDirectory:[NSString stringWithUTF8String:argv[2]]];
    NSString *err = nil;
    if (![d->engine startWithUser:@"nobody@example.invalid" password:@"secret pass"
                          quality:@"high" error:&err]) {
        printf ("FAIL: start: %s\n", [err UTF8String]);
        return 1;
    }
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!d->done && [until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    NSArray *log = d->log;
    NSString *checks[] = {
        @"info \"Login... Ok.\"",
        @"event userlogin (4 keys)",
        @"event usergetstations (5 keys)",
        @"prompt \"Select station:\"",
        @"playing \"Station \"Rock Radio\" (123)\"",
        @"up next: Song B by Artist B",
        @"time 2/180",
        @"prompt \"Bookmark [s]ong or [a]rtist?\"",
        @"info \"Bookmarking song... Ok.\"",
        @"prompt \"New name:\"",
        @"info \"Renaming station... Ok.\"",
        @"stations now: Jazz Mix",
        [NSString stringWithFormat:@"list \"%@\"", [NSString stringWithUTF8String:" 0) Artist A - Song A \xe2\x99\xa5"]],
        @"prompt \"Select song:\"",
        @"time 5/180",
        @"exit 0",
    };
    int fail = 0;
    unsigned i;
    for (i = 0; i < sizeof (checks) / sizeof (*checks); i++) {
        if (!has (log, checks[i])) { printf ("FAIL: missing: %s\n", [checks[i] UTF8String]); fail++; }
    }
    for (i = 0; i < [log count]; i++)
        if ([[log objectAtIndex:i] hasPrefix:@"ERROR"]) { printf ("FAIL: %s\n", [[log objectAtIndex:i] UTF8String]); fail++; }
    if (!d->done) { printf ("FAIL: engine never exited\n"); fail++; }
    printf ("%s\n", fail ? "FAILED" : "PASS");
    [pool release];
    return fail ? 1 : 0;
}
