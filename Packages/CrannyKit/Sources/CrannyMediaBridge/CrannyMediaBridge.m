// CrannyMediaBridge v3 — Cranny's media helper (ARCHITECTURE.md §6.3), R2's verified bridge. Owned by the
// Media package; the Swift client is CrannyMedia/Providers (BridgeConnection, BridgeMessage).
// Original code (MIT, Cranny). Technique credit: ungive/mediaremote-adapter
// (BSD-3) documented that /usr/bin/perl (identity com.apple.perl*) is admitted
// by mediaremoted and can load a custom library via DynaLoader.
//
// Process model: ONE long-lived /usr/bin/perl child per Cranny instance.
//   stdout  newline-delimited JSON events:
//           {"t":"hello","v":1,"pid":N}
//           {"t":"state", ...}            (full snapshot, de-duplicated: not re-sent when identical, or when it
//                                         only re-anchors elapsed/timestamp to a position within 50 ms)
//           {"t":"artwork","itemID":..,"mime":..,"data":base64}  (only on change; artwork over
//                                                     1 MB is re-encoded as a 1024-px JPEG, or skipped)
//           {"t":"ack"|"error"|"pong", ...}           (exactly one ack or error per cmd/seek/shuffle/repeat line)
//   stdin   one command per line:
//           cmd <0-13> [expectPID] | seek <seconds> [expectPID]
//           shuffle <1-3> | repeat <1-3> | refresh [state] | ping | quit
//           ("refresh" re-sends the state and the artwork, "refresh state" only the state)
//   lifetime: exits on stdin EOF, SIGPIPE, or when the host process exits (re-parented to launchd).
//           Event-driven only: no periodic timer, no polling (the debounce is one-shot per notification).
//   images:  Foundation and ImageIO only. AppKit (≈ 40 more images) is loaded only for the rare session whose
//           MediaRemote client names no bundle (NSRunningApplication, `bundleIDOfProcess`).
//
// Build (arm64 + x86_64, ad-hoc signed by the linker on arm64):
//   clang -dynamiclib -fobjc-arc -fmodules -fvisibility=hidden -arch arm64 -arch x86_64 \
//     -mmacosx-version-min=14.0 -framework Foundation -framework ImageIO \
//     -o libCrannyMediaBridge.dylib CrannyMediaBridge.m
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

#if !__has_feature(objc_arc)
#error "CrannyMediaBridge must be compiled with -fobjc-arc"
#endif

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(uint32_t, NSDictionary *);
typedef void (*SetDoubleFn)(double);
typedef void (*SetIntFn)(int);

static struct {
    GetInfoFn info; GetBoolFn playing; GetPIDFn pid; GetClientFn client;
    RegisterFn reg; SendFn send; SetDoubleFn seek; SetIntFn shuffle; SetIntFn repeat;
} MR;

static dispatch_queue_t gQ;          // all MediaRemote calls + state on one serial queue
static dispatch_source_t gDebounce;  // trailing debounce for notification bursts
static NSString *gLastState;         // the last state line sent: identical snapshots are not re-sent
static NSString *gLastTimeline;      // ... that state without its position anchor (elapsed, timestamp)
static double gLastElapsed, gLastTimestamp;  // ... and the anchor
static BOOL gLastAnchored;           // ... which had a timestamp (comparable by position)
static BOOL gAfterCommand;           // a command or seek was delivered: the next state goes out even if it only
                                     // re-anchors, because it confirms or undoes what Cranny showed at once
static NSString *gLastArtKey;        // artwork is re-sent only when this changes

// One line: the JSON and its newline under stdout's lock, so lines stay atomic for the reader (`hello` is written
// on the main thread while gQ may already answer a `ping`). No copy of the JSON to append the newline.
static void writeLine(NSData *json) {
    flockfile(stdout);
    fwrite(json.bytes, 1, json.length, stdout);
    putc_unlocked('\n', stdout);
    fflush(stdout);
    funlockfile(stdout);
}

// Slashes stay unescaped: JSON does not need `\/`, and base64 artwork is one sixty-fourth slashes.
static void emit(NSDictionary *obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingWithoutEscapingSlashes error:nil];
    if (d) writeLine(d);
}

// JSON-safe scalar: strings, finite numbers, dates (as epoch seconds).
// Live streams report Duration = +inf, which NSJSONSerialization rejects.
static id plain(id v) {
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) {
        double x = [(NSNumber *)v doubleValue];
        return isfinite(x) ? v : nil;
    }
    if ([v isKindOfClass:NSDate.class]) return @([(NSDate *)v timeIntervalSince1970]);
    return nil;
}

static NSString *K(NSString *suffix) { return [@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix]; }

// The bundle id of `pid`'s app as NSRunningApplication reports it: only for a MediaRemote client that names none.
// AppKit is loaded the first time (on the main thread, which runs the run loop), so the resident helper does not map
// AppKit and the ≈ 40 images it pulls in for a fallback that most sessions never need.
@protocol CrannyRunningApplicationClass
+ (id)runningApplicationWithProcessIdentifier:(pid_t)pid;
@end

static NSString *bundleIDOfProcess(pid_t pid) {
    static Class runningApplication;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^load)(void) = ^{ dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY | RTLD_LOCAL); };
        if (pthread_main_np()) load(); else dispatch_sync(dispatch_get_main_queue(), load);
        runningApplication = NSClassFromString(@"NSRunningApplication");
    });
    if (!runningApplication) return nil;
    id app = [(Class<CrannyRunningApplicationClass>)runningApplication runningApplicationWithProcessIdentifier:pid];
    id bundleID = [app valueForKey:@"bundleIdentifier"];
    return [bundleID isKindOfClass:NSString.class] ? bundleID : nil;
}

// MediaRemote's info keys of the state line (out key → kMRMediaRemoteNowPlayingInfo<suffix>), built once.
static NSDictionary<NSString *, NSString *> *stateKeys(void) {
    static NSDictionary<NSString *, NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *suffixes = @{ @"title": @"Title", @"artist": @"Artist", @"album": @"Album",
                                    @"duration": @"Duration", @"elapsed": @"ElapsedTime",
                                    @"timestamp": @"Timestamp", @"rate": @"PlaybackRate",
                                    @"itemID": @"ContentItemIdentifier", @"artworkID": @"ArtworkIdentifier",
                                    @"shuffle": @"ShuffleMode", @"repeat": @"RepeatMode",
                                    @"mediaType": @"MediaType", @"isMusicApp": @"IsMusicApp",
                                    @"prohibitsSkip": @"ProhibitsSkip", @"isAd": @"IsAdvertisement" };
        NSMutableDictionary *full = [NSMutableDictionary dictionaryWithCapacity:suffixes.count];
        for (NSString *outKey in suffixes) full[outKey] = K(suffixes[outKey]);
        keys = [full copy];
    });
    return keys;
}

// Re-anchoring: a state equal to the last one sent except for elapsed/timestamp that predict the same position is
// not sent (players re-publish their info when late artwork arrives, while buffering, some every few seconds; Cranny
// would parse it and change nothing). Cranny anchors a state without a timestamp at its arrival, so only states
// with one are compared by position; the position is Cranny's (`NowPlaying.position(at:)`).
static const double kSamePosition = 0.05;

static BOOL anchorOf(NSDictionary *s, double *elapsed, double *timestamp) {
    *elapsed = MAX([s[@"elapsed"] doubleValue], 0);
    *timestamp = [s[@"timestamp"] doubleValue];
    return *timestamp > 0;
}

static double positionAt(NSDictionary *s, double elapsed, double timestamp, double now) {
    BOOL playing = [s[@"playing"] boolValue];
    double rate = s[@"rate"] ? [s[@"rate"] doubleValue] : (playing ? 1 : 0);
    double p = playing ? elapsed + (now - timestamp) * (rate > 0 ? rate : 1) : elapsed;
    double duration = [s[@"duration"] doubleValue];
    if (duration > 0) p = MIN(p, duration);
    return MAX(p, 0);
}

static NSString *sortedJSON(NSDictionary *obj, NSData **data) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) *data = json;
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

// Sends the state `s` unless it is the last one again, or only re-anchors it (see `kSamePosition`; not right after a
// command, `gAfterCommand`).
static void sendState(NSDictionary *s) {
    NSData *json = nil;
    NSString *str = sortedJSON(s, &json);
    if (!str || [str isEqualToString:gLastState]) return;
    NSMutableDictionary *timeline = [s mutableCopy];
    [timeline removeObjectsForKeys:@[ @"elapsed", @"timestamp" ]];
    NSString *timelineKey = sortedJSON(timeline, NULL);
    double elapsed, timestamp;
    BOOL anchored = anchorOf(s, &elapsed, &timestamp);
    if (!gAfterCommand && anchored && gLastAnchored && timelineKey && [timelineKey isEqualToString:gLastTimeline]) {
        double now = NSDate.date.timeIntervalSince1970;
        if (fabs(positionAt(s, elapsed, timestamp, now) - positionAt(s, gLastElapsed, gLastTimestamp, now)) < kSamePosition) return;
    }
    gAfterCommand = NO;
    gLastState = str;
    gLastTimeline = timelineKey;
    gLastElapsed = elapsed;
    gLastTimestamp = timestamp;
    gLastAnchored = anchored;
    writeLine(json);
}

// Artwork travels base64-encoded in one JSON line, and Cranny drops lines over 8 MB. Large artwork (3000-px
// podcast PNGs) is re-encoded here as a 1024-px JPEG; Cranny shows at most 512 px. nil = could not shrink it.
// 4 MB of JPEG is 5.4 MB of base64, well under Cranny's limit.
enum { kMaxArtworkBytes = 1 << 20, kMaxShrunkBytes = 4 << 20, kArtworkMaxPixels = 1024 };

static NSData *shrunkArtwork(NSData *data) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *options = @{ (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                               (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(kArtworkMaxPixels),
                               (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) return nil;
    NSMutableData *jpeg = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, NULL);
    BOOL ok = NO;
    if (destination) {
        NSDictionary *properties = @{ (__bridge id)kCGImageDestinationLossyCompressionQuality: @0.85 };
        CGImageDestinationAddImage(destination, thumbnail, (__bridge CFDictionaryRef)properties);
        ok = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(thumbnail);
    return ok && jpeg.length > 0 && jpeg.length <= kMaxShrunkBytes ? jpeg : nil;
}

static void snapshot(void) {
    MR.pid(gQ, ^(int pid) {
      MR.playing(gQ, ^(Boolean isPlaying) {
        MR.client(gQ, ^(id client) {
          MR.info(gQ, ^(NSDictionary *info) {
            NSMutableDictionary *s = [@{ @"t": @"state", @"playing": isPlaying ? @YES : @NO, @"pid": @(pid) } mutableCopy];
            if (client) {
                for (NSString *sel in @[ @"bundleIdentifier", @"parentApplicationBundleIdentifier", @"displayName" ]) {
                    if ([client respondsToSelector:NSSelectorFromString(sel)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        id v = [client performSelector:NSSelectorFromString(sel)];
#pragma clang diagnostic pop
                        if ([v isKindOfClass:NSString.class] && [v length]) s[sel] = v;
                    }
                }
            }
            if (!s[@"bundleIdentifier"] && pid > 0) {
                NSString *bundleID = bundleIDOfProcess(pid);
                if (bundleID) s[@"bundleIdentifier"] = bundleID;
            }
            NSDictionary<NSString *, NSString *> *keys = stateKeys();
            for (NSString *outKey in keys) {
                id v = plain(info[keys[outKey]]);
                if (v) s[outKey] = v;
            }
            sendState(s);

            NSData *art = info[K(@"ArtworkData")];
            if ([art isKindOfClass:NSData.class] && art.length > 0) {
                NSString *artKey = [NSString stringWithFormat:@"%@|%@|%lu", s[@"itemID"], s[@"artworkID"], (unsigned long)art.length];
                if (![artKey isEqualToString:gLastArtKey]) {
                    gLastArtKey = artKey;
                    id mime = plain(info[K(@"ArtworkMIMEType")]) ?: @"";
                    if (art.length > kMaxArtworkBytes) {
                        art = shrunkArtwork(art);
                        mime = @"image/jpeg";
                    }
                    if (art) {
                        emit(@{ @"t": @"artwork", @"itemID": s[@"itemID"] ?: @"", @"mime": mime,
                                @"data": [art base64EncodedStringWithOptions:0] });
                    } else {
                        fprintf(stderr, "artwork could not be shrunk; skipped\n");
                    }
                }
            }
          });
        });
      });
    });
}

static void scheduleSnapshot(void) {
    dispatch_source_set_timer(gDebounce, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                              DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
}

// Runs `action` only if the elected now-playing PID matches `expect` (0 = always).
static void guarded(int expect, void (^action)(void)) {
    if (!expect) { action(); return; }
    MR.pid(gQ, ^(int pid) {
        if (pid != expect) { emit(@{ @"t": @"ack", @"ok": @NO, @"why": @"pid mismatch", @"nowPlayingPID": @(pid) }); return; }
        action();
    });
}

static void handleLine(NSString *line) {
    NSArray<NSString *> *p = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *verb = p.firstObject;
    int arg2 = p.count >= 3 ? p[2].intValue : 0;
    if ([verb isEqualToString:@"quit"]) exit(0);
    if ([verb isEqualToString:@"ping"]) { emit(@{ @"t": @"pong" }); return; }
    if ([verb isEqualToString:@"refresh"]) {
        // "refresh state" (Cranny's check after an unconfirmed command) leaves the artwork alone.
        gLastState = nil;
        gLastTimeline = nil;
        if (!(p.count >= 2 && [p[1] isEqualToString:@"state"])) gLastArtKey = nil;
        snapshot();
        return;
    }
    if ([verb isEqualToString:@"cmd"] && p.count >= 2) {
        int c = p[1].intValue;
        if (c < 0 || c > 13) { emit(@{ @"t": @"error", @"msg": @"bad command id" }); return; }
        guarded(arg2, ^{
            Boolean ok = MR.send((uint32_t)c, nil);
            if (ok) gAfterCommand = YES;
            emit(@{ @"t": @"ack", @"cmd": @(c), @"ok": ok ? @YES : @NO });
        });
        return;
    }
    if ([verb isEqualToString:@"seek"] && p.count >= 2 && MR.seek) {
        double sec = p[1].doubleValue;
        if (!(sec >= 0) || !isfinite(sec)) { emit(@{ @"t": @"error", @"msg": @"bad position" }); return; }
        guarded(arg2, ^{ MR.seek(sec); gAfterCommand = YES; emit(@{ @"t": @"ack", @"seek": @(sec), @"ok": @YES }); });
        return;
    }
    if (([verb isEqualToString:@"shuffle"] || [verb isEqualToString:@"repeat"]) && p.count >= 2) {
        int m = p[1].intValue;
        SetIntFn fn = [verb isEqualToString:@"shuffle"] ? MR.shuffle : MR.repeat;
        if (!fn || m < 1 || m > 3) { emit(@{ @"t": @"error", @"msg": @"bad mode" }); return; }
        guarded(arg2, ^{ fn(m); emit(@{ @"t": @"ack", verb: @(m), @"ok": @YES }); });
        return;
    }
    emit(@{ @"t": @"error", @"msg": [@"unknown command: " stringByAppendingString:line] });
}

__attribute__((visibility("default")))
void cranny_bridge_main(void) {
    signal(SIGPIPE, SIG_DFL);  // host gone while writing -> terminate quietly
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen MediaRemote failed\n"); exit(10); }
    MR.info = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    MR.playing = (GetBoolFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MR.pid = (GetPIDFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
    MR.client = (GetClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingClient");
    MR.reg = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MR.send = (SendFn)dlsym(h, "MRMediaRemoteSendCommand");
    MR.seek = (SetDoubleFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    MR.shuffle = (SetIntFn)dlsym(h, "MRMediaRemoteSetShuffleMode");
    MR.repeat = (SetIntFn)dlsym(h, "MRMediaRemoteSetRepeatMode");
    if (!MR.info || !MR.playing || !MR.pid || !MR.client || !MR.reg || !MR.send) {
        fprintf(stderr, "MediaRemote symbols missing\n"); exit(11);
    }
    gQ = dispatch_queue_create("cranny.media.bridge", DISPATCH_QUEUE_SERIAL);
    gDebounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQ);
    dispatch_source_set_event_handler(gDebounce, ^{ snapshot(); });
    dispatch_source_set_timer(gDebounce, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(gDebounce);

    for (NSString *name in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification" ]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(__unused NSNotification *n) { scheduleSnapshot(); }];
    }
    MR.reg(gQ);

    // stdin command channel; EOF means the host closed the pipe or died.
    NSMutableData *buf = [NSMutableData data];
    dispatch_source_t in = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, gQ);
    dispatch_source_set_event_handler(in, ^{
        char tmp[4096];
        ssize_t n = read(STDIN_FILENO, tmp, sizeof tmp);
        if (n <= 0) exit(0);
        [buf appendBytes:tmp length:(NSUInteger)n];
        if (buf.length > 65536) exit(12);  // runaway input guard
        for (;;) {
            NSRange r = [buf rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buf.length)];
            if (r.location == NSNotFound) break;
            NSString *line = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, r.location)] encoding:NSUTF8StringEncoding];
            [buf replaceBytesInRange:NSMakeRange(0, r.location + 1) withBytes:NULL length:0];
            line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (line.length) handleLine(line);
        }
    });
    dispatch_resume(in);

    // Belt and braces: if the host is SIGKILLed and stdin somehow stays open (e.g. a leaked
    // descriptor), exit when the host process exits. A kqueue process-exit source, not a timer:
    // the helper lives as long as Cranny and must not wake up while nothing plays (ARCHITECTURE §9.2).
    pid_t host = getppid();
    if (host <= 1) exit(0);  // already re-parented to launchd: the host is gone
    dispatch_source_t hostExit = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)host, DISPATCH_PROC_EXIT, gQ);
    if (hostExit) {
        dispatch_source_set_event_handler(hostExit, ^{ exit(0); });
        dispatch_resume(hostExit);
    }
    // The host may have died between getppid() and arming the source; re-parenting tells.
    if (getppid() != host) exit(0);

    emit(@{ @"t": @"hello", @"v": @1, @"pid": @(getpid()) });
    dispatch_async(gQ, ^{ snapshot(); });
    CFRunLoopRun();  // notifications are delivered via the main run loop
}
