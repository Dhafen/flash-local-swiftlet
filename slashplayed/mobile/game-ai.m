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
static SPAIFarmFeedback sp_ai_game_feedback;
static SPAINavEvidence sp_ai_game_evidence;
static SPAIHealthStatus sp_ai_player_health = SP_HEALTH_UNSPECIFIED;
static SPAIHealthStatus sp_ai_target_health = SP_HEALTH_UNSPECIFIED;
static NSTimeInterval sp_ai_game_at, sp_ai_strip_at, sp_ai_packet_at;
static SPAINavSample sp_ai_game_sample(void) {
    return (SPAINavSample){sp_ai_game_at, sp_ai_game_feedback, sp_ai_game_evidence,
        (sp_ai_game_meta & 128) ? (sp_ai_game_meta >> 3) & 15 : 0};
}
static const char *sp_ai_nav_outcome_name(SPAINavOutcome outcome) {
    static const char *const names[] = {"pending", "no-fresh-position", "context-changed", "stalled",
        "displacement-only", "target-closer", "plate-centered", "no-target-progress"};
    return names[outcome];
}
static BOOL sp_ai_heartbeat_seen;
static BOOL sp_ai_health_known(uint8_t value) { return sp_ai_hp_known(value); }
static SPAIDecision sp_ai_current_decision(NSTimeInterval now) {
    return sp_ai_decision(sp_ai_game_at > 0 && now-sp_ai_game_at < 3.0,
        sp_ai_game_flags,sp_ai_game_hp,sp_ai_game_target_hp,sp_ai_game_meta);
}
static uint8_t sp_ai_heartbeat_seq;
static int sp_ai_payload_status = -1, sp_ai_state_reason = -1;
static void sp_ai_game_update(const uint8_t *data, size_t length, NSTimeInterval observedAt) {
    if (observedAt <= sp_ai_game_at) return;
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
        sp_ai_game_feedback = (SPAIFarmFeedback){0};
        sp_ai_game_evidence = (SPAINavEvidence){0, 0, 0, SP_AI_DISTANCE_UNKNOWN};
        sp_ai_player_health = sp_ai_target_health = SP_HEALTH_UNSPECIFIED;
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
    sp_ai_game_feedback = sp_ai_farm_feedback(data, (unsigned)length);
    sp_ai_game_evidence = sp_ai_nav_evidence(data, (unsigned)length);
    SPAIHealthStatus player = sp_ai_health_status(data, (unsigned)length, false);
    SPAIHealthStatus target = sp_ai_health_status(data, (unsigned)length, true);
    if (player != sp_ai_player_health || target != sp_ai_target_health) {
        static const char *const health[] = {"public", "unavailable", "restricted", "absent", "unspecified"};
        sp_stub_log([[NSString stringWithFormat:@"AI health evidence: player=%s target=%s", health[player], health[target]] UTF8String]);
    }
    sp_ai_player_health = player;
    sp_ai_target_health = target;
    sp_ai_game_at = observedAt;
}

static void sp_ai_heartbeat(uint8_t seq, const uint8_t *data, size_t length, NSTimeInterval observedAt) {
    static NSTimeInterval lastHeartbeat;
    if (observedAt <= lastHeartbeat) return;
    if (sp_ai_heartbeat_seen && seq == sp_ai_heartbeat_seq) return;
    if (!sp_ai_heartbeat_seen) sp_stub_log("AI telemetry: independent heartbeat detected");
    sp_ai_heartbeat_seen = YES;
    sp_ai_heartbeat_seq = seq;
    lastHeartbeat = observedAt;
    sp_ai_game_update(data, length, observedAt);
}

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL starting;
@property(nonatomic) BOOL autonomousTest;
@property(nonatomic) BOOL modelDiagnostics;
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
    NSString *_layaState, *_lastPhase;
    NSString *_lastWorldSummary;
    NSTimeInterval _directNextAction;
    unsigned _lootAttempts, _searchAttempts;
    SPAISteering _visibleSteering;
    uint8_t _steeringPosition;
    NSTimeInterval _lastMoveAt, _lastDamageAt;
    SPAINavPulse _pulse;
    SPAINavBudget _navBudget;
    SPAICombatEvidence _combatEvidence;
    uint8_t _encounter;
    BOOL _recovering, _probeAfterMove;
    NSProcessInfoThermalState _lastThermal;
    SPAIApproachExamples _approachExamples;
    BOOL _teaching;
    NSTimeInterval _lastTeachingPacket;
    unsigned _teachingSamples;
    BOOL _p2pAvailable, _p2pPending;
    NSTimeInterval _p2pLastUsed, _p2pMetricsAt;
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
    if (_pulse.deadline) sp_stub_log("AI navigation: cancelled");
    _pulse = (SPAINavPulse){0};
    _visibleSteering = (SPAISteering){0};
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
- (void)finish:(NSString *)answer captured:(NSTimeInterval)captured run:(NSUInteger)run {
    if (!_active || _run != run) return;
    if ([answer isEqualToString:@"ERROR"] || [answer isEqualToString:@"UNAVAILABLE"]) {
        [self fail:@"AI MODEL!"];
        return;
    }
    NSString *display = NSProcessInfo.processInfo.systemUptime - captured <= 8.0 ? @"AI OBS" : @"AI SLOW";
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
    if (ok) for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text.confidence < 0.45 || text.string.length < 2) continue;
        CGRect rect = observation.boundingBox;
        CGPoint point = CGPointMake(CGRectGetMidX(rect), 1 - CGRectGetMidY(rect));
        [observedLabels addObject:@{@"id": @(observedLabels.count + 1), @"x": @(point.x), @"y": @(point.y),
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
        if (!ok || !observation.length || !observedLabels.count) {
            [self finish:@"WAIT" captured:captured run:run];
            if (self.status) self.status(@"AI NO TEXT");
            return;
        }
        if (self.status) self.status(@"AI THINK");
        Class bridge = NSClassFromString(@"SPGameAIModel");
        SEL selector = NSSelectorFromString(@"decide:completion:");
        if (![bridge respondsToSelector:selector]) { [self fail:@"AI MODEL!"]; return; }
        void (^completion)(NSString *) = ^(NSString *answer) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self finish:answer captured:captured run:run]; });
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
// Read-only model diagnostics. Predictions have no connection to the executor.
- (void)previewP2P:(NSUInteger)run {
    if (!_visualPreviewMode || !_p2pAvailable || _visualPreviewError || _p2pPending ||
        !sp_p2p_latest_frame || sp_p2p_latest_at <= _p2pLastUsed ||
        NSProcessInfo.processInfo.systemUptime - sp_p2p_latest_at > 3.0) return;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL pred = NSSelectorFromString(@"predictFrame:completion:");
    if (![p2p respondsToSelector:pred]) { _visualPreviewError = YES; return; }
    NSUInteger gen = _p2pGeneration;
    NSTimeInterval captured = sp_p2p_latest_at;
    NSTimeInterval submitted = NSProcessInfo.processInfo.systemUptime;
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
            if (now - strong->_p2pMetricsAt >= 10.0) {
                strong->_p2pMetricsAt = now;
                sp_stub_log([[NSString stringWithFormat:@"AI Pixel2Play: frame age %.2fs, prediction %.2fs",
                    now-captured, now-submitted] UTF8String]);
            }
            if (now - captured > 3.0) {
                strong->_visualPreviewStatus = @"VIS SLOW";
                strong->_visualPreviewAt = now;
                sp_stub_log([[NSString stringWithFormat:@"AI visual: stale result after %.2fs", now-captured] UTF8String]);
                return;
            }
            NSString *display = [@"VIS " stringByAppendingString:answer];
            if (move) sp_stub_log([[NSString stringWithFormat:@"AI visual preview: %@ (diagnostic only)", answer] UTF8String]);
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

- (void)showPhase:(NSString *)phase {
    if ([_lastPhase isEqualToString:phase]) return;
    _lastPhase = phase;
    sp_stub_log([[@"AI phase: " stringByAppendingString:phase] UTF8String]);
    if (self.status) self.status(phase);
}

- (void)observeWorld:(SPAINavSample)sample {
    NSString *target = !(sp_ai_game_flags & 4) ? @"none" : (sp_ai_game_flags & 16) ? @"dead" :
        (sp_ai_game_flags & 8) ? @"hostile NPC" : @"other";
    NSString *direction = !sample.column ? @"unknown" : sample.column <= 6 ? @"left" : sample.column >= 10 ? @"right" : @"center";
    NSString *summary = [NSString stringWithFormat:
        @"target=%@ identity=%@ plate=%@ position=%@ distance=%@ combat=%@ tab=%@ f12=%@",
        target, sample.evidence.target ? @"public" : @"unknown", direction,
        sample.evidence.position && sample.motion.source == SP_MOTION_POSITION ? @"public" : @"unknown",
        sample.evidence.distance == SP_AI_DISTANCE_UNKNOWN ? @"unknown" : @"public",
        (sp_ai_game_flags & 32) ? @"yes" : @"no",
        (sample.evidence.bindings & SP_AI_TAB_BOUND) ? @"verified" : @"unknown",
        (sample.evidence.bindings & SP_AI_ROTATION_BOUND) ? @"verified" : @"unknown"];
    if ([_lastWorldSummary isEqualToString:summary]) return;
    _lastWorldSummary = summary;
    sp_stub_log([[@"AI world: " stringByAppendingString:summary] UTF8String]);
}

- (BOOL)submit:(NSString *)action forSample:(SPAINavSample)sample hold:(NSTimeInterval)hold {
    BOOL accepted = self.autonomousTest && self.action && self.action(action, CGPointZero, sample.at, hold);
    sp_stub_log([[NSString stringWithFormat:@"AI action: rules %@ observation %.3f adapter %@",
        action, sample.at, accepted ? @"accepted" : @"rejected"] UTF8String]);
    return accepted;
}

- (void)recordNavigation:(SPAINavOutcome)outcome {
    sp_ai_nav_resolve(&_navBudget, outcome);
    const char *name = sp_ai_nav_outcome_name(outcome);
    SPAINavSample after = sp_ai_game_sample();
    sp_stub_log([[NSString stringWithFormat:
        @"AI navigation: %s target %u/%u position %u/%u counter %u/%u column %u/%u distance-q4 %u/%u",
        name, (unsigned)_pulse.before.evidence.target, (unsigned)after.evidence.target,
        (unsigned)_pulse.before.evidence.position, (unsigned)after.evidence.position,
        (unsigned)_pulse.before.motion.counter, (unsigned)after.motion.counter,
        _pulse.before.column, after.column, (unsigned)_pulse.before.evidence.distance,
        (unsigned)after.evidence.distance] UTF8String]);
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    NSString *key = [@"sp_ai_navigation_count_" stringByAppendingString:[NSString stringWithUTF8String:name]];
    NSInteger count = [prefs integerForKey:key];
    if (count < 10000) [prefs setInteger:count + 1 forKey:key];
}

- (NSString *)advance:(SPAINavSample)sample now:(NSTimeInterval)now reduced:(BOOL)reduced {
    if (!sp_ai_heartbeat_seen || !sp_ai_sample_fresh(sample.at, now)) {
        _visibleSteering = (SPAISteering){0};
        if (_pulse.deadline) {
            [self recordNavigation:SP_NAV_NO_SAMPLE];
            _pulse = (SPAINavPulse){0};
        }
        if (self.releaseInput) self.releaseInput();
        if (sp_ai_strip_at <= 0 || now-sp_ai_strip_at >= 6.0) return @"AI STRIP";
        if (sp_ai_packet_at <= 0 || now-sp_ai_packet_at >= 6.0) return @"AI SYNC";
        return sp_ai_state_reason > 0 ? [NSString stringWithFormat:@"AI DATA %d", sp_ai_state_reason] : @"AI STALE";
    }

    SPAIDecision decision = sp_ai_current_decision(now);
    BOOL hostile = decision == SP_AI_ATTACK || decision == SP_AI_BIND;
    uint8_t target = sample.evidence.target;
    if (_encounter != target) {
        if (_pulse.deadline) sp_stub_log("AI navigation: cancelled on target change");
        if (self.releaseInput) self.releaseInput();
        _directNextAction = _lastDamageAt = 0;
        _visibleSteering = (SPAISteering){0};
        _pulse = (SPAINavPulse){0};
        _navBudget = (SPAINavBudget){0};
        _combatEvidence = (SPAICombatEvidence){.lastHP = 255};
        _probeAfterMove = NO;
        _lootAttempts = 0;
        if (hostile) _searchAttempts = 0;
        _encounter = target;
    }

    bool recovering = _recovering;
    SPAIReadiness readiness = sp_ai_readiness(sp_ai_game_flags, sp_ai_game_hp, &recovering);
    _recovering = recovering;
    if (readiness != SP_AI_READY) {
        _visibleSteering = (SPAISteering){0};
        if (_pulse.deadline) [self invalidateDecision];
        if (self.releaseInput) self.releaseInput();
        if (readiness == SP_AI_DEAD) return @"PLAYER DEAD";
        if (readiness == SP_AI_MOUNTED) return @"MOUNTED";
        if (readiness == SP_AI_RECOVER) return @"RECOVER";
        return sp_ai_player_health == SP_HEALTH_RESTRICTED ? @"HP SECRET" : @"HP UNKNOWN";
    }

    if (_pulse.deadline) {
        BOOL canContinue = hostile && target && sample.column && sp_ai_movement_key(_pulse.move, sp_ai_game_move_keys);
        SPAINavOutcome outcome = sp_ai_nav_outcome(_pulse, sample, now);
        if (!canContinue && (outcome == SP_NAV_PENDING || outcome == SP_NAV_NO_SAMPLE))
            outcome = SP_NAV_CONTEXT_CHANGED;
        if (outcome == SP_NAV_PENDING) return reduced ? @"HEAT WALK" : @"APPROACH";
        if (self.releaseInput) self.releaseInput();
        [self recordNavigation:outcome];
        _probeAfterMove = _pulse.move == SP_MOVE_FORWARD && outcome == SP_NAV_DISPLACED;
        _pulse = (SPAINavPulse){0};
        _directNextAction = now + 0.4;
    }

    if (sample.motion.lootConfirmed && (sp_ai_game_flags & (16|128)) == (16|128) && target &&
        (sp_ai_game_flags & 32) == 0 && _lootAttempts < 3) {
        sp_stub_log("AI loot: selected corpse slot cleared");
        _lootAttempts = 3;
        _directNextAction = now + 0.4;
        return @"LOOT OK";
    }
    decision = sp_ai_farm_decision(decision, sp_ai_game_flags, sp_ai_game_meta, _lootAttempts,
        sample.motion.lootConfirmed);
    if (decision == SP_AI_LOOT_BIND) return @"INTERACT BIND";
    if (decision == SP_AI_LOOT_WAIT) return @"LOOT UNCONF";
    if (decision == SP_AI_LOOT) {
        if (!target) return @"LOOT UNKNOWN";
        if (now >= _directNextAction) {
            _directNextAction = now + 1.4;
            if (![self submit:@"LOOT" forSample:sample hold:0]) return @"AI INPUT";
            ++_lootAttempts;
        }
        return @"LOOT CHECK";
    }
    if (decision == SP_AI_TARGET) {
        if (!(sample.evidence.bindings & SP_AI_TAB_BOUND)) return @"TAB BIND";
        if (_searchAttempts >= 4) return @"NO TARGET";
        if (now >= _directNextAction) {
            _directNextAction = now + 1.0;
            if (![self submit:@"TARGET" forSample:sample hold:0]) return @"AI INPUT";
            ++_searchAttempts;
        }
        return reduced ? @"HEAT SEEK" : @"SEARCH";
    }
    if (decision == SP_AI_BIND) return @"F12 BIND";
    if (!hostile) return @"AI WAIT";
    if (!(sample.evidence.bindings & SP_AI_ROTATION_BOUND)) return @"F12 BIND";
    if (!target) return @"TARGET UNKNOWN";

    if (sp_ai_observe_damage(&_combatEvidence, sp_ai_game_target_hp, sample.at)) {
        _lastDamageAt = now;
        sp_stub_log("AI combat: selected target health decreased");
    }
    BOOL combat = (sp_ai_game_flags & 32) != 0;
    BOOL recentDamage = _lastDamageAt > 0 && now - _lastDamageAt < 3.0;
    SPAIMove move = sp_ai_visible_approach(sp_ai_game_meta, 2, false, false);
    if (sample.evidence.distance != SP_AI_DISTANCE_UNKNOWN)
        move = sp_ai_apply_approach(&_approachExamples, move, combat);
    if (_steeringPosition != sample.evidence.position) {
        _visibleSteering = (SPAISteering){0};
        _steeringPosition = sample.evidence.position;
    }
    BOOL confirmed = sp_ai_confirm_steering(&_visibleSteering, move, sample.at);
    if (now < _directNextAction) return combat ? @"IN COMBAT" : @"ENGAGE";
    SPAIEngagement engagement = sp_ai_engagement(_combatEvidence, move, sample.evidence.distance,
        recentDamage, _probeAfterMove);
    if (engagement == SP_ENGAGE_NO_DAMAGE) return @"NO DAMAGE";
    if (engagement == SP_ENGAGE_DAMAGE_UNKNOWN) return @"DAMAGE ?";

    if (engagement == SP_ENGAGE_APPROACH) {
        if (!sample.evidence.position || sample.motion.source != SP_MOTION_POSITION) return @"NAV POSITION";
        if (!sp_ai_nav_budget_open(_navBudget, move)) return @"NAV BLOCK";
        if (!sp_ai_movement_key(move, sp_ai_game_move_keys)) return @"MOVE BIND";
        if (!confirmed || now - _lastMoveAt < (reduced ? 2.0 : 0.8))
            return reduced ? @"HEAT WALK" : @"APPROACH";
        NSString *key = move == SP_MOVE_LEFT ? @"STRAFE_LEFT" : move == SP_MOVE_RIGHT ? @"STRAFE_RIGHT" : @"FORWARD";
        NSTimeInterval hold = 0.60; // cover the nominal 0.5s SPHover cadence
        if (![self submit:key forSample:sample hold:hold]) {
            _directNextAction = now + 0.8;
            return @"NAV INPUT";
        }
        sp_ai_nav_accept(&_navBudget, move);
        _visibleSteering = (SPAISteering){0};
        _lastMoveAt = now;
        _pulse = (SPAINavPulse){sample, move, now + hold, now + 1.8};
        return reduced ? @"HEAT WALK" : @"APPROACH";
    }

    _directNextAction = now + 0.85;
    if (![self submit:@"ATTACK" forSample:sample hold:0]) return @"AI INPUT";
    sp_ai_accept_probe(&_combatEvidence, now);
    _probeAfterMove = NO;
    return combat ? @"IN COMBAT" : @"ENGAGE";
}

- (void)pollDirect:(NSUInteger)run {
    if (!_active || _run != run) return;
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSTimeInterval now = process.systemUptime;
    NSProcessInfoThermalState thermal = process.thermalState;
    if (thermal != _lastThermal || !_lastPhase) {
        _lastThermal = thermal;
        sp_stub_log([[NSString stringWithFormat:@"AI thermal: %ld", (long)thermal] UTF8String]);
    }
    if (thermal == NSProcessInfoThermalStateCritical) { [self fail:@"AI HEAT"]; return; }
    BOOL reduced = thermal >= NSProcessInfoThermalStateSerious;
    SPAINavSample sample = sp_ai_game_sample();
    if (sp_ai_sample_fresh(sample.at, now)) [self observeWorld:sample];

    BOOL preview = self.modelDiagnostics && !self.autonomousTest && !reduced;
    if (preview != _visualPreviewMode) {
        [self invalidateDecision];
        _visualPreviewMode = preview;
    }
    sp_p2p_enable(preview && _p2pAvailable && !_visualPreviewError);
    if (self.autonomousTest) {
        [self showPhase:[self advance:sample now:now reduced:reduced]];
    } else if (preview) {
        if (sp_ai_sample_fresh(sample.at, now)) {
            SPAIDecision decision = sp_ai_current_decision(now);
            NSString *candidate = decision == SP_AI_TARGET ? @"TARGET" : decision == SP_AI_ATTACK ? @"ATTACK" : nil;
            [self evaluateLaya:candidate combat:(sp_ai_game_flags & 32) != 0 run:run];
        }
        [self previewP2P:run];
        NSString *status = !_p2pAvailable ? (_layaEnabled ? @"LAYA DIAG" : @"MODEL FILE") : _visualPreviewError ? @"MODEL ERROR" :
            (_visualPreviewStatus && now-_visualPreviewAt < 5.0 ? _visualPreviewStatus : @"VIS LOAD");
        [self showPhase:status];
    } else {
        [self showPhase:reduced ? @"HEAT PAUSE" :
            (sp_ai_sample_fresh(sample.at, now) ? @"OBSERVING" : @"AI STALE")];
    }

    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((reduced ? 0.8 : 0.4) * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [weak pollDirect:run]; });
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
    _lastPhase = nil;
    _lastWorldSummary = nil;
    _directNextAction = _lastMoveAt = _lastDamageAt = 0;
    _lootAttempts = _searchAttempts = 0;
    _navBudget = (SPAINavBudget){0};
    _combatEvidence = (SPAICombatEvidence){.lastHP = 255};
    _encounter = 0;
    _recovering = _probeAfterMove = NO;
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL available = NSSelectorFromString(@"available");
    _p2pAvailable = [p2p respondsToSelector:available] && ((BOOL (*)(id,SEL))objc_msgSend)(p2p,available);
    _p2pLastUsed = _p2pMetricsAt = 0;
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
