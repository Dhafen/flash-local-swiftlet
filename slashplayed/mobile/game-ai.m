// Experimental opt-in combat assistant. Local Apple Vision + Apple's on-device
// Foundation Models bridge; no frame is stored or uploaded. All actions run on main.
#import <ReplayKit/ReplayKit.h>
#import <Vision/Vision.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#include <stdatomic.h>
#include <stdbool.h>

static atomic_bool sp_p2p_capture_enabled;
static atomic_uint sp_p2p_capture_epoch;
static NSData *sp_p2p_latest_frame;
static NSTimeInterval sp_p2p_latest_at;
static void sp_p2p_enable(BOOL enabled) {
    atomic_fetch_add(&sp_p2p_capture_epoch, 1);
    atomic_store(&sp_p2p_capture_enabled, enabled);
    sp_p2p_latest_frame = nil;
    sp_p2p_latest_at = 0;
}

// State emitted by the game's own read-only addon API. Written and read on main.
static uint8_t sp_ai_game_flags, sp_ai_game_hp, sp_ai_game_target_hp;
static NSTimeInterval sp_ai_game_at, sp_ai_strip_at, sp_ai_packet_at;
static BOOL sp_ai_heartbeat_seen;
static uint8_t sp_ai_heartbeat_seq;
static int sp_ai_payload_status = -1;
static void sp_ai_game_update(const uint8_t *data, size_t length) {
    sp_ai_packet_at = NSProcessInfo.processInfo.systemUptime;
    if (length < 6 || data[0] != 'A' || data[1] != 'I' ||
        !(data[2] & 1) || data[3] > 100 || data[4] > 100) {
        if (sp_ai_payload_status != 0) sp_stub_log("AI telemetry: invalid or missing player state");
        sp_ai_payload_status = 0;
        sp_ai_game_at = 0;
        return;
    }
    if (sp_ai_game_at <= 0 || sp_ai_packet_at - sp_ai_game_at >= 6.0)
        sp_stub_log("AI telemetry: valid game-state payload");
    sp_ai_payload_status = 1;
    sp_ai_game_flags = data[2];
    sp_ai_game_hp = data[3];
    sp_ai_game_target_hp = data[4];
    sp_ai_game_at = NSProcessInfo.processInfo.systemUptime;
}

static void sp_ai_heartbeat(uint8_t seq, const uint8_t *data, size_t length) {
    if (sp_ai_heartbeat_seen && seq == sp_ai_heartbeat_seq) return;
    if (!sp_ai_heartbeat_seen) sp_stub_log("AI telemetry: independent heartbeat detected");
    sp_ai_heartbeat_seen = YES;
    sp_ai_heartbeat_seq = seq;
    sp_ai_game_update(data, length);
}

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL starting;
@property(nonatomic, copy) BOOL (^action)(NSString *, CGPoint, NSTimeInterval);
@property(nonatomic, copy) void (^releaseInput)(void);
@property(nonatomic, copy) void (^status)(NSString *);
- (void)start;
- (void)stop;
- (void)invalidateDecision;
@end

@implementation SPGameAIController {
    BOOL _active, _starting, _stopping, _ownsCapture;
    NSUInteger _run, _captureRun;
    BOOL _busy;
    NSTimeInterval _nextFrame, _lastFrame;
    BOOL _directRulesOnly, _directPending, _directLayaWarmed;
    NSUInteger _directDecisionGeneration;
    NSString *_directCandidate, *_directPlan;
    NSTimeInterval _directNextAction, _directPlanAt;
    BOOL _p2pAvailable, _p2pPending;
    NSTimeInterval _p2pLastUsed, _p2pLastMove;
    NSUInteger _p2pGeneration;
}
- (BOOL)active { return _active; }
- (BOOL)starting { return _starting && _active; }

- (void)invalidateDecision {
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL selector = NSSelectorFromString(@"resetDecision");
    if ([bridge respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
    ++_p2pGeneration;
    // Keep single-flight ownership until the previous callback finishes.
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL reset = NSSelectorFromString(@"resetHistory");
    if ([p2p respondsToSelector:reset]) ((void (*)(id, SEL))objc_msgSend)(p2p, reset);
}

// Summarize the full video frame (BGRA or NV12) without storing any frame.
// The coarse grid is used only for change detection, never semantic claims.
static NSArray<NSNumber *> *sp_ai_luminance(CVPixelBufferRef buffer) {
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:96];
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return result;
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    BOOL planar = CVPixelBufferIsPlanar(buffer) && CVPixelBufferGetPlaneCount(buffer) > 0 &&
        (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    BOOL bgra = format == kCVPixelFormatType_32BGRA;
    size_t width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer);
    size_t height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer);
    size_t stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer);
    const uint8_t *base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer);
    if ((planar || bgra) && base && width && height && stride >= width * (bgra ? 4 : 1)) {
        for (size_t y = 0; y < 8; ++y) for (size_t x = 0; x < 12; ++x) {
            const uint8_t *p = base + ((2*y+1)*height/16)*stride + ((2*x+1)*width/24)*(bgra ? 4 : 1);
            unsigned value = planar ? p[0] : (29*p[0] + 150*p[1] + 77*p[2])/256;
            [result addObject:@(value / 16)];
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    return result;
}

- (void)haltCapture {
    if (!_ownsCapture || _stopping) return;
    _ownsCapture = NO;
    _stopping = YES;
    __weak SPGameAIController *weak = self;
    [RPScreenRecorder.sharedRecorder stopCaptureWithHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (strong) strong->_stopping = NO;
        });
    }];
}
- (void)stop {
    if (!_active) return;
    _active = NO;
    sp_p2p_enable(NO);
    ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
    ++_directDecisionGeneration;
    _directPending = NO;
    if (self.releaseInput) self.releaseInput();
    [self invalidateDecision];
    [self haltCapture];
    if (self.status) self.status(@"AI OFF");
}
- (void)fail:(NSString *)reason {
    [self stop];
    if (self.status) self.status(reason);
}
- (void)finish:(NSString *)answer points:(NSArray<NSValue *> *)points labels:(NSArray<NSString *> *)labels observation:(NSString *)observation captured:(NSTimeInterval)captured run:(NSUInteger)run {
    if (!_active || _run != run) return;
    if ([answer isEqualToString:@"ERROR"] || [answer isEqualToString:@"UNAVAILABLE"]) {
        [self fail:@"AI MODEL!"];
        return;
    }
    NSString *display = @"AI WAIT";
    // Don't execute a decision made on an old frame.
    if (self.action && NSProcessInfo.processInfo.systemUptime - captured <= 8.0) {
        NSSet *keys = [NSSet setWithArray:@[@"ATTACK", @"TARGET", @"FORWARD", @"BACK", @"LEFT", @"RIGHT"]];
        BOOL executed = NO;
        if ([keys containsObject:answer]) executed = self.action(answer, CGPointZero, captured);
        else {
            NSArray<NSString *> *parts = [answer componentsSeparatedByString:@" "];
            if (parts.count == 2 && ([parts[0] isEqualToString:@"CLICK"] || [parts[0] isEqualToString:@"INTERACT"])) {
                NSInteger index = parts[1].integerValue;
                if (index >= 1 && index <= (NSInteger)points.count && index <= (NSInteger)labels.count) {
                    NSString *label = labels[index - 1].lowercaseString;
                    // Restrict left clicks to descriptive quest/loot controls; never arbitrary UI.
                    NSSet *allowed = [NSSet setWithArray:@[@"accept", @"accept quest", @"complete quest", @"continue", @"loot", @"loot all", @"take all"]];
                    BOOL allowedClick = [parts[0] isEqualToString:@"CLICK"] && [allowed containsObject:label];
                    BOOL blocked = [label containsString:@"trade"] || [label containsString:@"buy"] ||
                        [label containsString:@"sell"] || [label containsString:@"delete"] ||
                        [label containsString:@"settings"] || [label containsString:@"password"] ||
                        [label containsString:@"auction"] || [label containsString:@"mail"] ||
                        [label containsString:@"logout"] || [label containsString:@"exit"];
                    if (!blocked && (allowedClick || [parts[0] isEqualToString:@"INTERACT"]))
                        executed = self.action(parts[0], points[index - 1].CGPointValue, captured);
                }
            }
        }
        if (executed) {
            display = [@"AI " stringByAppendingString:[[answer componentsSeparatedByString:@" "] firstObject]];
            Class bridge = NSClassFromString(@"SPGameAIModel");
            SEL record = NSSelectorFromString(@"recordAction:observation:");
            if ([bridge respondsToSelector:record])
                ((void (*)(id, SEL, NSString *, NSString *))objc_msgSend)(bridge, record, answer, observation);
        }
    }
    if (NSProcessInfo.processInfo.systemUptime - captured > 8.0) display = @"AI SLOW";
    if (self.status) self.status(display);
    @synchronized(self) {
        if (_captureRun == run) {
            _busy = NO;
            _nextFrame = NSProcessInfo.processInfo.systemUptime + 1.5;
        }
    }
}
- (void)inspect:(CMSampleBufferRef)sample run:(NSUInteger)run {
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    @synchronized(self) {
        if (_captureRun != run) return;
        _lastFrame = NSProcessInfo.processInfo.systemUptime;
        if (_busy || _lastFrame < _nextFrame) return;
        _busy = YES;
    }
    NSTimeInterval captured = NSProcessInfo.processInfo.systemUptime;
    NSNumber *orientation = (__bridge NSNumber *)CMGetAttachment(sample, (__bridge CFStringRef)RPVideoSampleOrientationKey, NULL);
    NSInteger value = orientation ? orientation.integerValue : kCGImagePropertyOrientationUp;
    CGImagePropertyOrientation exif = (value >= 1 && value <= 8) ? (CGImagePropertyOrientation)value : kCGImagePropertyOrientationUp;
    // ReplayKit delivers buffers on its capture queue; OCR remains off main.
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelFast;
    request.usesLanguageCorrection = NO;
    request.regionOfInterest = CGRectMake(0, 0.24, 1, 0.76); // omit the chat end of the screen
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:buffer orientation:exif options:@{}];
    NSError *error = nil;
    BOOL ok = [handler performRequests:@[request] error:&error];
    NSMutableArray<NSDictionary *> *observedLabels = [NSMutableArray array];
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    if (ok) for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text.confidence < 0.45 || text.string.length < 2) continue;
        CGRect rect = observation.boundingBox;
        CGPoint point = CGPointMake(CGRectGetMidX(rect), 1 - CGRectGetMidY(rect));
        [points addObject:[NSValue valueWithCGPoint:point]];
        [labels addObject:[text.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        [observedLabels addObject:@{@"id": @(points.count), @"x": @(point.x), @"y": @(point.y),
            @"text": [text.string substringToIndex:MIN(text.string.length, 120)]}];
        if (observedLabels.count >= 25) break;
    }
    // Whole-image classification is generic, not a WoW-trained detector.
    VNClassifyImageRequest *classification = [VNClassifyImageRequest new];
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if ([handler performRequests:@[classification] error:NULL]) {
        for (VNClassificationObservation *label in classification.results) {
            if (label.confidence < 0.08) continue;
            [tags addObject:label.identifier];
            if (tags.count >= 5) break;
        }
    }
    NSDictionary *payload = @{@"labels": observedLabels, @"visualTags": tags, @"luminance": sp_ai_luminance(buffer)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSString *observation = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || self->_run != run) return;
        if (!ok || !observation.length || !points.count) {
            [self finish:@"WAIT" points:points labels:labels observation:observation captured:captured run:run];
            if (self.status) self.status(@"AI NO TEXT");
            return;
        }
        if (self.status) self.status(@"AI THINK");
        Class bridge = NSClassFromString(@"SPGameAIModel");
        SEL selector = NSSelectorFromString(@"decide:completion:");
        if (![bridge respondsToSelector:selector]) { [self fail:@"AI MODEL!"]; return; }
        void (^completion)(NSString *) = ^(NSString *answer) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finish:answer points:points labels:labels observation:observation captured:captured run:run]; });
        };
        ((void (*)(id, SEL, NSString *, void (^)(NSString *)))objc_msgSend)(bridge, selector, observation, completion);
    });
}
- (void)watchCapture:(NSUInteger)run {
    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SPGameAIController *strong = weak;
        if (!strong || !strong->_active || strong->_run != run) return;
        NSTimeInterval elapsed;
        @synchronized(strong) { elapsed = NSProcessInfo.processInfo.systemUptime - strong->_lastFrame; }
        if (elapsed > 15.0) { [strong fail:@"AI NO VID"]; return; }
        [strong watchCapture:run];
    });
}
- (void)tryP2P:(NSUInteger)run {
    if (!_p2pAvailable || _p2pPending || !sp_p2p_latest_frame ||
        sp_p2p_latest_at <= _p2pLastUsed ||
        NSProcessInfo.processInfo.systemUptime - sp_p2p_latest_at > 3.0) return;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL pred = NSSelectorFromString(@"predictFrame:completion:");
    if (![p2p respondsToSelector:pred]) return;
    NSUInteger gen = _p2pGeneration;
    NSTimeInterval captured = sp_p2p_latest_at;
    _p2pLastUsed = captured;
    _p2pPending = YES;
    __weak SPGameAIController *weak = self;
    void (^completion)(NSString *) = ^(NSString *answer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (!strong) return;
            strong->_p2pPending = NO;
            if (!strong->_active || strong->_run != run || strong->_p2pGeneration != gen) return;
            if ([answer hasPrefix:@"ERR:"]) {
                strong->_p2pAvailable = NO;
                sp_p2p_enable(NO);
                if (strong.status) strong.status(@"P2P ERR");
                return;
            }
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            unsigned f = sp_ai_game_flags;
            // Only seek in a known, living unmounted state with no selected living hostile.
            BOOL seeking = !(f & (2|32|64)) && sp_ai_game_hp >= 35 &&
                (!(f & 4) || (f & 16) || !(f & 8));
            BOOL allowed = strong->_directRulesOnly || [strong->_directPlan isEqualToString:@"TARGET"];
            if (!seeking || !allowed || sp_ai_game_at <= 0 || now-sp_ai_game_at >= 6.0 ||
                now-captured > 3.0 || now-strong->_p2pLastMove < 0.8) return;
            if (![@[@"FORWARD",@"BACK",@"LEFT",@"RIGHT"] containsObject:answer]) return;
            if (strong.action && strong.action(answer, CGPointZero, captured)) {
                strong->_p2pLastMove = now;
                SEL record = NSSelectorFromString(@"recordMove:");
                if ([p2p respondsToSelector:record])
                    ((void (*)(id,SEL,NSString *))objc_msgSend)(p2p,record,answer);
                if (strong.status) strong.status(@"P2P MOVE");
            }
        });
    };
    ((void (*)(id,SEL,NSData *,void (^)(NSString *)))objc_msgSend)(p2p,pred,sp_p2p_latest_frame,completion);
}
- (void)pollDirect:(NSUInteger)run {
    if (!_active || _run != run) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSString *candidate = nil;
    NSString *display = @"AI DATA";
    if (sp_ai_strip_at <= 0 || now - sp_ai_strip_at >= 6.0) display = @"AI STRIP";
    else if (sp_ai_packet_at <= 0 || now - sp_ai_packet_at >= 6.0) display = @"AI SYNC";
    if (sp_ai_game_at > 0 && now - sp_ai_game_at < 6.0) {
        unsigned f = sp_ai_game_flags;
        if ((f & 2) || (f & 64) || sp_ai_game_hp < 35) display = @"AI REST";
        else if (!(f & 4) || (f & 16)) candidate = @"TARGET";
        else if ((f & 8) && sp_ai_game_target_hp > 0) candidate = @"ATTACK";
        else candidate = @"TARGET"; // a friendly NPC is not attackable; seek a hostile target
    }
    if (!candidate) {
        if (_directCandidate) { ++_directDecisionGeneration; _directPending = NO; }
        _directCandidate = _directPlan = nil;
    } else {
        if (![_directCandidate isEqualToString:candidate]) {
            ++_directDecisionGeneration;
            _directCandidate = candidate;
            _directPlan = nil;
            _directPending = NO;
        }
        if (!_directRulesOnly && !_directPending &&
            (!_directPlan || now - _directPlanAt > 12.0)) {
            Class bridge = NSClassFromString(@"SPGameAIModel");
            SEL selector = NSSelectorFromString(@"decideGameState:candidate:completion:");
            if (![bridge respondsToSelector:selector]) _directRulesOnly = YES;
            else {
                _directPending = YES;
                NSUInteger gen = ++_directDecisionGeneration;
                NSString *hp = sp_ai_game_hp < 40 ? @"low" : sp_ai_game_hp < 75 ? @"medium" : @"high";
                NSString *targetHP = sp_ai_game_target_hp < 35 ? @"low" : sp_ai_game_target_hp < 75 ? @"medium" : @"high";
                NSString *state = [NSString stringWithFormat:@"%@:%@:%@:%@", candidate, hp,
                    (sp_ai_game_flags & 32) ? @"combat" : @"peace", targetHP];
                __weak SPGameAIController *weak = self;
                void (^completion)(NSString *) = ^(NSString *answer) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        SPGameAIController *strong = weak;
                        if (!strong || !strong->_active || strong->_run != run || strong->_directDecisionGeneration != gen) return;
                        strong->_directPending = NO;
                        strong->_directLayaWarmed = YES;
                        strong->_directPlanAt = NSProcessInfo.processInfo.systemUptime;
                        if ([answer hasPrefix:@"ERR:"]) {
                            sp_stub_log([[@"AI model: " stringByAppendingString:answer] UTF8String]);
                            strong->_directRulesOnly = YES;
                        } else strong->_directPlan = [answer isEqualToString:candidate] ? candidate : @"WAIT";
                    });
                };
                ((void (*)(id, SEL, NSString *, NSString *, void (^)(NSString *)))objc_msgSend)(bridge, selector, state, candidate, completion);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((_directLayaWarmed ? 6 : 90) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    SPGameAIController *strong = weak;
                    if (!strong || !strong->_active || strong->_run != run || strong->_directDecisionGeneration != gen || !strong->_directPending) return;
                    ++strong->_directDecisionGeneration;
                    strong->_directPending = NO;
                    strong->_directRulesOnly = YES;
                    sp_stub_log("AI model: response timeout; using deterministic game-state rules");
                });
            }
        }
        BOOL authorized = _directRulesOnly || [_directPlan isEqualToString:candidate];
        display = _directPending ? (_directLayaWarmed ? @"LAYA THINK" : @"LAYA LOAD") : (_directRulesOnly ? @"RULE WAIT" : @"LAYA WAIT");
        if (authorized && [candidate isEqualToString:@"TARGET"] && !(sp_ai_game_flags & 32))
            [self tryP2P:run];
        if (authorized && now >= _directNextAction && self.action) {
            BOOL sent = self.action(candidate, CGPointZero, sp_ai_game_at);
            if (sent) {
                _directNextAction = now + ([candidate isEqualToString:@"TARGET"] ? 3.0 : 0.85);
                display = [NSString stringWithFormat:@"%@ %@", _directRulesOnly ? @"RULE" : @"LAYA",
                    [candidate isEqualToString:@"ATTACK"] ? @"F12" : @"TAB"];
            } else display = @"AI INPUT";
        }
    }
    if (_p2pAvailable && now-_p2pLastMove < 1.2) display = @"P2P MOVE";
    if (self.status) self.status(display);
    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weak pollDirect:run];
    });
}
- (void)start {
    if (_active || _starting || _stopping) return;
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL ready = NSSelectorFromString(@"layaReady");
    if (![bridge respondsToSelector:ready] || !((BOOL (*)(id, SEL))objc_msgSend)(bridge, ready)) {
        if (self.status) self.status(@"LAYA FILE");
        return;
    }
    _directLayaWarmed = NO;
    _directRulesOnly = NO;
    _directCandidate = _directPlan = nil;
    _directPending = NO;
    _directNextAction = 0;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL available = NSSelectorFromString(@"available");
    _p2pAvailable = [p2p respondsToSelector:available] && ((BOOL (*)(id,SEL))objc_msgSend)(p2p,available);
    _p2pLastUsed = _p2pLastMove = 0;
    [self invalidateDecision];
    sp_p2p_enable(_p2pAvailable);
    _active = YES;
    NSUInteger run = ++_run;
    if (self.status) self.status(@"AI ON");
    [self pollDirect:run];
}

// Keep the earlier screen-based experiment available in source for later testing.
- (void)startScreen {
    if (_active || _starting || _stopping) return;
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL ready = NSSelectorFromString(@"ready");
    RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
    if (![bridge respondsToSelector:ready] || !((BOOL (*)(id, SEL))objc_msgSend)(bridge, ready)) {
        if (self.status) self.status(@"AI MODEL!");
        return;
    }
    if (!recorder.isAvailable || recorder.isRecording) {
        if (self.status) self.status(@"AI CAP!");
        return;
    }
    [self invalidateDecision];
    _active = YES;
    _starting = YES;
    NSUInteger run = ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
    if (self.status) self.status(@"AI ON…");
    recorder.microphoneEnabled = NO;
    __weak SPGameAIController *weak = self;
    [recorder startCaptureWithHandler:^(CMSampleBufferRef sample, RPSampleBufferType type, NSError *error) {
        SPGameAIController *strong = weak;
        if (!strong) return;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strong->_active && strong->_run == run) [strong fail:@"AI CAP!"];
            });
            return;
        }
        if (type == RPSampleBufferTypeVideo && sample) [strong inspect:sample run:run];
    } completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (!strong) return;
            strong->_starting = NO;
            if (error) {
                if (strong->_active && strong->_run == run) [strong fail:@"AI CAP!"];
                return;
            }
            strong->_ownsCapture = YES;
            if (!strong->_active || strong->_run != run) { [strong haltCapture]; return; }
            @synchronized(strong) {
                strong->_captureRun = run;
                strong->_nextFrame = 0;
                strong->_lastFrame = NSProcessInfo.processInfo.systemUptime;
            }
            if (strong.status) strong.status(@"AI VIDEO");
            [strong watchCapture:run];
        });
    }];
    // No session timeout: the same button toggles off. Lifecycle/errors still fail closed.
}
@end
