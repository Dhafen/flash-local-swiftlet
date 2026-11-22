// Local iOS agent integration. Planner and input callbacks run on the main thread.
#include <stdatomic.h>
#include <stdbool.h>
#include "ai-encounter.h"
#include "ai-progression.h"
#include "ai-health-vision.h"
#include "ai-strip.h"
#include "ai-movement.h"

static void sp_ai_restriction_heartbeat(const uint8_t *bytes, unsigned length) {
    static SPRuntimeRestriction previous;
    SPRuntimeRestriction restriction = sp_ai_strip_restriction(bytes, length);
    if (!restriction.kind || (restriction.kind == previous.kind && !strcmp(restriction.action, previous.action))) return;
    previous = restriction;
    sp_stub_log([[NSString stringWithFormat:@"SPHover restriction: %s action=%s",
        restriction.kind == 1 ? "forbidden" : "blocked", restriction.action] UTF8String]);
}

static atomic_bool sp_p2p_capture_enabled;
static atomic_uint sp_ai_health_interval_ms;
static atomic_uint sp_ai_health_capture_epoch;
static _Atomic(uint64_t) sp_ai_health_bounds, sp_ai_health_bounds_ms;
static uint8_t sp_ai_health_visual_result = SP_VISUAL_HP_UNKNOWN;
static NSTimeInterval sp_ai_health_visual_at;
static SPHealthReference sp_ai_health_reference[4];
static unsigned sp_ai_health_reference_count;
static BOOL sp_ai_health_comparison_pending;
static void sp_ai_clear_health_comparison(void) {
    sp_ai_health_reference_count = 0;
    sp_ai_health_comparison_pending = NO;
}
static void sp_ai_finish_health_comparison(NSTimeInterval now) {
    if (!sp_ai_health_comparison_pending) return;
    uint8_t reference;
    SPHealthComparison result = sp_ai_compare_visible_health(sp_ai_health_reference, sp_ai_health_reference_count,
        sp_ai_health_visual_at, sp_ai_health_visual_result, now, &reference);
    if (result == SP_HEALTH_COMPARE_PENDING) return;
    sp_ai_health_comparison_pending = NO;
    static const char *const status[] = {"pending", "paired", "unreadable", "changing", "unknown", "unbracketed"};
    sp_stub_log([[NSString stringWithFormat:@"AI health validation: %s visual=%u public=%u", status[result],
        (unsigned)sp_ai_health_visual_result, (unsigned)reference] UTF8String]);
}
static void sp_ai_record_health_reference(NSTimeInterval at, uint8_t hp) {
    if (!atomic_load(&sp_ai_health_interval_ms)) return;
    unsigned count = sp_ai_health_reference_count;
    if (count && at <= sp_ai_health_reference[count - 1].at) return;
    if (count == sizeof sp_ai_health_reference / sizeof sp_ai_health_reference[0]) {
        --count;
        memmove(sp_ai_health_reference, sp_ai_health_reference + 1, count * sizeof sp_ai_health_reference[0]);
    }
    sp_ai_health_reference[count] = (SPHealthReference){at, hp};
    sp_ai_health_reference_count = count + 1;
    sp_ai_finish_health_comparison(at);
}
static void sp_ai_health_set_interval(unsigned interval) {
    unsigned previous = atomic_exchange(&sp_ai_health_interval_ms, interval);
    if (interval || !previous) return;
    atomic_fetch_add(&sp_ai_health_capture_epoch, 1);
    sp_ai_health_visual_result = SP_VISUAL_HP_UNKNOWN;
    sp_ai_health_visual_at = 0;
    sp_ai_clear_health_comparison();
}
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
    if ([move isEqualToString:@"TURN_LEFT"]) return SP_TURN_LEFT;
    if ([move isEqualToString:@"TURN_RIGHT"]) return SP_TURN_RIGHT;
    return SP_MOVE_NONE;
}

// State emitted by the game's own read-only addon API. Written and read on main.
static uint8_t sp_ai_game_flags, sp_ai_game_hp, sp_ai_game_target_hp, sp_ai_game_meta, sp_ai_game_move_keys;
static SPAIFarmFeedback sp_ai_game_feedback;
static uint8_t sp_ai_game_corpse;
static SPAIOwnHit sp_ai_game_hit;
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

static NSString *const sp_ai_approach_model_key = @"sp_wolkara_approach_feedback_v2";
static SPAIApproachModel sp_ai_load_approach_model(void) {
    SPAIApproachModel model = {0};
    NSData *data = [NSUserDefaults.standardUserDefaults dataForKey:sp_ai_approach_model_key];
    if (data.length != sizeof model) return model;
    [data getBytes:&model length:sizeof model];
    for (unsigned side = 0; side < 2; ++side)
        for (unsigned move = 0; move < 2; ++move)
            if (model.trials[side][move] > 100 || model.progress[side][move] > model.trials[side][move])
                return (SPAIApproachModel){0};
    return model;
}
static void sp_ai_save_approach_model(SPAIApproachModel model) {
    NSData *data = [NSData dataWithBytes:&model length:sizeof model];
    [NSUserDefaults.standardUserDefaults setObject:data forKey:sp_ai_approach_model_key];
}
static BOOL sp_ai_heartbeat_seen;
static BOOL sp_ai_health_known(uint8_t value) { return sp_ai_hp_known(value); }
static SPAIDecision sp_ai_current_decision(NSTimeInterval now) {
    return sp_ai_decision(sp_ai_game_at > 0 && now-sp_ai_game_at < 3.0,
        sp_ai_game_flags,sp_ai_game_hp,sp_ai_game_target_hp,sp_ai_game_meta);
}
static uint8_t sp_ai_heartbeat_seq;
static uint8_t sp_ai_pose_seq;
static uint8_t sp_ai_xp_seq;
static SPAIWorldPose sp_ai_pose;
static SPAIProgression sp_ai_progress;
static NSTimeInterval sp_ai_pose_at;
static NSTimeInterval sp_ai_xp_at;
static uint8_t sp_ai_health_seq;
static NSTimeInterval sp_ai_health_at;
static BOOL sp_ai_packed_heartbeat;
static void sp_ai_set_pose(uint8_t seq, const uint8_t *data, unsigned length, NSTimeInterval observedAt) {
    sp_ai_pose = data ? sp_ai_world_pose(data, length) : (SPAIWorldPose){0};
    sp_ai_pose.observedAt = observedAt;
    sp_ai_pose.sequence = seq;
    sp_ai_pose_seq = seq;
    sp_ai_pose_at = observedAt;
}

static void sp_ai_pose_heartbeat(uint8_t seq, const uint8_t *data, unsigned length, NSTimeInterval observedAt) {
    if (sp_ai_packed_heartbeat || observedAt <= sp_ai_pose_at ||
        (sp_ai_pose_at > 0 && observedAt - sp_ai_pose_at < 1.0 && seq == sp_ai_pose_seq)) return;
    sp_ai_set_pose(seq, data, length, observedAt);
}

static SPAIWorldPose sp_ai_game_pose(SPAINavSample sample) {
    if (sp_ai_pose_seq == sp_ai_heartbeat_seq && sp_ai_pose.epoch == sample.evidence.position &&
        fabs(sp_ai_pose_at - sample.at) < 0.4) return sp_ai_pose;
    return (SPAIWorldPose){0};
}

static void sp_ai_xp_heartbeat(uint8_t seq, const uint8_t *data, unsigned length, NSTimeInterval observedAt) {
    if (observedAt <= sp_ai_xp_at || (sp_ai_xp_at > 0 && observedAt - sp_ai_xp_at < 2.0 && seq == sp_ai_xp_seq)) return;
    sp_ai_progress = sp_ai_progression(data, length);
    sp_ai_xp_seq = seq;
    sp_ai_xp_at = observedAt;
}

static void sp_ai_health_heartbeat(uint8_t seq, const uint8_t *data, unsigned length, NSTimeInterval observedAt) {
    if (observedAt <= sp_ai_health_at || (sp_ai_health_at > 0 && observedAt - sp_ai_health_at < 2.0 && seq == sp_ai_health_seq))
        return;
    sp_ai_health_seq = seq;
    sp_ai_health_at = observedAt;
    uint64_t bounds = sp_ai_health_region(data, length);
    if (atomic_exchange(&sp_ai_health_bounds, bounds) != bounds) {
        atomic_fetch_add(&sp_ai_health_capture_epoch, 1);
        sp_ai_health_visual_result = SP_VISUAL_HP_UNKNOWN;
        sp_ai_health_visual_at = 0;
        sp_ai_clear_health_comparison();
    }
    atomic_store(&sp_ai_health_bounds_ms, (uint64_t)(observedAt * 1000));
}

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
        sp_ai_game_hp = SP_VISUAL_HP_UNKNOWN;
        sp_ai_game_move_keys = 0;
        sp_ai_game_feedback = (SPAIFarmFeedback){0};
        sp_ai_game_corpse = 0;
        sp_ai_game_hit = (SPAIOwnHit){0};
        sp_ai_game_evidence = (SPAINavEvidence){0, 0, 0, SP_AI_DISTANCE_UNKNOWN};
        sp_ai_player_health = sp_ai_target_health = SP_HEALTH_UNSPECIFIED;
        sp_ai_record_health_reference(observedAt, SP_VISUAL_HP_UNKNOWN);
        return;
    }
    SPAIHealthStatus player = sp_ai_health_status(data, (unsigned)length, false);
    uint8_t publicHP = player == SP_HEALTH_PUBLIC ? data[3] : SP_VISUAL_HP_UNKNOWN;
    if (sp_ai_game_at <= 0 || sp_ai_packet_at - sp_ai_game_at >= 6.0 ||
        sp_ai_health_known(sp_ai_game_hp) != sp_ai_health_known(publicHP) ||
        sp_ai_health_known(sp_ai_game_target_hp) != sp_ai_health_known(data[4]))
        sp_stub_log((publicHP == SP_VISUAL_HP_UNKNOWN || data[4] == 255) ?
            "AI telemetry: public decision flags valid; health unknown" : "AI telemetry: valid game-state payload");
    sp_ai_payload_status = 1;
    sp_ai_state_reason = -1;
    sp_ai_game_flags = data[2];
    sp_ai_game_hp = publicHP;
    sp_ai_game_target_hp = data[4];
    sp_ai_game_meta = data[5];
    sp_ai_game_move_keys = sp_ai_movement_bindings(data, (unsigned)length);
    sp_ai_game_feedback = sp_ai_farm_feedback(data, (unsigned)length);
    sp_ai_game_corpse = sp_ai_corpse_evidence(data, (unsigned)length);
    sp_ai_game_hit = sp_ai_own_hit(data, (unsigned)length);
    sp_ai_game_evidence = sp_ai_nav_evidence(data, (unsigned)length);
    SPAIHealthStatus target = sp_ai_health_status(data, (unsigned)length, true);
    if (player != sp_ai_player_health || target != sp_ai_target_health) {
        static const char *const health[] = {"public", "unavailable", "restricted", "absent", "unspecified"};
        sp_stub_log([[NSString stringWithFormat:@"AI health evidence: player=%s target=%s", health[player], health[target]] UTF8String]);
    }
    sp_ai_player_health = player;
    sp_ai_target_health = target;
    sp_ai_game_at = observedAt;
    sp_ai_record_health_reference(observedAt, publicHP);
}

static BOOL sp_ai_accept_heartbeat(uint8_t seq, NSTimeInterval observedAt) {
    static NSTimeInterval lastHeartbeat;
    if (observedAt <= lastHeartbeat || (sp_ai_heartbeat_seen && seq == sp_ai_heartbeat_seq)) return NO;
    if (!sp_ai_heartbeat_seen) sp_stub_log("AI telemetry: independent heartbeat detected");
    sp_ai_heartbeat_seen = YES;
    sp_ai_heartbeat_seq = seq;
    lastHeartbeat = observedAt;
    return YES;
}

static void sp_ai_heartbeat(uint8_t seq, const uint8_t *data, size_t length, NSTimeInterval observedAt) {
    if (!sp_ai_accept_heartbeat(seq, observedAt)) return;
    sp_ai_packed_heartbeat = NO;
    sp_ai_game_update(data, length, observedAt);
}

static void sp_ai_bundle_heartbeat(uint8_t seq, const uint8_t *data, unsigned length, NSTimeInterval observedAt) {
    SPAIObservationBundle bundle = sp_ai_strip_bundle(data, length);
    if (!bundle.state || !sp_ai_accept_heartbeat(seq, observedAt)) return;
    sp_ai_packed_heartbeat = YES;
    sp_ai_set_pose(seq, bundle.pose, SP_AI_STRIP_RECORD_BYTES, observedAt);
    if (bundle.progression) sp_ai_xp_heartbeat(seq, bundle.progression, SP_AI_STRIP_RECORD_BYTES, observedAt);
    if (bundle.health) sp_ai_health_heartbeat(seq, bundle.health, SP_AI_STRIP_RECORD_BYTES, observedAt);
    sp_ai_game_update(bundle.state, SP_AI_STRIP_RECORD_BYTES, observedAt);
}

@interface SPGameAIController : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL manualPaused;
@property(nonatomic) BOOL autonomousTest;
@property(nonatomic) BOOL observationSelected;
@property(nonatomic) BOOL modelDiagnostics;
@property(nonatomic) BOOL healthDiagnostics;
@property(nonatomic, copy) BOOL (^action)(NSString *, CGPoint, NSTimeInterval, NSTimeInterval);
@property(nonatomic, copy) void (^releaseInput)(void);
@property(nonatomic, copy) void (^status)(NSString *);
- (void)start;
- (void)stop;
- (void)yieldToManualInput;
- (void)resumeFromManualInput;
- (void)recordRouteMark;
- (void)clearGrindRoute;
- (void)recordManualProbe:(SPAINavPulse)pulse outcome:(SPAINavOutcome)outcome;
- (void)invalidateDecision;
- (void)toggleTeaching;
- (void)recordManualSteering:(CGPoint)delta;
@end

@interface SPGameAIController (EncounterAdapter)
- (BOOL)submit:(NSString *)action forSample:(SPAINavSample)sample hold:(NSTimeInterval)hold;
- (void)recordNavigation:(SPAINavOutcome)outcome before:(SPAINavSample)before after:(SPAINavSample)after;
@end

static bool sp_ai_submit_input(void *context, const char *action, SPAINavSample sample, double hold) {
    SPGameAIController *controller = (__bridge SPGameAIController *)context;
    return [controller submit:[NSString stringWithUTF8String:action] forSample:sample hold:hold];
}

static void sp_ai_release_input(void *context) {
    SPGameAIController *controller = (__bridge SPGameAIController *)context;
    if (controller.releaseInput) controller.releaseInput();
}

static void sp_ai_navigation_outcome(void *context, SPAINavOutcome outcome, SPAINavSample before, SPAINavSample after) {
    SPGameAIController *controller = (__bridge SPGameAIController *)context;
    [controller recordNavigation:outcome before:before after:after];
}

static void sp_ai_note_event(void *context, const char *message) {
    (void)context;
    sp_stub_log(message);
}

@implementation SPGameAIController {
    BOOL _active;
    BOOL _manualPaused;
    NSTimeInterval _manualResumeAt;
    NSTimeInterval _lastFreshGameAt;
    NSUInteger _run;
    BOOL _layaEnabled, _layaPending;
    NSString *_layaState, *_lastPhase;
    NSString *_lastWorldSummary;
    NSString *_lastHealthCaptureState;
    NSString *_lastProgressSummary;
    SPAIProgression _lastProgress;
    NSTimeInterval _lastProgressAt;
    SPAIEncounter _encounter;
    SPAIRoute _grindRoute;
    SPAIWorldPose _recordedLegStart;
    SPAIWorldPose _recordedFirstMotion, _recordedLastMotion;
    BOOL _recordedForward, _recordedOtherDirection;
    NSUInteger _routeRecordingGeneration;
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
- (BOOL)manualPaused { return _manualPaused; }

- (void)yieldToManualInput {
    if (!_active) return;
    if (_manualPaused || (!self.autonomousTest && !self.modelDiagnostics)) return;
    _manualPaused = YES;
    SPAIEncounterAdapter adapter = {(__bridge void *)self, sp_ai_submit_input, sp_ai_release_input,
        sp_ai_navigation_outcome, sp_ai_note_event};
    sp_ai_suspend_encounter(&_encounter, adapter);
    sp_p2p_enable(NO);
    sp_ai_health_set_interval(0);
    [self invalidateDecision];
    [self showPhase:@"AI PAUSED"];
}

- (void)resumeFromManualInput {
    if (!_active || !_manualPaused) return;
    _manualResumeAt = NSProcessInfo.processInfo.systemUptime + 1.0;
    _manualPaused = NO;
}

- (void)sampleRecordedLeg:(NSUInteger)generation {
    if (generation != _routeRecordingGeneration || !_recordedLegStart.valid || _active) return;
    SPAIWorldPose pose = sp_ai_game_pose(sp_ai_game_sample());
    if (pose.valid && pose.headingKnown && sp_ai_sample_fresh(pose.observedAt, NSProcessInfo.processInfo.systemUptime)) {
        if (pose.map != _recordedLegStart.map || pose.epoch != _recordedLegStart.epoch ||
            sp_ai_heading_delta(pose.heading, _recordedLegStart.heading) > 5) {
            _recordedOtherDirection = YES;
        } else {
            if (!_recordedFirstMotion.valid) _recordedFirstMotion = pose;
            _recordedLastMotion = pose;
        }
    }
    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(),
        ^{ [weak sampleRecordedLeg:generation]; });
}

- (void)recordRouteMark {
    if (_active) return;
    SPAINavSample sample = sp_ai_game_sample();
    SPAIWorldPose pose = sp_ai_game_pose(sample);
    NSString *status;
    if (!sp_ai_sample_fresh(sample.at, NSProcessInfo.processInfo.systemUptime) || !pose.valid || !pose.headingKnown) {
        status = @"ROUTE DATA";
    } else if (!_recordedLegStart.valid) {
        _recordedLegStart = pose;
        _recordedFirstMotion = _recordedLastMotion = (SPAIWorldPose){0};
        _recordedForward = _recordedOtherDirection = NO;
        status = @"LEG START";
        [self sampleRecordedLeg:++_routeRecordingGeneration];
    } else {
        BOOL added = _recordedForward && !_recordedOtherDirection && sp_ai_route_append(&_grindRoute, _recordedLegStart, pose);
        if (added) {
            SPAIRouteLeg *leg = &_grindRoute.legs[_grindRoute.count - 1];
            sp_ai_route_calibrate_leg(leg, _recordedFirstMotion, _recordedLastMotion);
            status = leg->calibrated ? [NSString stringWithFormat:@"LEGS %u", _grindRoute.count] : @"LEG NO CAL";
        } else {
            status = @"LEG INVALID";
        }
        _recordedLegStart = (SPAIWorldPose){0};
        ++_routeRecordingGeneration;
    }
    if (self.status) self.status(status);
}

- (void)clearGrindRoute {
    if (_active) return;
    _grindRoute = (SPAIRoute){0};
    _recordedLegStart = (SPAIWorldPose){0};
    ++_routeRecordingGeneration;
    if (self.status) self.status(@"ROUTE EMPTY");
}

- (void)recordManualProbe:(SPAINavPulse)pulse outcome:(SPAINavOutcome)outcome {
    if (_active || (sp_ai_game_flags & (2|32|64))) return;
    SPAIApproachModel model = sp_ai_load_approach_model();
    if (sp_ai_train_approach(&model, pulse.before, pulse.move, outcome)) sp_ai_save_approach_model(model);
}

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
    if (_recordedLegStart.valid && hypot(delta.x, delta.y) >= 12) {
        if (-delta.y >= 12 && fabs(delta.x) <= -delta.y * 0.25) {
            _recordedForward = YES;
        } else {
            _recordedOtherDirection = YES;
        }
    }
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
    if (_encounter.pulse.deadline) sp_stub_log("AI navigation: cancelled");
    sp_ai_cancel_steering(&_encounter);
    // Keep single-flight ownership until the previous callback finishes.
    Class p2p = NSClassFromString(@"SPP2PBridge");
    SEL reset = NSSelectorFromString(@"resetHistory");
    if ([p2p respondsToSelector:reset]) ((void (*)(id, SEL))objc_msgSend)(p2p, reset);
}

- (void)stop {
    if (!_active) return;
    _active = NO;
    _manualPaused = NO;
    _manualResumeAt = 0;
    _visualPreviewMode = NO;
    _visualPreviewStatus = nil;
    _visualPreviewAt = 0;
    sp_p2p_enable(NO);
    sp_ai_health_set_interval(0);
    ++_run;
    if (self.releaseInput) self.releaseInput();
    [self invalidateDecision];
    if (self.status) self.status(@"AI OFF");
}
- (void)fail:(NSString *)reason {
    [self stop];
    if (self.status) self.status(reason);
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
    unsigned loot = sp_ai_game_corpse & (SP_CORPSE_LOOT_NONE|SP_CORPSE_LOOT_AVAILABLE);
    unsigned range = sp_ai_game_corpse & (SP_CORPSE_RANGE_OUT|SP_CORPSE_RANGE_IN);
    SPAIWorldPose pose = sp_ai_game_pose(sample);
    NSString *summary = [NSString stringWithFormat:
        @"target=%@ identity=%@ plate=%@ position=%@ distance=%@ combat=%@ tab=%@ f12=%@ kill=%@ loot=%@ interact-range=%@ pose=%@ heading=%@ target-vector=%@",
        target, sample.evidence.target ? @"public" : @"unknown", direction,
        sample.evidence.position && sample.motion.source == SP_MOTION_POSITION ? @"public" : @"unknown",
        sample.evidence.distance == SP_AI_DISTANCE_UNKNOWN ? @"unknown" : @"public",
        (sp_ai_game_flags & 32) ? @"yes" : @"no",
        (sample.evidence.bindings & SP_AI_TAB_BOUND) ? @"verified" : @"unknown",
        (sample.evidence.bindings & SP_AI_ROTATION_BOUND) ? @"verified" : @"unknown",
        (sp_ai_game_corpse & SP_CORPSE_LOCAL_KILL) ? @"player-or-pet" : @"unknown",
        loot == SP_CORPSE_LOOT_AVAILABLE ? @"available" : loot == SP_CORPSE_LOOT_NONE ? @"none" : @"unknown",
        range == SP_CORPSE_RANGE_IN ? @"in" : range == SP_CORPSE_RANGE_OUT ? @"out" : @"unknown",
        pose.valid ? @"public" : @"unknown", pose.valid && pose.headingKnown ? @"public" : @"unknown",
        pose.valid && pose.targetKnown ? @"public" : @"unknown"];
    if ([_lastWorldSummary isEqualToString:summary]) return;
    _lastWorldSummary = summary;
    sp_stub_log([[@"AI world: " stringByAppendingString:summary] UTF8String]);
}

- (void)observeProgression:(NSTimeInterval)now {
    SPAIProgression current = now - sp_ai_xp_at < 2.5 ? sp_ai_progress : (SPAIProgression){0};
    NSString *xp = current.xpKnown ? [NSString stringWithFormat:@"%u/%u level=%u",
        current.xp, current.maximum, (unsigned)current.level] : @"unknown";
    NSString *quests = current.questCountKnown ? [NSString stringWithFormat:@"%u", (unsigned)current.quests] : @"unknown";
    NSString *summary = [NSString stringWithFormat:@"xp=%@ quests=%@", xp, quests];
    BOOL continuous = _lastProgressAt > 0 && sp_ai_xp_at - _lastProgressAt < 2.5;
    SPAIXPOutcome outcome = continuous ? sp_ai_xp_outcome(_lastProgress, current) : SP_XP_UNVERIFIED;
    _lastProgressAt = (current.xpKnown || current.questCountKnown) ? sp_ai_xp_at : 0;
    _lastProgress = current;
    if ([_lastProgressSummary isEqualToString:summary]) return;
    const char *change = outcome == SP_XP_GAINED ? "gain" : outcome == SP_XP_LEVEL_UP ? "level-up" : "snapshot";
    sp_stub_log([[NSString stringWithFormat:@"AI progression: %s %@", change, summary] UTF8String]);
    _lastProgressSummary = summary;
}

- (BOOL)submit:(NSString *)action forSample:(SPAINavSample)sample hold:(NSTimeInterval)hold {
    BOOL accepted = self.autonomousTest && !_manualPaused && self.action && self.action(action, CGPointZero, sample.at, hold);
    sp_stub_log([[NSString stringWithFormat:@"AI action: rules %@ observation %.3f adapter %@",
        action, sample.at, accepted ? @"accepted" : @"rejected"] UTF8String]);
    return accepted;
}

- (void)recordNavigation:(SPAINavOutcome)outcome before:(SPAINavSample)before after:(SPAINavSample)after {
    if (_encounter.approachModelDirty) {
        sp_ai_save_approach_model(_encounter.approachModel);
        _encounter.approachModelDirty = NO;
    }
    const char *name = sp_ai_nav_outcome_name(outcome);
    sp_stub_log([[NSString stringWithFormat:
        @"AI navigation: %s target %u/%u position %u/%u counter %u/%u column %u/%u distance-q4 %u/%u",
        name, (unsigned)before.evidence.target, (unsigned)after.evidence.target,
        (unsigned)before.evidence.position, (unsigned)after.evidence.position,
        (unsigned)before.motion.counter, (unsigned)after.motion.counter,
        before.column, after.column, (unsigned)before.evidence.distance,
        (unsigned)after.evidence.distance] UTF8String]);
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    NSString *key = [@"sp_ai_navigation_count_" stringByAppendingString:[NSString stringWithUTF8String:name]];
    NSInteger count = [prefs integerForKey:key];
    if (count < 10000) [prefs setInteger:count + 1 forKey:key];
}

- (NSString *)advance:(SPAINavSample)sample now:(NSTimeInterval)now reduced:(BOOL)reduced {
    SPAIEncounterAdapter adapter = {(__bridge void *)self, sp_ai_submit_input, sp_ai_release_input,
        sp_ai_navigation_outcome, sp_ai_note_event};
    if (!sp_ai_heartbeat_seen || !sp_ai_sample_fresh(sample.at, now)) {
        sp_ai_stale_encounter(&_encounter, sample, adapter);
        if (sp_ai_strip_at <= 0 || now-sp_ai_strip_at >= 6.0) return @"AI STRIP";
        if (sp_ai_packet_at <= 0 || now-sp_ai_packet_at >= 6.0) return @"AI SYNC";
        return sp_ai_state_reason > 0 ? [NSString stringWithFormat:@"AI DATA %d", sp_ai_state_reason] : @"AI STALE";
    }
    SPAIEncounterObservation observation = {sample, sp_ai_game_flags, sp_ai_game_hp, sp_ai_game_target_hp,
        sp_ai_game_meta, sp_ai_game_move_keys, sp_ai_game_corpse, sp_ai_player_health, sp_ai_game_pose(sample), sp_ai_game_hit};
    const char *phase = sp_ai_advance(&_encounter, observation, now, reduced, &_approachExamples, adapter);
    return [NSString stringWithUTF8String:phase];
}

- (void)pollDirect:(NSUInteger)run {
    if (!_active || _run != run) return;
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSTimeInterval now = process.systemUptime;
    NSProcessInfoThermalState thermal = process.thermalState;
    BOOL reduced = thermal >= NSProcessInfoThermalStateSerious;
    BOOL diagnosticsRequested = self.modelDiagnostics && !self.autonomousTest;
    SPAINavSample sample = sp_ai_game_sample();
    BOOL fresh = sp_ai_sample_fresh(sample.at, now);
    if (fresh) _lastFreshGameAt = now;
    else if (self.autonomousTest && now - _lastFreshGameAt >= 6.0) {
        self.autonomousTest = NO;
        [self fail:@"AI MODE"];
        return;
    }
    BOOL paused = _manualPaused || (_manualResumeAt > 0 && (!fresh || sample.at <= _manualResumeAt));
    if (!paused) _manualResumeAt = 0;
    BOOL preview = diagnosticsRequested && !paused && thermal == NSProcessInfoThermalStateNominal;
    BOOL healthDiag = self.healthDiagnostics && !self.autonomousTest;
    BOOL waitingForHealth = self.autonomousTest && !sp_ai_health_known(sp_ai_game_hp);
    _Static_assert(NSProcessInfoThermalStateNominal == 0 && NSProcessInfoThermalStateFair == 1 &&
                   NSProcessInfoThermalStateSerious == 2 && NSProcessInfoThermalStateCritical == 3,
                   "Health capture cadence must match iOS thermal states");
    unsigned healthInterval = sp_ai_health_capture_interval_ms((unsigned)thermal, healthDiag || waitingForHealth, paused, fresh);
    sp_ai_health_set_interval(healthInterval);
    if (healthInterval) sp_ai_finish_health_comparison(now);
    BOOL cropAvailable = (healthDiag || waitingForHealth) && atomic_load(&sp_ai_health_bounds) &&
        sp_ai_health_bounds_fresh(atomic_load(&sp_ai_health_bounds_ms), (uint64_t)(now * 1000));
    if (healthDiag || waitingForHealth) {
        NSString *state = !fresh ? @"stale telemetry" : paused ? @"manual input" :
            !healthInterval ? @"thermal pause" : !cropAvailable ? @"layout unavailable" :
            [NSString stringWithFormat:@"layout available, interval %u ms", healthInterval];
        if (![state isEqualToString:_lastHealthCaptureState]) {
            _lastHealthCaptureState = state;
            sp_stub_log([[NSString stringWithFormat:@"AI health capture: %@", state] UTF8String]);
        }
    } else _lastHealthCaptureState = nil;
    NSTimeInterval interval = reduced ? 0.8 : 0.4;
    if (thermal != _lastThermal || !_lastPhase) {
        _lastThermal = thermal;
        if (thermal >= NSProcessInfoThermalStateCritical) {
            sp_stub_log("AI thermal: critical, stopping");
        } else {
            NSString *diagnostics = preview ? @"allowed" : (diagnosticsRequested ? @"paused" : @"off");
            sp_stub_log([[NSString stringWithFormat:@"AI thermal: %ld poll=%.1fs model-diagnostics=%@",
                (long)thermal, interval, diagnostics] UTF8String]);
        }
    }
    if (thermal >= NSProcessInfoThermalStateCritical) { [self fail:@"AI HEAT"]; return; }
    if (fresh) {
        [self observeWorld:sample];
        [self observeProgression:now];
    }

    if (preview != _visualPreviewMode) {
        [self invalidateDecision];
        _visualPreviewMode = preview;
    }
    sp_p2p_enable(preview && _p2pAvailable && !_visualPreviewError);
    if (paused) {
        [self showPhase:@"AI PAUSED"];
    } else if (self.autonomousTest) {
        [self showPhase:[self advance:sample now:now reduced:reduced]];
    } else if (healthDiag) {
        NSString *status = fresh ? @"HP PAUSED" : @"AI STALE";
        if (healthInterval) {
            BOOL sampleFresh = sp_ai_health_visual_at > 0 && now - sp_ai_health_visual_at < 2.0;
            status = @"HP NO VIEW";
            if (cropAvailable) {
                if (!sampleFresh) status = @"HP WAIT";
                else if (sp_ai_health_visual_result != SP_VISUAL_HP_UNKNOWN)
                    status = [NSString stringWithFormat:@"HP≈%u%%", (unsigned)sp_ai_health_visual_result];
            }
        }
        [self showPhase:status];
    } else if (preview) {
        if (fresh) {
            SPAIDecision decision = sp_ai_current_decision(now);
            NSString *candidate = decision == SP_AI_TARGET ? @"TARGET" : decision == SP_AI_ATTACK ? @"ATTACK" : nil;
            [self evaluateLaya:candidate combat:(sp_ai_game_flags & 32) != 0 run:run];
        }
        [self previewP2P:run];
        NSString *status = !_p2pAvailable ? (_layaEnabled ? @"LAYA DIAG" : @"MODEL FILE") : _visualPreviewError ? @"MODEL ERROR" :
            (_visualPreviewStatus && now-_visualPreviewAt < 5.0 ? _visualPreviewStatus : @"VIS LOAD");
        [self showPhase:status];
    } else {
        [self showPhase:fresh ? @"OBS ONLY" : @"AI STALE"];
    }

    __weak SPGameAIController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [weak pollDirect:run]; });
}
- (void)start {
    if (_active) return;
    _recordedLegStart = (SPAIWorldPose){0};
    ++_routeRecordingGeneration;
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
    _manualPaused = NO;
    _manualResumeAt = 0;
    _lastFreshGameAt = NSProcessInfo.processInfo.systemUptime;
    _lastWorldSummary = nil;
    _lastHealthCaptureState = nil;
    _lastProgressSummary = nil;
    _lastProgress = (SPAIProgression){0};
    _lastProgressAt = 0;
    _encounter = (SPAIEncounter){.combatEvidence.lastHP = 255};
    _encounter.route = _grindRoute;
    _encounter.approachModel = sp_ai_load_approach_model();
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

@end
