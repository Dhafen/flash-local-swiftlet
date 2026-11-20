// Experimental opt-in combat assistant. Local Apple Vision + Apple's on-device
// Foundation Models bridge; no frame is stored or uploaded. All actions run on main.
#import <ReplayKit/ReplayKit.h>
#import <Vision/Vision.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#include <stdatomic.h>
#include <stdbool.h>
#include "ai-direct.h"

static atomic_bool sp_p2p_capture_enabled;
static atomic_uint sp_p2p_capture_epoch;
static NSData *sp_p2p_latest_frame;
static NSTimeInterval sp_p2p_latest_at;
// Approximate visual change, not proof that the character moved or is safe.
static BOOL sp_p2p_scene_changed(NSData *before, NSData *after) {
    if (before.length != 3*192*192 || after.length != before.length) return NO;
    const uint8_t *a = before.bytes, *b = after.bytes;
    unsigned sum = 0, count = 0;
    for (unsigned c=0;c<3;c++) for (unsigned y=42;y<150;y+=8)
        for (unsigned x=24;x<168;x+=8) {
            unsigned i=c*192*192+y*192+x;
            sum += (unsigned)abs((int)a[i]-(int)b[i]); ++count;
        }
    return count && sum >= count*3;
}
static void sp_p2p_enable(BOOL enabled) {
    if (atomic_load(&sp_p2p_capture_enabled) == enabled) return;
    atomic_fetch_add(&sp_p2p_capture_epoch, 1);
    atomic_store(&sp_p2p_capture_enabled, enabled);
    sp_p2p_latest_frame = nil;
    sp_p2p_latest_at = 0;
}

static SPAIMove sp_ai_move(NSString *move) {
    if ([move isEqualToString:@"FORWARD"]) return SP_MOVE_FORWARD;
    if ([move isEqualToString:@"BACK"]) return SP_MOVE_BACK;
    if ([move isEqualToString:@"LEFT"] || [move isEqualToString:@"STRAFE_LEFT"]) return SP_MOVE_LEFT;
    if ([move isEqualToString:@"RIGHT"] || [move isEqualToString:@"STRAFE_RIGHT"]) return SP_MOVE_RIGHT;
    return SP_MOVE_NONE;
}

// State emitted by the game's own read-only addon API. Written and read on main.
static uint8_t sp_ai_game_flags, sp_ai_game_hp, sp_ai_game_target_hp, sp_ai_game_meta, sp_ai_game_move_keys;
static NSTimeInterval sp_ai_game_at, sp_ai_strip_at, sp_ai_packet_at;
static BOOL sp_ai_heartbeat_seen;
static BOOL sp_ai_health_known(uint8_t value) { return sp_ai_hp_known(value); }
static SPAIDecision sp_ai_current_decision(NSTimeInterval now) {
    return sp_ai_decision(sp_ai_game_at > 0 && now-sp_ai_game_at < 3.0,
        sp_ai_game_flags,sp_ai_game_hp,sp_ai_game_target_hp,sp_ai_game_meta);
}
static uint8_t sp_ai_heartbeat_seq;
static int sp_ai_payload_status = -1, sp_ai_state_reason = -1;
static void sp_ai_game_update(const uint8_t *data, size_t length) {
    sp_ai_packet_at = NSProcessInfo.processInfo.systemUptime;
    if (length < 6 || data[0] != 'A' || data[1] != 'I' ||
        !(data[2] & 1) || ((data[2] & 128) && (data[2] & (4|16)) != (4|16)) ||
        (data[3] > 100 && data[3] != 255) || (data[4] > 100 && data[4] != 255)) {
        int reason = length >= 6 && data[0] == 'A' && data[1] == 'I' && !(data[2] & 1) ? data[3] : 0;
        if (sp_ai_payload_status != 0 || reason != sp_ai_state_reason) {
            static const char *const reasons[] = {"missing payload", "UnitExists(player)", "UnitHealthMax(player)", "UnitHealth(player)", "player death API", "UnitExists(target)", "target attack/player API", "target death API", "target health API", "UnitAffectingCombat", "IsMounted", "GetTime/encoding", "player health restricted", "target health restricted"};
            const char *why = reason >= 0 && reason < sizeof reasons / sizeof reasons[0] ? reasons[reason] : "unknown reason";
            sp_stub_log([[NSString stringWithFormat:@"AI telemetry: state unavailable reason %d (%s)", reason, why] UTF8String]);
        }
        sp_ai_state_reason = reason;
        sp_ai_payload_status = 0;
        sp_ai_game_at = 0;
        sp_ai_game_move_keys = 0;
        return;
    }
    if (sp_ai_game_at <= 0 || sp_ai_packet_at - sp_ai_game_at >= 6.0 ||
        sp_ai_health_known(sp_ai_game_hp) != sp_ai_health_known(data[3]) ||
        sp_ai_health_known(sp_ai_game_target_hp) != sp_ai_health_known(data[4]))
        sp_stub_log((data[3] == 255 || data[4] == 255) ?
            "AI telemetry: public decision flags valid; health unknown" : "AI telemetry: valid game-state payload");
    sp_ai_payload_status = 1;
    sp_ai_state_reason = -1;
    sp_ai_game_flags = data[2];
    sp_ai_game_hp = data[3];
    sp_ai_game_target_hp = data[4];
    sp_ai_game_meta = data[5];
    sp_ai_game_move_keys = sp_ai_movement_bindings(data, (unsigned)length);
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
@property(nonatomic, copy) BOOL (^action)(NSString *, CGPoint, NSTimeInterval, NSTimeInterval);
@property(nonatomic, copy) void (^releaseInput)(void);
@property(nonatomic, copy) void (^status)(NSString *);
- (void)start;
- (void)stop;
- (void)invalidateDecision;
- (void)toggleTeaching;
- (void)recordManualSteering:(CGPoint)delta;
@end

@implementation SPGameAIController {
    BOOL _active, _starting, _stopping, _ownsCapture;
    NSUInteger _run, _captureRun;
    BOOL _busy;
    NSTimeInterval _nextFrame, _lastFrame;
    BOOL _layaEnabled, _layaPending;
    NSString *_directCandidate, *_layaState;
    NSTimeInterval _directNextAction, _directLastActionAt, _p2pMetricsAt;
    NSString *_directLastAction, *_p2pLastStatus;
    NSTimeInterval _p2pStatusAt;
    unsigned _directAttackAttempts, _visiblePulses, _lootAttempts;
    SPAIMove _visibleProposal;
    NSTimeInterval _visibleSeenAt, _lastDamageAt, _lootBindSince;
    uint8_t _lastTargetHP;
    SPAIApproachExamples _approachExamples;
    BOOL _teaching;
    NSTimeInterval _lastTeachingPacket;
    unsigned _teachingSamples;
    SPAINavigation _navigation;
    NSData *_sceneBeforeMove;
    NSTimeInterval _moveEndsAt;
    BOOL _wasInCombat, _navigationThermalPause;
    BOOL _p2pAvailable, _p2pPending;
    NSTimeInterval _p2pLastUsed, _p2pLastMove;
    NSUInteger _p2pGeneration;
    BOOL _visualPreviewMode;
    BOOL _visualPreviewError;
    NSString *_visualPreviewStatus;
    NSTimeInterval _visualPreviewAt;
}
- (BOOL)active { return _active; }
- (BOOL)starting { return _starting && _active; }

- (void)toggleTeaching {
    if (_teaching) {
        _teaching = NO;
        if (!_teachingSamples) {
            if (self.status) self.status(@"TEACH NO DATA");
            return;
        }
        [NSUserDefaults.standardUserDefaults setObject:@[@(_approachExamples.forward[0]),
            @(_approachExamples.lateral[0]), @(_approachExamples.forward[1]), @(_approachExamples.lateral[1])]
            forKey:@"sp_wolkara_approach_examples_v1"];
        if (self.status) self.status(@"TEACH SAVED");
        return;
    }
    if (_active) [self stop];
    _approachExamples = (SPAIApproachExamples){0};
    _lastTeachingPacket = 0;
    _teachingSamples = 0;
    _teaching = YES;
    if (self.status) self.status(@"TEACH 0");
}

- (void)recordManualSteering:(CGPoint)delta {
    if (!_teaching || _active || _teachingSamples >= 60) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now-sp_ai_game_at >= 0.85 || sp_ai_game_at <= _lastTeachingPacket ||
        sp_ai_current_decision(now) != SP_AI_ATTACK || (sp_ai_game_flags & 32)) return;
    SPAIMove side = sp_ai_visible_approach(sp_ai_game_meta, 2, false, false);
    if (side != SP_MOVE_LEFT && side != SP_MOVE_RIGHT) {
        if (self.status && side == SP_MOVE_NONE) self.status(@"TEACH NO PLATE");
        return;
    }
    SPAIMove demonstrated = SP_MOVE_NONE;
    if (-delta.y >= 12 && -delta.y > fabs(delta.x)) demonstrated = SP_MOVE_FORWARD;
    else if (fabs(delta.x) >= 12 && fabs(delta.x) > fabs(delta.y))
        demonstrated = delta.x < 0 ? SP_MOVE_LEFT : SP_MOVE_RIGHT;
    if (demonstrated != SP_MOVE_FORWARD && demonstrated != side) return;
    sp_ai_learn_approach(&_approachExamples, side, demonstrated);
    _lastTeachingPacket = sp_ai_game_at;
    ++_teachingSamples;
    if (self.status) self.status([NSString stringWithFormat:@"TEACH %u", _teachingSamples]);
}

- (void)invalidateDecision {
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL selector = NSSelectorFromString(@"resetDecision");
    if ([bridge respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
    ++_p2pGeneration;
    _navigation = (SPAINavigation){0};
    _sceneBeforeMove = nil;
    _moveEndsAt = 0;
    _visibleProposal = SP_MOVE_NONE;
    _visibleSeenAt = 0;
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
    _visualPreviewMode = NO;
    _visualPreviewStatus = nil;
    _visualPreviewAt = 0;
    sp_p2p_enable(NO);
    ++_run;
    @synchronized(self) { _captureRun = 0; _busy = NO; }
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
        if ([keys containsObject:answer]) executed = self.action(answer, CGPointZero, captured, 0);
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
                        executed = self.action(parts[0], points[index - 1].CGPointValue, captured, 0);
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
- (void)setNavigationStatus:(NSString *)status at:(NSTimeInterval)now {
    _p2pLastStatus = status;
    _p2pStatusAt = now;
}
- (void)tryP2P:(NSUInteger)run {
    if (!_p2pAvailable || _p2pPending || !sp_p2p_latest_frame ||
        sp_p2p_latest_at <= _p2pLastUsed ||
        NSProcessInfo.processInfo.systemUptime - sp_p2p_latest_at > 2.2 || _navigation.blocked) return;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL pred = NSSelectorFromString(@"predictFrame:completion:");
    if (![p2p respondsToSelector:pred]) return;
    NSUInteger gen = _p2pGeneration;
    NSTimeInterval captured = sp_p2p_latest_at;
    NSData *frame = sp_p2p_latest_frame;
    NSTimeInterval submitted = NSProcessInfo.processInfo.systemUptime;
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
            SPAIDecision decision = sp_ai_current_decision(now);
            NSString *current = decision == SP_AI_TARGET ? @"TARGET" : decision == SP_AI_ATTACK ? @"ATTACK" : nil;
            if (!sp_ai_nav_allowed(decision, f, strong->_directAttackAttempts) ||
                ![strong->_directCandidate isEqualToString:current] || strong->_navigationThermalPause ||
                (decision == SP_AI_ATTACK && (sp_ai_game_meta & 0x78))) return;
            if (now - strong->_p2pMetricsAt >= 10.0) {
                strong->_p2pMetricsAt = now;
                sp_stub_log([[NSString stringWithFormat:@"AI navigation: frame age %.2fs; Core ML queue and prediction %.2fs",
                    now-captured, now-submitted] UTF8String]);
            }
            if (now-captured > 2.2) {
                strong->_navigation.proposed = SP_MOVE_NONE;
                strong->_navigation.votes = 0;
                [strong setNavigationStatus:@"P2P SLOW" at:now];
                return;
            }
            if (strong->_sceneBeforeMove) {
                if (captured < strong->_moveEndsAt) return;
                sp_ai_nav_feedback(&strong->_navigation, sp_p2p_scene_changed(strong->_sceneBeforeMove, frame));
                strong->_sceneBeforeMove = nil;
            }
            if (strong->_navigation.blocked) {
                [strong setNavigationStatus:@"NAV BLOCK" at:now];
                sp_stub_log("AI navigation: scene unchanged after bounded recovery; holding position");
                return;
            }
            SPAIMove proposed = sp_ai_move(answer);
            SPAIMove selected = sp_ai_nav_proposal(&strong->_navigation, proposed);
            if (selected == SP_MOVE_NONE) {
                NSString *status = proposed != SP_MOVE_NONE ? @"NAV CHECK" :
                    [answer isEqualToString:@"WARMUP"] ? @"P2P WARM" : @"P2P WAIT";
                [strong setNavigationStatus:status at:now];
                return;
            }
            if (!sp_ai_nav_has_slot(now, strong->_directNextAction) || now-strong->_p2pLastMove < 0.8) return;
            BOOL recovering = strong->_navigation.stalls == 2;
            NSString *move = recovering ? (selected == SP_MOVE_LEFT ? @"STRAFE_LEFT" : @"FORWARD") : answer;
            NSTimeInterval duration = sp_ai_nav_duration(&strong->_navigation, selected);
            if (strong.action && strong.action(move, CGPointZero, captured, duration)) {
                sp_ai_nav_sent(&strong->_navigation, selected);
                strong->_p2pLastMove = now;
                strong->_sceneBeforeMove = frame;
                strong->_moveEndsAt = now + duration;
                SEL record = NSSelectorFromString(@"recordMove:");
                if ([p2p respondsToSelector:record])
                    ((void (*)(id,SEL,NSString *))objc_msgSend)(p2p, record, move);
                [strong setNavigationStatus:recovering ? @"NAV RECOVER" : @"P2P MOVE" at:now];
            } else [strong setNavigationStatus:@"P2P INPUT" at:now];
        });
    };
    ((void (*)(id,SEL,NSData *,void (^)(NSString *)))objc_msgSend)(p2p,pred,frame,completion);
}
// Legacy visual observation only when public decision flags are unavailable.
- (void)previewP2P:(NSUInteger)run {
    if (!_visualPreviewMode || !_p2pAvailable || _visualPreviewError || _p2pPending ||
        !sp_p2p_latest_frame || sp_p2p_latest_at <= _p2pLastUsed ||
        NSProcessInfo.processInfo.systemUptime - sp_p2p_latest_at > 3.0) return;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL pred = NSSelectorFromString(@"predictFrame:completion:");
    if (![p2p respondsToSelector:pred]) { _visualPreviewError = YES; return; }
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
            if (!strong->_active || strong->_run != run || strong->_p2pGeneration != gen ||
                !strong->_visualPreviewMode) return;
            if ([answer hasPrefix:@"ERR:"]) {
                strong->_visualPreviewError = YES;
                sp_stub_log("AI visual preview: model error");
                return;
            }
            BOOL move = [@[@"FORWARD", @"BACK", @"LEFT", @"RIGHT", @"STRAFE_LEFT", @"STRAFE_RIGHT"] containsObject:answer];
            if (!move && ![@[@"WAIT", @"WARMUP"] containsObject:answer]) return;
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (sp_ai_packet_at <= 0 || now - sp_ai_packet_at >= 6.0 ||
                (sp_ai_state_reason != 12 && sp_ai_state_reason != 13)) return;
            if (now - captured > 3.0) {
                strong->_visualPreviewStatus = @"VIS SLOW";
                strong->_visualPreviewAt = now;
                sp_stub_log([[NSString stringWithFormat:@"AI visual: stale result after %.2fs", now-captured] UTF8String]);
                return;
            }
            NSString *display = [@"VIS " stringByAppendingString:answer];
            if (move) sp_stub_log([[NSString stringWithFormat:@"AI visual preview: %@ (public flags unknown)", answer] UTF8String]);
            strong->_visualPreviewStatus = display;
            strong->_visualPreviewAt = now;
        });
    };
    ((void (*)(id,SEL,NSData *,void (^)(NSString *)))objc_msgSend)(p2p,pred,sp_p2p_latest_frame,completion);
}
// Laya's two-choice result is diagnostic. It cannot delay time-sensitive input.
- (void)evaluateLaya:(NSString *)candidate combat:(BOOL)combat run:(NSUInteger)run {
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL selector = NSSelectorFromString(@"decideGameState:candidate:completion:");
    if (!_layaEnabled || _layaPending || !candidate ||
        !sp_ai_health_known(sp_ai_game_hp) || !sp_ai_health_known(sp_ai_game_target_hp) ||
        ![bridge respondsToSelector:selector]) return;
    NSString *hp = sp_ai_game_hp < 40 ? @"low" : sp_ai_game_hp < 75 ? @"medium" : @"high";
    NSString *targetHP = sp_ai_game_target_hp < 35 ? @"low" : sp_ai_game_target_hp < 75 ? @"medium" : @"high";
    NSString *state = [NSString stringWithFormat:@"%@:%@:%@:%@", candidate, hp, combat ? @"combat" : @"peace", targetHP];
    if ([_layaState isEqualToString:state]) return;
    _layaState = state;
    _layaPending = YES;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    __weak SPGameAIController *weak = self;
    void (^completion)(NSString *) = ^(NSString *answer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPGameAIController *strong = weak;
            if (!strong) return;
            strong->_layaPending = NO;
            if (!strong->_active || strong->_run != run) return;
            if ([answer hasPrefix:@"ERR:"]) strong->_layaEnabled = NO;
            sp_stub_log([[NSString stringWithFormat:@"AI Laya comparison: %@ / %@ in %.2fs", candidate, answer,
                NSProcessInfo.processInfo.systemUptime-started] UTF8String]);
        });
    };
    ((void (*)(id, SEL, NSString *, NSString *, void (^)(NSString *)))objc_msgSend)(bridge, selector, state, candidate, completion);
}
- (void)pollDirect:(NSUInteger)run {
    if (!_active || _run != run) return;
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSTimeInterval now = process.systemUptime;
    NSProcessInfoThermalState thermal = process.thermalState;
    if (thermal == NSProcessInfoThermalStateCritical) { [self fail:@"AI HEAT"]; return; }
    BOOL thermalPause = thermal >= NSProcessInfoThermalStateSerious;
    BOOL telemetryFresh = sp_ai_game_at > 0 && now-sp_ai_game_at < 3.0;
    BOOL combat = telemetryFresh && (sp_ai_game_flags & 32);
    SPAIDecision base = sp_ai_current_decision(now);
    if (!(sp_ai_game_flags & 128)) {
        _lootAttempts = 0;
        _lootBindSince = 0;
    }
    SPAIDecision decision = sp_ai_farm_decision(base, sp_ai_game_flags, sp_ai_game_meta, _lootAttempts);
    if (decision == SP_AI_LOOT_BIND) {
        if (!_lootBindSince) _lootBindSince = now;
        if (now-_lootBindSince >= 2.4) {
            _lootAttempts = 2;
            decision = base;
        }
    }
    NSString *candidate = decision == SP_AI_TARGET ? @"TARGET" : decision == SP_AI_ATTACK ? @"ATTACK" :
        decision == SP_AI_LOOT ? @"LOOT" : nil;
    BOOL preview = (sp_ai_packet_at > 0 && now-sp_ai_packet_at < 6.0 &&
        (sp_ai_state_reason == 12 || sp_ai_state_reason == 13));
    BOOL phaseChanged = ((candidate || _directCandidate) && ![candidate isEqualToString:_directCandidate]) ||
        combat != _wasInCombat;
    if (phaseChanged || preview != _visualPreviewMode || thermalPause != _navigationThermalPause) {
        if (combat != _wasInCombat)
            sp_stub_log(combat ? "AI combat: public combat flag entered" :
                telemetryFresh ? "AI combat: public combat flag ended" : "AI combat: public state lost");
        if (phaseChanged) _layaState = nil;
        _directCandidate = candidate;
        _wasInCombat = combat;
        _navigationThermalPause = thermalPause;
        _visualPreviewMode = preview;
        _visualPreviewStatus = nil;
        _visualPreviewAt = 0;
        _visualPreviewError = NO;
        _p2pLastUsed = 0;
        _p2pLastStatus = nil;
        _directLastAction = nil;
        if (phaseChanged) {
            _directAttackAttempts = _visiblePulses = 0;
            _lastTargetHP = 255;
            _lastDamageAt = 0;
            _directNextAction = 0;
        }
        [self invalidateDecision];
        if (self.releaseInput) self.releaseInput();
    }

    NSString *display = @"AI WAIT";
    if (sp_ai_strip_at <= 0 || now-sp_ai_strip_at >= 6.0) display = @"AI STRIP";
    else if (sp_ai_packet_at <= 0 || now-sp_ai_packet_at >= 6.0) display = @"AI SYNC";
    else if (sp_ai_state_reason > 0) display = [NSString stringWithFormat:@"AI DATA %d", sp_ai_state_reason];
    if (decision == SP_AI_REST) display = @"AI REST";
    else if (decision == SP_AI_BIND) display = @"F12 BIND";
    else if (decision == SP_AI_LOOT_BIND) display = @"INTERACT BIND";
    else if (combat) display = @"AI COMBAT";

    if (decision == SP_AI_ATTACK && sp_ai_health_known(sp_ai_game_target_hp)) {
        if (sp_ai_health_known(_lastTargetHP) && sp_ai_game_target_hp < _lastTargetHP) {
            _lastDamageAt = now;
            _visiblePulses = 0;
        }
        _lastTargetHP = sp_ai_game_target_hp;
    }
    BOOL recentDamage = _lastDamageAt > 0 && now-_lastDamageAt < 3.0;
    SPAIFarmPlan plan = sp_ai_plan_farm(decision, sp_ai_game_flags, sp_ai_game_meta, _directAttackAttempts,
        recentDamage, &_approachExamples);
    // The expensive frame capture and both models pause, while the existing
    // public target column can still guide short, infrequent movement pulses.
    SPAIMove visibleMove = _visiblePulses < 12 ? plan.movement : SP_MOVE_NONE;
    BOOL hasColumn = decision == SP_AI_ATTACK && (sp_ai_game_meta & 0x78);
    BOOL navigate = plan.usePixel2Play;
    sp_p2p_enable(_p2pAvailable && !thermalPause && (preview || (navigate && !_navigation.blocked)));
    if (preview) {
        if (thermalPause) display = @"VIS HEAT";
        else if (!_p2pAvailable) display = @"VIS FILE";
        else if (_visualPreviewError) display = @"VIS ERR";
        else {
            [self previewP2P:run];
            display = _visualPreviewStatus && now-_visualPreviewAt < 5.0 ? _visualPreviewStatus : @"VIS LOAD";
        }
    } else if (candidate) {
        if (!thermalPause && decision != SP_AI_LOOT)
            [self evaluateLaya:candidate combat:combat run:run];
        BOOL keyDue = now >= _directNextAction;
        if (keyDue && self.action) {
            BOOL sent = self.action(candidate, CGPointZero, sp_ai_game_at, 0);
            if (sent) {
                if (decision == SP_AI_ATTACK && _directAttackAttempts < 2) ++_directAttackAttempts;
                if (decision == SP_AI_LOOT) ++_lootAttempts;
                BOOL approach = plan.phase == SP_FARM_APPROACH &&
                    (visibleMove != SP_MOVE_NONE || plan.usePixel2Play);
                _directNextAction = now + sp_ai_direct_interval(decision, approach);
                BOOL unknownHP = !sp_ai_health_known(sp_ai_game_hp);
                _directLastAction = decision == SP_AI_ATTACK ? (unknownHP ? @"HP? F12" : @"AI F12") :
                    decision == SP_AI_LOOT ? @"AI LOOT" : (unknownHP ? @"HP? TAB" : @"AI TAB");
                _directLastActionAt = now;
                display = _directLastAction;
            } else { display = @"AI INPUT"; _directNextAction = now + 0.4; }
        } else if (_directLastAction && now-_directLastActionAt < 1.0) display = _directLastAction;
        // Use only fresh, public on-screen target columns, and require two
        // agreeing packets before steering. Do not send this branch through P2P.
        if (visibleMove != _visibleProposal) {
            _visibleProposal = visibleMove;
            _visibleSeenAt = sp_ai_game_at;
        } else if (!keyDue && visibleMove != SP_MOVE_NONE && sp_ai_game_at - _visibleSeenAt >= 0.12 &&
                   now-sp_ai_game_at < 0.85 && now-_p2pLastMove >= sp_ai_visible_move_spacing(thermalPause) &&
                   sp_ai_nav_has_slot(now, _directNextAction) && self.action) {
            NSString *move = visibleMove == SP_MOVE_LEFT ? @"STRAFE_LEFT" :
                visibleMove == SP_MOVE_RIGHT ? @"STRAFE_RIGHT" : @"FORWARD";
            if (self.action(move, CGPointZero, sp_ai_game_at, sp_ai_visible_move_duration(visibleMove, thermalPause))) {
                ++_visiblePulses;
                _p2pLastMove = now;
                display = thermalPause ? @"HEAT WALK" : @"AI APPROACH";
            } else display = @"NAV INPUT";
        }
        if (navigate) {
            if (thermalPause) display = decision == SP_AI_TARGET ? @"HEAT SEEK" : @"HEAT NO PLATE";
            else if (_navigation.blocked) display = @"NAV BLOCK";
            else {
                [self tryP2P:run];
                if (_p2pLastStatus && now-_p2pStatusAt < 2.0 && now-_directLastActionAt >= 1.0)
                    display = _p2pLastStatus;
            }
        }
    }
    if (decision == SP_AI_ATTACK && !hasColumn && !combat && _directAttackAttempts >= 2 &&
        (!_p2pAvailable || [display isEqualToString:@"AI WAIT"])) display = @"NAV NO PLATE";
    if (decision == SP_AI_ATTACK && hasColumn && _visiblePulses >= 12 &&
        [display isEqualToString:@"AI WAIT"]) display = @"NAV LIMIT";
    if (self.status) self.status(display);
    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weak pollDirect:run];
    });
}
- (void)start {
    if (_active || _starting || _stopping) return;
    if (_teaching) [self toggleTeaching];
    NSArray *examples = [NSUserDefaults.standardUserDefaults arrayForKey:@"sp_wolkara_approach_examples_v1"];
    _approachExamples = (SPAIApproachExamples){0};
    if (examples.count == 4) {
        for (NSUInteger i=0; i<4; ++i) {
            if (![examples[i] isKindOfClass:NSNumber.class]) continue;
            NSInteger count = [examples[i] integerValue];
            if (count < 0 || count > 100) continue;
            if (i % 2) _approachExamples.lateral[i/2] = (uint16_t)count;
            else _approachExamples.forward[i/2] = (uint16_t)count;
        }
    }
    Class bridge = NSClassFromString(@"SPGameAIModel");
    SEL ready = NSSelectorFromString(@"layaReady");
    _layaEnabled = [bridge respondsToSelector:ready] && ((BOOL (*)(id, SEL))objc_msgSend)(bridge, ready);
    _layaState = nil;
    _visualPreviewMode = _visualPreviewError = NO;
    _visualPreviewStatus = nil;
    _visualPreviewAt = 0;
    _wasInCombat = _navigationThermalPause = NO;
    _directCandidate = nil;
    _directNextAction = _directLastActionAt = _p2pStatusAt = _p2pMetricsAt = 0;
    _directAttackAttempts = _visiblePulses = _lootAttempts = 0;
    _lootBindSince = 0;
    _lastTargetHP = 255;
    _lastDamageAt = 0;
    _directLastAction = _p2pLastStatus = nil;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL available = NSSelectorFromString(@"available");
    _p2pAvailable = [p2p respondsToSelector:available] && ((BOOL (*)(id,SEL))objc_msgSend)(p2p,available);
    _p2pLastUsed = _p2pLastMove = 0;
    [self invalidateDecision];
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
