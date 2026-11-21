// Encounter planning runs against the same adapter contract on iPhone and in tests.
#ifndef SP_AI_ENCOUNTER_H
#define SP_AI_ENCOUNTER_H
#include "ai-direct.h"

typedef struct {
    SPAINavSample sample;
    uint8_t flags, hp, targetHP, meta, movementKeys, corpseEvidence;
    SPAIHealthStatus playerHealth;
} SPAIEncounterObservation;

typedef struct {
    void *context;
    bool (*submit)(void *context, const char *action, SPAINavSample sample, double hold);
    void (*release)(void *context);
    void (*outcome)(void *context, SPAINavOutcome outcome, SPAINavSample before, SPAINavSample after);
    void (*note)(void *context, const char *message);
} SPAIEncounterAdapter;

typedef struct {
    double nextAction, lastMoveAt, lastDamageAt;
    unsigned lootAttempts, searchAttempts;
    SPAISteering steering;
    uint8_t steeringPosition, target;
    SPAINavPulse pulse;
    SPAINavBudget navBudget;
    SPAICombatEvidence combatEvidence;
    bool recovering, probeAfterMove;
} SPAIEncounter;

static inline void sp_ai_note(SPAIEncounterAdapter adapter, const char *message) {
    if (adapter.note) adapter.note(adapter.context, message);
}

static inline void sp_ai_cancel_steering(SPAIEncounter *encounter) {
    encounter->steering = (SPAISteering){0};
    encounter->pulse = (SPAINavPulse){0};
}

static inline void sp_ai_report_navigation(SPAIEncounter *encounter, SPAINavOutcome outcome,
    SPAINavSample sample, SPAIEncounterAdapter adapter) {
    sp_ai_nav_resolve(&encounter->navBudget, outcome);
    if (adapter.outcome) adapter.outcome(adapter.context, outcome, encounter->pulse.before, sample);
}

static inline void sp_ai_stale_encounter(SPAIEncounter *encounter, SPAINavSample sample, SPAIEncounterAdapter adapter) {
    if (encounter->pulse.deadline)
        sp_ai_report_navigation(encounter, SP_NAV_NO_SAMPLE, sample, adapter);
    sp_ai_cancel_steering(encounter);
    adapter.release(adapter.context);
}

static inline const char *sp_ai_advance(SPAIEncounter *encounter, SPAIEncounterObservation observation,
    double now, bool reduced, const SPAIApproachExamples *examples, SPAIEncounterAdapter adapter) {
    SPAINavSample sample = observation.sample;
    if (!sp_ai_sample_fresh(sample.at, now)) {
        sp_ai_stale_encounter(encounter, sample, adapter);
        return "AI STALE";
    }

    uint8_t flags = observation.flags, meta = observation.meta;
    SPAIDecision decision = sp_ai_decision(true, flags, observation.hp, observation.targetHP, meta);
    bool hostile = decision == SP_AI_ATTACK || decision == SP_AI_BIND;
    uint8_t target = sample.evidence.target;
    if (encounter->target != target) {
        if (encounter->pulse.deadline) sp_ai_note(adapter, "AI navigation: cancelled on target change");
        adapter.release(adapter.context);
        sp_ai_cancel_steering(encounter);
        encounter->nextAction = encounter->lastDamageAt = 0;
        encounter->navBudget = (SPAINavBudget){0};
        encounter->combatEvidence = (SPAICombatEvidence){.lastHP = 255};
        encounter->probeAfterMove = false;
        encounter->lootAttempts = 0;
        if (hostile) encounter->searchAttempts = 0;
        encounter->target = target;
    }

    SPAIReadiness readiness = sp_ai_readiness(flags, observation.hp, &encounter->recovering);
    if (readiness != SP_AI_READY) {
        if (encounter->pulse.deadline) sp_ai_note(adapter, "AI navigation: cancelled");
        sp_ai_cancel_steering(encounter);
        adapter.release(adapter.context);
        if (readiness == SP_AI_DEAD) return "PLAYER DEAD";
        if (readiness == SP_AI_MOUNTED) return "MOUNTED";
        if (readiness == SP_AI_RECOVER) return "RECOVER";
        return observation.playerHealth == SP_HEALTH_RESTRICTED ? "HP SECRET" : "HP UNKNOWN";
    }

    const char *approach = "APPROACH";
    if (encounter->pulse.deadline) {
        bool canContinue = hostile && target && sample.column &&
            sp_ai_movement_key(encounter->pulse.move, observation.movementKeys);
        SPAINavOutcome outcome = sp_ai_nav_outcome(encounter->pulse, sample, now);
        if (!canContinue && (outcome == SP_NAV_PENDING || outcome == SP_NAV_NO_SAMPLE))
            outcome = SP_NAV_CONTEXT_CHANGED;
        if (outcome == SP_NAV_PENDING) return approach;
        adapter.release(adapter.context);
        sp_ai_report_navigation(encounter, outcome, sample, adapter);
        encounter->probeAfterMove = encounter->pulse.move == SP_MOVE_FORWARD && outcome == SP_NAV_DISPLACED;
        encounter->pulse = (SPAINavPulse){0};
        encounter->nextAction = now + 0.4;
    }

    bool combat = (flags & 32) != 0;
    if (sample.motion.lootConfirmed && (flags & (16|128)) == (16|128) && target &&
        !combat && encounter->lootAttempts < 3) {
        sp_ai_note(adapter, "AI loot: selected corpse slot cleared");
        encounter->lootAttempts = 3;
        encounter->nextAction = now + 0.4;
        return "LOOT OK";
    }
    decision = sp_ai_farm_decision(decision, flags, meta, encounter->lootAttempts, sample.motion.lootConfirmed);
    if (decision == SP_AI_LOOT_BIND) return "INTERACT BIND";
    if (decision == SP_AI_LOOT_WAIT) return "LOOT UNCONF";
    if (decision == SP_AI_LOOT) {
        if (!target) return "LOOT UNKNOWN";
        if ((observation.corpseEvidence & (SP_CORPSE_RANGE_OUT|SP_CORPSE_RANGE_IN)) == SP_CORPSE_RANGE_OUT)
            return "LOOT RANGE";
        if (now >= encounter->nextAction) {
            encounter->nextAction = now + 1.4;
            if (!adapter.submit(adapter.context, "LOOT", sample, 0)) return "AI INPUT";
            ++encounter->lootAttempts;
        }
        return "LOOT CHECK";
    }
    if (decision == SP_AI_TARGET) {
        if (!(sample.evidence.bindings & SP_AI_TAB_BOUND)) return "TAB BIND";
        if (encounter->searchAttempts >= 4) return "NO TARGET";
        if (now >= encounter->nextAction) {
            encounter->nextAction = now + 1.0;
            if (!adapter.submit(adapter.context, "TARGET", sample, 0)) return "AI INPUT";
            ++encounter->searchAttempts;
        }
        return "SEARCH";
    }
    if (decision == SP_AI_BIND) return "F12 BIND";
    if (!hostile) return "AI WAIT";
    if (!(sample.evidence.bindings & SP_AI_ROTATION_BOUND)) return "F12 BIND";
    if (!target) return "TARGET UNKNOWN";

    if (sp_ai_observe_damage(&encounter->combatEvidence, observation.targetHP, sample.at)) {
        encounter->lastDamageAt = now;
        sp_ai_note(adapter, "AI combat: selected target health decreased");
    }
    bool recentDamage = encounter->lastDamageAt > 0 && now - encounter->lastDamageAt < 3.0;
    SPAIMove move = sp_ai_visible_approach(meta, 2, false, false);
    if (sample.evidence.distance != SP_AI_DISTANCE_UNKNOWN)
        move = sp_ai_apply_approach(examples, move, combat);
    if (encounter->steeringPosition != sample.evidence.position) {
        encounter->steering = (SPAISteering){0};
        encounter->steeringPosition = sample.evidence.position;
    }
    bool confirmed = sp_ai_confirm_steering(&encounter->steering, move, sample.at);
    const char *phase = combat ? "IN COMBAT" : "ENGAGE";
    if (now < encounter->nextAction) return phase;
    SPAIEngagement engagement = sp_ai_engagement(encounter->combatEvidence, move, sample.evidence.distance,
        recentDamage, encounter->probeAfterMove);
    if (engagement == SP_ENGAGE_NO_DAMAGE) return "NO DAMAGE";
    if (engagement == SP_ENGAGE_DAMAGE_UNKNOWN) return "DAMAGE ?";

    if (engagement == SP_ENGAGE_APPROACH) {
        if (!sample.evidence.position || sample.motion.source != SP_MOTION_POSITION) return "NAV POSITION";
        if (!sp_ai_nav_budget_open(encounter->navBudget, move)) return "NAV BLOCK";
        if (!sp_ai_movement_key(move, observation.movementKeys)) return "MOVE BIND";
        if (!confirmed || now - encounter->lastMoveAt < (reduced ? 2.0 : 0.8)) return approach;
        const char *key = move == SP_MOVE_LEFT ? "STRAFE_LEFT" : move == SP_MOVE_RIGHT ? "STRAFE_RIGHT" : "FORWARD";
        const double hold = 0.60; // cover the nominal 0.5s SPHover cadence
        if (!adapter.submit(adapter.context, key, sample, hold)) {
            encounter->nextAction = now + 0.8;
            return "NAV INPUT";
        }
        sp_ai_nav_accept(&encounter->navBudget, move);
        encounter->steering = (SPAISteering){0};
        encounter->lastMoveAt = now;
        encounter->pulse = (SPAINavPulse){sample, move, now + hold, now + 1.8};
        return approach;
    }

    encounter->nextAction = now + 0.85;
    if (!adapter.submit(adapter.context, "ATTACK", sample, 0)) return "AI INPUT";
    sp_ai_accept_probe(&encounter->combatEvidence, now);
    encounter->probeAfterMove = false;
    return phase;
}
#endif
