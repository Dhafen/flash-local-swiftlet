// Pure decision policy for the opt-in authorized test environment.
#ifndef SP_AI_DIRECT_H
#define SP_AI_DIRECT_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { SP_AI_WAIT, SP_AI_REST, SP_AI_TARGET, SP_AI_ATTACK, SP_AI_BIND, SP_AI_LOOT, SP_AI_LOOT_BIND, SP_AI_LOOT_WAIT } SPAIDecision;
static inline bool sp_ai_hp_known(uint8_t hp) { return hp <= 100; }
static inline bool sp_ai_hostile(uint8_t flags, uint8_t hp) {
    return (flags & 4) && (flags & 8) && !(flags & 16) && (!sp_ai_hp_known(hp) || hp > 0);
}
static inline SPAIDecision sp_ai_decision(bool fresh, uint8_t flags, uint8_t hp, uint8_t targetHP, uint8_t meta) {
    if (!fresh || !(flags & 1)) return SP_AI_WAIT;
    if ((flags & (2|64)) || (sp_ai_hp_known(hp) && hp < 35)) return SP_AI_REST;
    if (!sp_ai_hostile(flags,targetHP)) return (flags & 32) ? SP_AI_WAIT : SP_AI_TARGET;
    // Reject a publicly confirmed incorrect binding. Unknown is not proof of binding.
    if ((meta & 128) && (meta & 2)) return SP_AI_BIND;
    return SP_AI_ATTACK;
}
typedef enum {
    SP_MOVE_NONE, SP_MOVE_FORWARD, SP_MOVE_BACK, SP_MOVE_LEFT, SP_MOVE_RIGHT, SP_TURN_LEFT, SP_TURN_RIGHT
} SPAIMove;
enum { SP_KEY_ARROW_LEFT = 128, SP_KEY_ARROW_RIGHT = 129 };

static inline uint8_t sp_ai_movement_bindings(const uint8_t *packet, unsigned length) {
    return length >= 8 && packet[6] == 'K' ? packet[7] : 0;
}

static inline uint8_t sp_ai_movement_key(SPAIMove move, uint8_t bindings) {
    switch (move) {
        case SP_MOVE_FORWARD: return (bindings & 1) ? 'w' : 0;
        case SP_MOVE_BACK: return (bindings & 2) ? 's' : 0;
        case SP_MOVE_LEFT: return (bindings & 4) ? 'q' : (bindings & 8) ? 'a' : 0;
        case SP_MOVE_RIGHT: return (bindings & 16) ? 'e' : (bindings & 32) ? 'd' : 0;
        case SP_TURN_LEFT: return (bindings & 64) ? SP_KEY_ARROW_LEFT : 0;
        case SP_TURN_RIGHT: return (bindings & 128) ? SP_KEY_ARROW_RIGHT : 0;
        default: return 0;
    }
}
static inline bool sp_ai_move_opposes(SPAIMove a, SPAIMove b) {
    return (a == SP_MOVE_FORWARD && b == SP_MOVE_BACK) || (a == SP_MOVE_BACK && b == SP_MOVE_FORWARD) ||
           (a == SP_MOVE_LEFT && b == SP_MOVE_RIGHT) || (a == SP_MOVE_RIGHT && b == SP_MOVE_LEFT);
}

// Confirmed local encounter, selected NPC corpse and combat ended.
static inline SPAIDecision sp_ai_farm_decision(SPAIDecision base, uint8_t flags, uint8_t meta,
    unsigned attempts, bool lootConfirmed) {
    if (base != SP_AI_TARGET || (flags & (4|16|128)) != (4|16|128) || lootConfirmed) return base;
    if ((meta & (128|4)) != (128|4)) return SP_AI_LOOT_BIND;
    return attempts < 2 ? SP_AI_LOOT : SP_AI_LOOT_WAIT;
}

typedef enum { SP_MOTION_UNKNOWN, SP_MOTION_POSITION, SP_MOTION_SPEED } SPAIMotionSource;
typedef struct {
    SPAIMotionSource source;
    uint8_t counter;
    bool lootConfirmed;
} SPAIFarmFeedback;

static inline SPAIFarmFeedback sp_ai_farm_feedback(const uint8_t *packet, unsigned length) {
    if (length < 12 || packet[8] != 'F' || packet[9] > SP_MOTION_SPEED) return (SPAIFarmFeedback){0};
    return (SPAIFarmFeedback){packet[9], packet[10], (packet[11] & 1) != 0};
}

enum {
    SP_CORPSE_LOCAL_KILL = 2, SP_CORPSE_LOOT_NONE = 4, SP_CORPSE_LOOT_AVAILABLE = 8,
    SP_CORPSE_RANGE_OUT = 16, SP_CORPSE_RANGE_IN = 32
};

static inline uint8_t sp_ai_corpse_evidence(const uint8_t *packet, unsigned length) {
    if (length < 12 || packet[8] != 'F' || (packet[2] & (4|16)) != (4|16)) return 0;
    return packet[11] & 62;
}

typedef struct { uint8_t count; bool known; } SPAIOwnHit;

static inline SPAIOwnHit sp_ai_own_hit(const uint8_t *packet, unsigned length) {
    if (length < 18 || packet[8] != 'F' || packet[12] != 'N' || !packet[13] ||
        (packet[17] & 192) != 192) return (SPAIOwnHit){0};
    return (SPAIOwnHit){packet[11] >> 6, true};
}

static inline bool sp_ai_farm_progress(SPAIFarmFeedback start, SPAIFarmFeedback current) {
    return start.source == SP_MOTION_POSITION && current.source == SP_MOTION_POSITION && current.counter != start.counter;
}

enum { SP_AI_DISTANCE_UNKNOWN = UINT16_MAX, SP_AI_TAB_BOUND = 1, SP_AI_ROTATION_BOUND = 2 };
typedef struct {
    uint8_t target, position, bindings;
    uint16_t distance;
} SPAINavEvidence;

static inline SPAINavEvidence sp_ai_nav_evidence(const uint8_t *packet, unsigned length) {
    if (length < 18 || packet[12] != 'N') return (SPAINavEvidence){0, 0, 0, SP_AI_DISTANCE_UNKNOWN};
    return (SPAINavEvidence){packet[13], packet[14], packet[17] & 3,
        (uint16_t)(packet[15] * 256 + packet[16])};
}

typedef enum {
    SP_HEALTH_PUBLIC, SP_HEALTH_UNAVAILABLE, SP_HEALTH_RESTRICTED, SP_HEALTH_ABSENT, SP_HEALTH_UNSPECIFIED
} SPAIHealthStatus;

static inline SPAIHealthStatus sp_ai_health_status(const uint8_t *packet, unsigned length, bool target) {
    if (length < 18 || packet[12] != 'N' || !(packet[17] & 64)) return SP_HEALTH_UNSPECIFIED;
    SPAIHealthStatus status = (packet[17] >> (target ? 4 : 2)) & 3;
    uint8_t hp = packet[target ? 4 : 3];
    if (target && !(packet[2] & 4))
        return status == SP_HEALTH_ABSENT && hp == 0 ? status : SP_HEALTH_UNSPECIFIED;
    if (status == SP_HEALTH_ABSENT || ((status == SP_HEALTH_PUBLIC) != sp_ai_hp_known(hp)))
        return SP_HEALTH_UNSPECIFIED;
    return status;
}

typedef enum { SP_AI_READY, SP_AI_HEALTH_HOLD, SP_AI_RECOVER, SP_AI_MOUNTED, SP_AI_DEAD } SPAIReadiness;

static inline SPAIReadiness sp_ai_readiness(uint8_t flags, uint8_t hp, bool *recovering) {
    if (sp_ai_hp_known(hp)) {
        if (hp < 35) *recovering = true;
        if (hp >= 50) *recovering = false;
    }
    if (flags & 2) return SP_AI_DEAD;
    if (flags & 64) return SP_AI_MOUNTED;
    if (!sp_ai_hp_known(hp)) return SP_AI_HEALTH_HOLD;
    return *recovering ? SP_AI_RECOVER : SP_AI_READY;
}

typedef struct {
    double at;
    SPAIFarmFeedback motion;
    SPAINavEvidence evidence;
    unsigned column;
} SPAINavSample;

static inline bool sp_ai_sample_fresh(double sampledAt, double now) {
    return sampledAt > 0 && now >= sampledAt && now - sampledAt < 0.85;
}

typedef struct {
    SPAIMove move;
    double observedAt;
    bool confirmed;
} SPAISteering;

static inline bool sp_ai_confirm_steering(SPAISteering *steering, SPAIMove move, double at) {
    if (move == SP_MOVE_NONE || at < steering->observedAt) {
        *steering = (SPAISteering){0};
        return false;
    }
    if (steering->move != move || !sp_ai_sample_fresh(steering->observedAt, at)) {
        *steering = (SPAISteering){move, at, false};
    } else if (at - steering->observedAt >= 0.12) {
        steering->observedAt = at;
        steering->confirmed = true;
    }
    return steering->confirmed;
}

typedef enum {
    SP_NAV_PENDING, SP_NAV_NO_SAMPLE, SP_NAV_CONTEXT_CHANGED, SP_NAV_STALLED,
    SP_NAV_DISPLACED, SP_NAV_CLOSER, SP_NAV_ALIGNED, SP_NAV_NO_PROGRESS
} SPAINavOutcome;

typedef struct {
    SPAINavSample before;
    SPAIMove move;
    double endedAt, deadline;
} SPAINavPulse;

static inline unsigned sp_ai_column_error(unsigned column) {
    return column > 8 ? column - 8 : 8 - column;
}

static inline SPAINavOutcome sp_ai_nav_outcome(SPAINavPulse pulse, SPAINavSample after, double now) {
    if (!pulse.before.evidence.position || pulse.before.motion.source != SP_MOTION_POSITION)
        return SP_NAV_NO_SAMPLE;
    if (after.at <= pulse.before.at || after.at < pulse.endedAt || after.at > pulse.deadline ||
        !sp_ai_sample_fresh(after.at, now))
        return now >= pulse.deadline ? SP_NAV_NO_SAMPLE : SP_NAV_PENDING;
    if (after.evidence.target != pulse.before.evidence.target ||
        (after.evidence.position && after.evidence.position != pulse.before.evidence.position))
        return SP_NAV_CONTEXT_CHANGED;
    if (!after.evidence.position || after.motion.source != SP_MOTION_POSITION)
        return now >= pulse.deadline ? SP_NAV_NO_SAMPLE : SP_NAV_PENDING;
    if (!sp_ai_farm_progress(pulse.before.motion, after.motion))
        return now >= pulse.deadline ? SP_NAV_STALLED : SP_NAV_PENDING;
    bool knownDistance = pulse.before.evidence.distance != SP_AI_DISTANCE_UNKNOWN &&
        after.evidence.distance != SP_AI_DISTANCE_UNKNOWN;
    if (knownDistance && after.evidence.distance + 2 <= pulse.before.evidence.distance)
        return SP_NAV_CLOSER;
    if ((pulse.move == SP_MOVE_LEFT || pulse.move == SP_MOVE_RIGHT) && pulse.before.column && after.column &&
        sp_ai_column_error(after.column) < sp_ai_column_error(pulse.before.column))
        return SP_NAV_ALIGNED;
    return knownDistance || ((pulse.move == SP_MOVE_LEFT || pulse.move == SP_MOVE_RIGHT) &&
        pulse.before.column && after.column) ? SP_NAV_NO_PROGRESS : SP_NAV_DISPLACED;
}

static inline SPAINavOutcome sp_ai_nav_observe(SPAINavPulse pulse, SPAINavSample *after, double now,
    SPAINavSample *lastInWindow) {
    if (after->at >= pulse.endedAt && after->at <= pulse.deadline && sp_ai_sample_fresh(after->at, now))
        *lastInWindow = *after;
    if (after->at > pulse.deadline && sp_ai_sample_fresh(after->at, now) && sp_ai_sample_fresh(lastInWindow->at, now)) {
        if (after->evidence.target != pulse.before.evidence.target ||
            (after->evidence.position && after->evidence.position != pulse.before.evidence.position))
            return SP_NAV_CONTEXT_CHANGED;
        *after = *lastInWindow;
    }
    return sp_ai_nav_outcome(pulse, *after, now);
}

static inline bool sp_ai_forward_probe_ready(SPAINavSample sample, uint8_t flags, uint8_t movementKeys, double now) {
    // Leave an eight-yard margin in this test. Distance is in quarter yards.
    return sp_ai_sample_fresh(sample.at, now) && (flags & (1|2|4|8|16|32|64)) == (1|4|8) &&
           sample.evidence.target && sample.evidence.position && sample.motion.source == SP_MOTION_POSITION &&
           sample.evidence.distance != SP_AI_DISTANCE_UNKNOWN && sample.evidence.distance > 32 &&
           sp_ai_movement_key(SP_MOVE_FORWARD, movementKeys);
}

static inline bool sp_ai_forward_probe_repeat(SPAINavOutcome outcome, unsigned remaining) {
    return outcome == SP_NAV_CLOSER && remaining > 1;
}

typedef struct {
    unsigned pulses, failures, unmeasured, reversals;
    SPAIMove lastLateral;
} SPAINavBudget;

static inline bool sp_ai_nav_budget_open(SPAINavBudget budget, SPAIMove next) {
    return budget.pulses < 12 && budget.failures < 2 && budget.unmeasured < 2 &&
        !(budget.reversals >= 1 && sp_ai_move_opposes(budget.lastLateral, next));
}

static inline void sp_ai_nav_accept(SPAINavBudget *budget, SPAIMove move) {
    if (move == SP_MOVE_LEFT || move == SP_MOVE_RIGHT) {
        if (sp_ai_move_opposes(budget->lastLateral, move)) ++budget->reversals;
        budget->lastLateral = move;
    }
    ++budget->pulses;
}

static inline void sp_ai_nav_resolve(SPAINavBudget *budget, SPAINavOutcome outcome) {
    if (outcome == SP_NAV_CLOSER || outcome == SP_NAV_ALIGNED) {
        budget->failures = budget->unmeasured = 0;
    } else if (outcome == SP_NAV_DISPLACED) {
        ++budget->unmeasured;
    } else {
        ++budget->failures;
    }
}

typedef struct {
    unsigned attacks;
    uint8_t lastHP, probeHP;
    double observedAt, probedAt;
    bool measured;
    SPAIOwnHit lastOwnHit;
} SPAICombatEvidence;

static inline void sp_ai_accept_probe(SPAICombatEvidence *combat, double at) {
    ++combat->attacks;
    combat->probedAt = at;
    combat->probeHP = combat->lastHP;
    combat->measured = false;
}

static inline bool sp_ai_observe_damage(SPAICombatEvidence *combat, uint8_t hp, double observedAt) {
    if (observedAt <= combat->observedAt) return false;
    combat->observedAt = observedAt;
    bool decreased = sp_ai_hp_known(combat->lastHP) && sp_ai_hp_known(hp) && hp < combat->lastHP;
    combat->lastHP = hp;
    if (combat->attacks && observedAt > combat->probedAt) {
        if (!sp_ai_hp_known(hp)) combat->probeHP = 255;
        combat->measured = sp_ai_hp_known(combat->probeHP) && sp_ai_hp_known(hp);
    }
    return decreased;
}

static inline bool sp_ai_observe_own_damage(SPAICombatEvidence *combat, SPAIOwnHit hit, double at) {
    if (!hit.known) return false;
    bool changed = combat->lastOwnHit.known && hit.count != combat->lastOwnHit.count;
    combat->lastOwnHit = hit;
    if (!changed || !combat->attacks || at <= combat->probedAt) return false;
    combat->attacks = 0;
    return true;
}

static inline bool sp_ai_combat_budget_open(SPAICombatEvidence combat) {
    return combat.attacks < 4;
}

typedef enum { SP_ENGAGE_PROBE, SP_ENGAGE_APPROACH, SP_ENGAGE_NO_DAMAGE, SP_ENGAGE_DAMAGE_UNKNOWN } SPAIEngagement;

static inline SPAIEngagement sp_ai_engagement(SPAICombatEvidence combat, SPAIMove move, uint16_t distance,
    bool observedDamage, bool probeAfterMove) {
    if (!sp_ai_combat_budget_open(combat))
        return combat.measured ? SP_ENGAGE_NO_DAMAGE : SP_ENGAGE_DAMAGE_UNKNOWN;
    if (combat.attacks && !probeAfterMove && distance > 16 && !observedDamage && move != SP_MOVE_NONE)
        return SP_ENGAGE_APPROACH;
    return SP_ENGAGE_PROBE;
}

static inline SPAIMove sp_ai_visible_approach(uint8_t meta, unsigned attempts, bool combat, bool recentDamage) {
    unsigned column = (meta >> 3) & 15;
    if (!(meta & 128) || !column || attempts < 2) return SP_MOVE_NONE;
    if (column <= 6) return SP_MOVE_LEFT;
    if (column >= 10) return SP_MOVE_RIGHT;
    if (combat && recentDamage) return SP_MOVE_NONE;
    return SP_MOVE_FORWARD;
}

// Fit a small on-device steering table from manual samples. Learning can
// choose forward or toward the observed side, never reverse or steer away.
typedef struct { uint16_t forward[2], lateral[2]; } SPAIApproachExamples;
static inline void sp_ai_learn_approach(SPAIApproachExamples *examples, SPAIMove side, SPAIMove demonstrated) {
    if (side != SP_MOVE_LEFT && side != SP_MOVE_RIGHT) return;
    if (demonstrated != SP_MOVE_FORWARD && demonstrated != side) return;
    unsigned index = side == SP_MOVE_RIGHT;
    uint16_t *count = demonstrated == SP_MOVE_FORWARD ? &examples->forward[index] : &examples->lateral[index];
    if (*count < 100) ++*count;
}

// Two contexts, two candidate moves. Counts represent only measured outcomes.
typedef struct {
    uint16_t trials[2][2], progress[2][2];
} SPAIApproachModel;

static inline bool sp_ai_approach_model_context(SPAINavSample sample) {
    return sample.evidence.target && sample.evidence.position && sample.motion.source == SP_MOTION_POSITION &&
           sample.evidence.distance >= 32 && sample.evidence.distance <= 200 &&
           (sample.column == 6 || sample.column == 10);
}

static inline bool sp_ai_train_approach(SPAIApproachModel *model, SPAINavSample before,
    SPAIMove move, SPAINavOutcome outcome) {
    if (!sp_ai_approach_model_context(before)) return false;
    bool progress = outcome == SP_NAV_CLOSER || outcome == SP_NAV_ALIGNED;
    if (!progress && outcome != SP_NAV_STALLED && outcome != SP_NAV_NO_PROGRESS) return false;
    unsigned side = before.column == 10;
    if (move != SP_MOVE_FORWARD && move != (side ? SP_MOVE_RIGHT : SP_MOVE_LEFT)) return false;
    unsigned choice = move != SP_MOVE_FORWARD;
    uint16_t *trials = &model->trials[side][choice], *wins = &model->progress[side][choice];
    if (*trials >= 100) {
        *trials /= 2;
        *wins /= 2;
    }
    ++*trials;
    if (progress) ++*wins;
    return true;
}

static inline SPAIMove sp_ai_predict_approach(const SPAIApproachModel *model, SPAINavSample sample,
    SPAIMove proposed, bool combat) {
    if (combat || !sp_ai_approach_model_context(sample)) return proposed;
    unsigned side = sample.column == 10;
    if (proposed != (side ? SP_MOVE_RIGHT : SP_MOVE_LEFT)) return proposed;
    unsigned forward = model->trials[side][0], lateral = model->trials[side][1];
    if (forward < 6 || lateral < 6) return proposed;
    unsigned forwardWeight = (model->progress[side][0] + 1) * (lateral + 2);
    unsigned lateralWeight = (model->progress[side][1] + 1) * (forward + 2);
    return 4 * forwardWeight >= 4 * lateralWeight + (forward + 2) * (lateral + 2)
        ? SP_MOVE_FORWARD : proposed;
}

#endif
