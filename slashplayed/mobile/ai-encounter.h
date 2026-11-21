// Encounter planning runs against the same adapter contract on iPhone and in tests.
#ifndef SP_AI_ENCOUNTER_H
#define SP_AI_ENCOUNTER_H
#include "ai-direct.h"
#include "ai-navigation.h"

typedef struct {
    SPAINavSample sample;
    uint8_t flags, hp, targetHP, meta, movementKeys, corpseEvidence;
    SPAIHealthStatus playerHealth;
    SPAIWorldPose pose;
    SPAIOwnHit ownHit;
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
    unsigned inputFailures;
    SPAISteering steering;
    uint8_t steeringPosition, target;
    SPAINavPulse pulse;
    SPAINavSample lastPulseSample;
    SPAINavBudget navBudget;
    SPAICombatEvidence combatEvidence;
    bool recovering, probeAfterMove;
    bool approachModelDirty, pulseTrainingEligible;
    SPAIApproachModel approachModel;
    SPAIRoute route;
    double routeDeadline, routeProgress, routeStartedAt, routeHold;
    unsigned routeFailures, routeMoves, routeTurns;
    uint8_t routeEvidenceSeq;
    SPAIWorldPose routeBefore;
    SPAIMove routeAction;
    bool routeEvidenceArmed, routeHeadingUnconfirmed;
    SPAIWorldPose targetTurnBefore;
    double targetTurnReleasedAt, targetTurnDeadline;
    unsigned targetTurnError, targetTurns, targetTurnFailures;
    SPAIMove targetTurnMove;
    uint8_t targetTurnDesired;
    SPAISteering targetFacingProof;
    bool targetTurnUnconfirmed;
} SPAIEncounter;

static inline void sp_ai_note(SPAIEncounterAdapter adapter, const char *message) {
    if (adapter.note) adapter.note(adapter.context, message);
}

static inline bool sp_ai_try_input(SPAIEncounter *encounter, SPAIEncounterAdapter adapter,
    const char *action, SPAINavSample sample, double hold) {
    bool accepted = adapter.submit(adapter.context, action, sample, hold);
    if (accepted) encounter->inputFailures = 0;
    else ++encounter->inputFailures;
    return accepted;
}

static inline void sp_ai_cancel_steering(SPAIEncounter *encounter) {
    encounter->steering = (SPAISteering){0};
    encounter->pulse = (SPAINavPulse){0};
    encounter->lastPulseSample = (SPAINavSample){0};
    encounter->pulseTrainingEligible = false;
    encounter->routeDeadline = 0;
    encounter->routeEvidenceArmed = false;
    encounter->targetTurnDeadline = 0;
    encounter->targetFacingProof = (SPAISteering){0};
}

static inline bool sp_ai_observed_bearing(const SPAIEncounter *encounter, SPAIEncounterObservation observation,
    double now, uint8_t *desired) {
    SPAIWorldPose pose = observation.pose;
    uint16_t distance = observation.sample.evidence.distance;
    if (observation.sample.column || !observation.sample.evidence.target || (observation.flags & 32) ||
        distance <= 16 || distance > 120 || pose.epoch != observation.sample.evidence.position ||
        !sp_ai_sample_fresh(pose.observedAt, now)) return false;
    double dx = pose.targetFirstQ4, dy = pose.targetSecondQ4;
    double low = distance - 2, high = distance + 2, length2 = dx * dx + dy * dy;
    return length2 >= low * low && length2 <= high * high && sp_ai_target_heading(&encounter->route, pose, desired);
}

static inline const char *sp_ai_check_target_turn(SPAIEncounter *encounter, SPAIEncounterObservation observation,
    bool bearing, uint8_t desired, double now, SPAIEncounterAdapter adapter) {
    SPAIWorldPose pose = observation.pose;
    bool binding = sp_ai_movement_key(encounter->targetTurnMove, observation.movementKeys) != 0;
    bool stableTarget = bearing && sp_ai_heading_delta(desired, encounter->targetTurnDesired) <= 8;
    if (!binding || !stableTarget || sp_ai_pose_distance2(pose, encounter->targetTurnBefore) > 9 ||
        pose.epoch != encounter->targetTurnBefore.epoch) {
        adapter.release(adapter.context);
        encounter->targetTurnDeadline = 0;
        encounter->targetFacingProof = (SPAISteering){0};
        if (binding && stableTarget) encounter->targetTurnFailures = 2;
        return !binding ? "TURN BIND" : stableTarget ? "NAV BLOCK" : "NAV BEARING";
    }
    if (pose.observedAt < encounter->targetTurnReleasedAt && now < encounter->targetTurnDeadline)
        return "TURN TARGET";
    unsigned error = sp_ai_heading_delta(desired, pose.heading);
    SPAIMove direction = error <= 8 ? SP_MOVE_FORWARD :
        (sp_ai_heading_error(desired, pose.heading) > 0 ? SP_TURN_LEFT : SP_TURN_RIGHT);
    bool confirmed = pose.observedAt >= encounter->targetTurnReleasedAt &&
        sp_ai_confirm_steering(&encounter->targetFacingProof, direction, pose.observedAt);
    if (!confirmed && now < encounter->targetTurnDeadline) return "TURN TARGET";
    adapter.release(adapter.context);
    encounter->targetTurnDeadline = 0;
    int turned = sp_ai_heading_error(pose.heading, encounter->targetTurnBefore.heading);
    bool correctDirection = encounter->targetTurnMove == SP_TURN_LEFT ? turned >= 2 : turned <= -2;
    bool progressed = confirmed && correctDirection && (error <= 8 || error + 4 < encounter->targetTurnError);
    encounter->targetTurnUnconfirmed = !progressed || error > 8;
    if (progressed)
        encounter->targetTurnFailures = 0;
    else
        ++encounter->targetTurnFailures;
    encounter->steering = (SPAISteering){0};
    return "TURN TARGET";
}

static inline void sp_ai_suspend_encounter(SPAIEncounter *encounter, SPAIEncounterAdapter adapter) {
    adapter.release(adapter.context);
    sp_ai_cancel_steering(encounter);
    encounter->probeAfterMove = false;
    encounter->combatEvidence = (SPAICombatEvidence){.lastHP = 255};
    encounter->lastDamageAt = 0;
    encounter->inputFailures = 0;
}

static inline void sp_ai_report_navigation(SPAIEncounter *encounter, SPAINavOutcome outcome,
    SPAINavSample sample, SPAIEncounterAdapter adapter) {
    sp_ai_nav_resolve(&encounter->navBudget, outcome);
    if (encounter->pulseTrainingEligible &&
        sp_ai_train_approach(&encounter->approachModel, encounter->pulse.before, encounter->pulse.move, outcome))
        encounter->approachModelDirty = true;
    if (adapter.outcome) adapter.outcome(adapter.context, outcome, encounter->pulse.before, sample);
}

static inline void sp_ai_stale_encounter(SPAIEncounter *encounter, SPAINavSample sample, SPAIEncounterAdapter adapter) {
    if (encounter->pulse.deadline)
        sp_ai_report_navigation(encounter, SP_NAV_NO_SAMPLE, sample, adapter);
    sp_ai_cancel_steering(encounter);
    adapter.release(adapter.context);
}

static inline const char *sp_ai_follow_route(SPAIEncounter *encounter, SPAIEncounterObservation observation,
    double now, bool reduced, SPAIEncounterAdapter adapter) {
    SPAIWorldPose pose = observation.pose;
    if (!sp_ai_sample_fresh(pose.observedAt, now)) pose.valid = false;
    SPAIRoute *route = &encounter->route;
    SPAIRouteDecision decision = sp_ai_route_probe(route, pose);
    if (encounter->routeDeadline) {
        bool turning = encounter->routeAction == SP_TURN_LEFT || encounter->routeAction == SP_TURN_RIGHT;
        const char *status = turning ? "TURN ROUTE" : "ROUTE";
        if (!sp_ai_movement_key(encounter->routeAction, observation.movementKeys)) {
            adapter.release(adapter.context);
            encounter->routeDeadline = 0;
            encounter->routeEvidenceArmed = false;
            return turning ? "TURN BIND" : "MOVE BIND";
        }
        if (turning && pose.valid && sp_ai_pose_distance2(pose, encounter->routeBefore) > 9) {
            adapter.release(adapter.context);
            encounter->routeDeadline = 0;
            encounter->routeEvidenceArmed = false;
            encounter->routeFailures = 2;
            return "ROUTE BLOCK";
        }
        if (decision == SP_ROUTE_OFF_ROUTE || (!turning && decision == SP_ROUTE_FACE) ||
            decision == SP_ROUTE_UNKNOWN || (pose.valid && pose.epoch != encounter->routeBefore.epoch)) {
            adapter.release(adapter.context);
            encounter->routeDeadline = 0;
            encounter->routeEvidenceArmed = false;
            if (decision == SP_ROUTE_UNKNOWN) {
                ++encounter->routeFailures;
                return "ROUTE DATA";
            }
            return "ROUTE HOLD";
        }
        bool afterRelease = pose.observedAt > encounter->routeStartedAt + encounter->routeHold;
        bool newEvidence = afterRelease && encounter->routeEvidenceArmed && pose.sequence != encounter->routeEvidenceSeq;
        if (afterRelease && !encounter->routeEvidenceArmed) {
            encounter->routeEvidenceArmed = true;
            encounter->routeEvidenceSeq = pose.sequence;
        }
        if (!newEvidence && now < encounter->routeDeadline) return status;
        adapter.release(adapter.context);
        encounter->routeDeadline = 0;
        encounter->routeEvidenceArmed = false;
        if (!newEvidence) {
            ++encounter->routeFailures;
            return "ROUTE DATA";
        }
        SPAIRouteLeg leg = route->legs[route->next];
        bool progressed = turning
            ? pose.headingKnown && (decision == SP_ROUTE_FORWARD ||
                sp_ai_heading_delta(leg.start.heading, pose.heading) + 2 <= encounter->routeProgress)
            : sp_ai_pose_distance2(pose, leg.end) + 16 < encounter->routeProgress;
        if (turning && decision == SP_ROUTE_FORWARD) encounter->routeHeadingUnconfirmed = false;
        if (progressed)
            encounter->routeFailures = 0;
        else ++encounter->routeFailures;
    }
    switch (decision) {
        case SP_ROUTE_COMPLETE: return "ROUTE DONE";
        case SP_ROUTE_UNKNOWN:
            encounter->routeEvidenceArmed = false;
            return "ROUTE DATA";
        case SP_ROUTE_OFF_ROUTE:
            encounter->routeEvidenceArmed = false;
            return "ROUTE HOLD";
        case SP_ROUTE_FACE: break;
        case SP_ROUTE_REACHED:
            ++route->next;
            encounter->searchAttempts = encounter->routeFailures = encounter->routeMoves = 0;
            encounter->routeTurns = 0;
            encounter->routeHeadingUnconfirmed = false;
            return "WAYPOINT";
        case SP_ROUTE_FORWARD: break;
    }
    SPAIRouteLeg leg = route->legs[route->next];
    bool turning = decision == SP_ROUTE_FACE;
    if (turning) encounter->routeEvidenceArmed = false;
    if (encounter->routeFailures >= 2 || (turning ? encounter->routeTurns >= 8 : encounter->routeMoves >= 12))
        return "ROUTE BLOCK";
    if (turning && sp_ai_pose_distance2(pose, leg.start) > SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4)
        return "FACE ROUTE";
    if (!turning && encounter->routeHeadingUnconfirmed) {
        if (pose.observedAt <= encounter->routeStartedAt + encounter->routeHold) return "TURN ROUTE";
        if (!encounter->routeEvidenceArmed) {
            encounter->routeEvidenceArmed = true;
            encounter->routeEvidenceSeq = pose.sequence;
            return "TURN ROUTE";
        }
        if (pose.sequence == encounter->routeEvidenceSeq) return "TURN ROUTE";
        encounter->routeHeadingUnconfirmed = false;
    }
    int error = sp_ai_heading_error(leg.start.heading, pose.heading);
    SPAIMove action = turning ? (error > 0 ? SP_TURN_LEFT : SP_TURN_RIGHT) : SP_MOVE_FORWARD;
    if (!sp_ai_movement_key(action, observation.movementKeys)) return turning ? "TURN BIND" : "MOVE BIND";
    const char *status = turning ? "TURN ROUTE" : "ROUTE";
    if (now - encounter->routeStartedAt < (reduced ? 2.0 : 1.0)) return status;
    encounter->routeStartedAt = now;
    unsigned headingError = sp_ai_heading_delta(leg.start.heading, pose.heading);
    double hold = turning ? (headingError <= 24 ? 0.10 : 0.28) : sp_ai_route_hold(route, pose);
    const char *command = action == SP_TURN_LEFT ? "TURN_LEFT" : action == SP_TURN_RIGHT ? "TURN_RIGHT" : "FORWARD";
    if (!sp_ai_try_input(encounter, adapter, command, observation.sample, hold)) {
        ++encounter->routeFailures;
        return "NAV INPUT";
    }
    encounter->routeBefore = pose;
    encounter->routeAction = action;
    encounter->routeProgress = turning ? headingError : sp_ai_pose_distance2(pose, leg.end);
    encounter->routeHold = hold;
    encounter->routeEvidenceArmed = false;
    encounter->routeDeadline = now + 2.6;
    if (turning) {
        ++encounter->routeTurns;
        encounter->routeHeadingUnconfirmed = true;
    }
    else ++encounter->routeMoves;
    return status;
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
    if (encounter->routeDeadline && (decision != SP_AI_TARGET || (flags & (4|32)))) {
        adapter.release(adapter.context);
        encounter->routeDeadline = 0;
    }
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
        encounter->inputFailures = 0;
        encounter->targetTurns = encounter->targetTurnFailures = 0;
        encounter->targetTurnUnconfirmed = false;
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
    if (encounter->inputFailures >= 3) {
        adapter.release(adapter.context);
        return "INPUT BLOCK";
    }

    const char *approach = "APPROACH";
    uint8_t desired = 0;
    bool bearing = hostile && sp_ai_observed_bearing(encounter, observation, now, &desired);
    if (encounter->targetTurnDeadline)
        return sp_ai_check_target_turn(encounter, observation, bearing, desired, now, adapter);
    if (encounter->pulse.deadline) {
        bool facing = bearing && sp_ai_heading_delta(desired, observation.pose.heading) <= 8;
        bool canContinue = hostile && target && (sample.column || facing) &&
            sp_ai_movement_key(encounter->pulse.move, observation.movementKeys);
        SPAINavSample outcomeSample = sample;
        SPAINavOutcome outcome = sp_ai_nav_observe(encounter->pulse, &outcomeSample, now, &encounter->lastPulseSample);
        if (!canContinue && (outcome == SP_NAV_PENDING || outcome == SP_NAV_NO_SAMPLE))
            outcome = SP_NAV_CONTEXT_CHANGED;
        if (outcome == SP_NAV_PENDING) return approach;
        adapter.release(adapter.context);
        sp_ai_report_navigation(encounter, outcome, outcomeSample, adapter);
        encounter->probeAfterMove = encounter->pulse.move == SP_MOVE_FORWARD && outcome == SP_NAV_DISPLACED;
        encounter->pulse = (SPAINavPulse){0};
        encounter->lastPulseSample = (SPAINavSample){0};
        encounter->pulseTrainingEligible = false;
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
        unsigned range = observation.corpseEvidence & (SP_CORPSE_RANGE_OUT|SP_CORPSE_RANGE_IN);
        unsigned loot = observation.corpseEvidence & (SP_CORPSE_LOOT_NONE|SP_CORPSE_LOOT_AVAILABLE);
        if (loot == SP_CORPSE_LOOT_NONE) return "LOOT EMPTY";
        if (range == SP_CORPSE_RANGE_OUT) return "LOOT RANGE";
        if (range != SP_CORPSE_RANGE_IN || loot != SP_CORPSE_LOOT_AVAILABLE) return "LOOT UNKNOWN";
        if (now >= encounter->nextAction) {
            encounter->nextAction = now + 1.4;
            if (!sp_ai_try_input(encounter, adapter, "LOOT", sample, 0)) return "AI INPUT";
            ++encounter->lootAttempts;
        }
        return "LOOT CHECK";
    }
    if (decision == SP_AI_TARGET) {
        if (!(sample.evidence.bindings & SP_AI_TAB_BOUND)) return "TAB BIND";
        if (encounter->searchAttempts >= 4) {
            if (!encounter->route.count) return "NO TARGET";
            if ((flags & (4|32)) != 0) return "ROUTE HOLD";
            return sp_ai_follow_route(encounter, observation, now, reduced, adapter);
        }
        if (now >= encounter->nextAction) {
            encounter->nextAction = now + 1.0;
            if (!sp_ai_try_input(encounter, adapter, "TARGET", sample, 0)) return "AI INPUT";
            ++encounter->searchAttempts;
        }
        return "SEARCH";
    }
    if (decision == SP_AI_BIND) return "F12 BIND";
    if (!hostile) return "AI WAIT";
    if (!(sample.evidence.bindings & SP_AI_ROTATION_BOUND)) return "F12 BIND";
    if (!target) return "TARGET UNKNOWN";
    if (encounter->targetTurnUnconfirmed && encounter->targetTurnFailures >= 2) return "NAV BLOCK";
    if (encounter->targetTurnUnconfirmed && !bearing) return "NAV BEARING";

    if (sp_ai_observe_damage(&encounter->combatEvidence, observation.targetHP, sample.at)) {
        sp_ai_note(adapter, "AI combat: selected target health decreased");
    }
    if (sp_ai_observe_own_damage(&encounter->combatEvidence, observation.ownHit, sample.at)) {
        encounter->lastDamageAt = now;
        sp_ai_note(adapter, "AI combat: matched local damage on selected target");
    }
    bool recentDamage = encounter->lastDamageAt > 0 && now - encounter->lastDamageAt < 3.0;
    SPAIMove ruleMove = sp_ai_visible_approach(meta, 2, false, false);
    if (bearing) {
        int error = sp_ai_heading_error(desired, observation.pose.heading);
        ruleMove = error >= -8 && error <= 8 ? SP_MOVE_FORWARD : (error > 0 ? SP_TURN_LEFT : SP_TURN_RIGHT);
    }
    SPAIMove move = sp_ai_predict_approach(&encounter->approachModel, sample, ruleMove, combat);
    // Demonstrations can opt out of model changes where the player taught lateral movement.
    unsigned side = ruleMove == SP_MOVE_RIGHT;
    if (!bearing && move != ruleMove && examples->lateral[side] > examples->forward[side] && examples->lateral[side] >= 4)
        move = ruleMove;
    if (encounter->steeringPosition != sample.evidence.position) {
        encounter->steering = (SPAISteering){0};
        encounter->steeringPosition = sample.evidence.position;
    }
    bool confirmed = sp_ai_confirm_steering(&encounter->steering, move, bearing ? observation.pose.observedAt : sample.at);
    if (bearing && move == SP_MOVE_FORWARD && confirmed) encounter->targetTurnUnconfirmed = false;
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
        if (move == SP_TURN_LEFT || move == SP_TURN_RIGHT) {
            if (encounter->targetTurns >= 8 || encounter->targetTurnFailures >= 2) return "NAV BLOCK";
            unsigned error = sp_ai_heading_delta(desired, observation.pose.heading);
            double hold = error <= 24 ? 0.10 : 0.28;
            if (!sp_ai_try_input(encounter, adapter, move == SP_TURN_LEFT ? "TURN_LEFT" : "TURN_RIGHT", sample, hold)) {
                encounter->nextAction = now + 0.8;
                return "NAV INPUT";
            }
            ++encounter->targetTurns;
            encounter->targetTurnBefore = observation.pose;
            encounter->targetTurnError = error;
            encounter->targetTurnMove = move;
            encounter->targetTurnDesired = desired;
            encounter->targetTurnReleasedAt = now + hold;
            encounter->targetTurnDeadline = now + 2.6;
            encounter->targetFacingProof = (SPAISteering){0};
            encounter->targetTurnUnconfirmed = true;
            encounter->lastMoveAt = now;
            return "TURN TARGET";
        }
        const char *key = move == SP_MOVE_LEFT ? "STRAFE_LEFT" : move == SP_MOVE_RIGHT ? "STRAFE_RIGHT" : "FORWARD";
        const double hold = 0.60; // cover the nominal 0.5s SPHover cadence
        if (!sp_ai_try_input(encounter, adapter, key, sample, hold)) {
            encounter->nextAction = now + 0.8;
            return "NAV INPUT";
        }
        sp_ai_note(adapter, bearing ? "AI policy: calibrated target bearing selected forward" :
            move == ruleMove ? "AI policy: rules selected approach" :
            "AI policy: measured approach model selected forward");
        sp_ai_nav_accept(&encounter->navBudget, move);
        encounter->steering = (SPAISteering){0};
        encounter->lastMoveAt = now;
        encounter->pulse = (SPAINavPulse){sample, move, now + hold, now + 1.8};
        encounter->pulseTrainingEligible = !combat;
        return approach;
    }

    encounter->nextAction = now + 0.85;
    if (!sp_ai_try_input(encounter, adapter, "ATTACK", sample, 0)) return "AI INPUT";
    sp_ai_accept_probe(&encounter->combatEvidence, now);
    encounter->probeAfterMove = false;
    return phase;
}
#endif
