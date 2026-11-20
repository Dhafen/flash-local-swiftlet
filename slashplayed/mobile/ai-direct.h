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
