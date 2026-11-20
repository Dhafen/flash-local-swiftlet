// Pure decision policy for the opt-in authorized test environment.
#ifndef SP_AI_DIRECT_H
#define SP_AI_DIRECT_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { SP_AI_WAIT, SP_AI_REST, SP_AI_TARGET, SP_AI_ATTACK, SP_AI_BIND, SP_AI_LOOT, SP_AI_LOOT_BIND } SPAIDecision;
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
static inline bool sp_ai_nav_allowed(SPAIDecision decision, uint8_t flags, unsigned attempts) {
    if (flags & (2|32|64)) return false;
    // A selected target with no combat after several F12 attempts may need movement.
    // Only use model-proposed movement; never presume range or direction is known.
    return decision == SP_AI_TARGET || (decision == SP_AI_ATTACK && attempts >= 2);
}
// A model proposal is advisory. Feedback is consumed once per completed input,
// and scene change is only a proxy for progress.
typedef enum { SP_MOVE_NONE, SP_MOVE_FORWARD, SP_MOVE_BACK, SP_MOVE_LEFT, SP_MOVE_RIGHT } SPAIMove;

static inline uint8_t sp_ai_movement_bindings(const uint8_t *packet, unsigned length) {
    return length >= 8 && packet[6] == 'K' ? packet[7] & 63 : 0;
}

static inline char sp_ai_movement_key(SPAIMove move, uint8_t bindings) {
    switch (move) {
        case SP_MOVE_FORWARD: return (bindings & 1) ? 'w' : 0;
        case SP_MOVE_BACK: return (bindings & 2) ? 's' : 0;
        case SP_MOVE_LEFT: return (bindings & 4) ? 'q' : (bindings & 8) ? 'a' : 0;
        case SP_MOVE_RIGHT: return (bindings & 16) ? 'e' : (bindings & 32) ? 'd' : 0;
        default: return 0;
    }
}
typedef struct {
    SPAIMove last, proposed;
    unsigned votes, stalls, streak;
    bool recoveryUsed, blocked;
} SPAINavigation;

static inline bool sp_ai_move_opposes(SPAIMove a, SPAIMove b) {
    return (a == SP_MOVE_FORWARD && b == SP_MOVE_BACK) || (a == SP_MOVE_BACK && b == SP_MOVE_FORWARD) ||
           (a == SP_MOVE_LEFT && b == SP_MOVE_RIGHT) || (a == SP_MOVE_RIGHT && b == SP_MOVE_LEFT);
}

static inline void sp_ai_nav_feedback(SPAINavigation *nav, bool changed) {
    if (changed) nav->stalls = 0;
    else if (nav->stalls < 2) ++nav->stalls;
    if (nav->stalls == 2 && nav->recoveryUsed) nav->blocked = true;
}

static inline SPAIMove sp_ai_nav_proposal(SPAINavigation *nav, SPAIMove move) {
    if (nav->blocked) return SP_MOVE_NONE;
    if (move != nav->proposed || move == SP_MOVE_NONE) {
        nav->proposed = move;
        nav->votes = 0;
    }
    if (move == SP_MOVE_NONE) return SP_MOVE_NONE;
    if (nav->votes < 3) ++nav->votes;
    if (nav->stalls == 2) {
        if (nav->votes < 2) return SP_MOVE_NONE;
        return nav->last == SP_MOVE_LEFT || nav->last == SP_MOVE_RIGHT ? SP_MOVE_FORWARD : SP_MOVE_LEFT;
    }
    unsigned required = move == nav->last ? 1 : sp_ai_move_opposes(nav->last, move) ? 3 : 2;
    return nav->votes >= required ? move : SP_MOVE_NONE;
}

// Confirmed local encounter, selected NPC corpse and combat ended.
static inline SPAIDecision sp_ai_farm_decision(SPAIDecision base, uint8_t flags, uint8_t meta, unsigned attempts) {
    if (base != SP_AI_TARGET || (flags & (4|16|128)) != (4|16|128) || attempts >= 2) return base;
    return (meta & (128|4)) == (128|4) ? SP_AI_LOOT : SP_AI_LOOT_BIND;
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

static inline SPAIMove sp_ai_apply_approach(const SPAIApproachExamples *examples, SPAIMove side, bool combat) {
    if (combat || (side != SP_MOVE_LEFT && side != SP_MOVE_RIGHT)) return side;
    unsigned index = side == SP_MOVE_RIGHT;
    return examples->forward[index] >= 4 && examples->forward[index] >= 2 * examples->lateral[index] + 2 ?
        SP_MOVE_FORWARD : side;
}

typedef enum {
    SP_FARM_PAUSE, SP_FARM_SEARCH, SP_FARM_ENGAGE, SP_FARM_APPROACH, SP_FARM_COMBAT, SP_FARM_LOOT
} SPAIFarmPhase;

typedef struct {
    SPAIFarmPhase phase;
    SPAIMove movement;
    bool usePixel2Play;
} SPAIFarmPlan;

// The planner owns the current phase. The controller still owns key timing,
// movement limits and cancellation, and executes at most one input per poll.
static inline SPAIFarmPlan sp_ai_plan_farm(SPAIDecision decision, uint8_t flags, uint8_t meta,
    unsigned attempts, bool recentDamage, const SPAIApproachExamples *examples) {
    if (decision == SP_AI_LOOT) return (SPAIFarmPlan){SP_FARM_LOOT, SP_MOVE_NONE, false};
    if (decision == SP_AI_TARGET)
        return (SPAIFarmPlan){SP_FARM_SEARCH, SP_MOVE_NONE, sp_ai_nav_allowed(decision, flags, attempts)};
    if (decision != SP_AI_ATTACK) return (SPAIFarmPlan){SP_FARM_PAUSE, SP_MOVE_NONE, false};
    bool combat = (flags & 32) != 0;
    if (combat && recentDamage) return (SPAIFarmPlan){SP_FARM_COMBAT, SP_MOVE_NONE, false};
    // An off-combat target with a visible nameplate can be approached from
    // the first poll. Missing direction still needs the existing attack probes.
    SPAIMove move = sp_ai_visible_approach(meta, combat ? attempts : 2, combat, recentDamage);
    if (move != SP_MOVE_NONE)
        return (SPAIFarmPlan){SP_FARM_APPROACH, sp_ai_apply_approach(examples, move, combat), false};
    if (attempts < 2) return (SPAIFarmPlan){SP_FARM_ENGAGE, SP_MOVE_NONE, false};
    if (combat) return (SPAIFarmPlan){SP_FARM_COMBAT, SP_MOVE_NONE, false};
    return (SPAIFarmPlan){SP_FARM_APPROACH, SP_MOVE_NONE, sp_ai_nav_allowed(decision, flags, attempts)};
}

static inline double sp_ai_direct_interval(SPAIDecision decision, bool moving) {
    if (decision == SP_AI_TARGET || moving) return 3.2;
    if (decision == SP_AI_LOOT) return 1.4;
    return 0.85;
}

static inline double sp_ai_nav_duration(const SPAINavigation *nav, SPAIMove move) {
    if (nav->stalls > 0) return 0.42;
    return nav->last == move && nav->streak >= 2 ? 0.70 : 0.55;
}

static inline void sp_ai_nav_sent(SPAINavigation *nav, SPAIMove move) {
    if (nav->stalls == 2) {
        nav->recoveryUsed = true;
        nav->stalls = 1; // Stop if the recovery pulse also fails.
        nav->proposed = SP_MOVE_NONE;
        nav->votes = 0;
    }
    if (nav->last != move) nav->streak = 1;
    else if (nav->streak < 3) ++nav->streak;
    nav->last = move;
}

static inline bool sp_ai_nav_has_slot(double now, double nextDirectAction) {
    return nextDirectAction - now >= 1.0;
}
#endif
