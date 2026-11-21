#include <assert.h>
#include "../ai-direct.h"

static void test_steering_observations(void) {
    SPAISteering steering = {0};
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_LEFT, 1.0));
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_LEFT, 1.0));
    assert(sp_ai_confirm_steering(&steering, SP_MOVE_LEFT, 1.5));
    // Returning to the same column after an observation gap needs a new pair.
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_LEFT, 3.0));
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_RIGHT, 3.5));
    assert(sp_ai_confirm_steering(&steering, SP_MOVE_RIGHT, 4.0));
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_NONE, 4.5));
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_RIGHT, 5.0));
    // An accepted movement pulse clears the evidence before the next decision.
    steering = (SPAISteering){0};
    assert(!sp_ai_confirm_steering(&steering, SP_MOVE_RIGHT, 5.5));
    assert(sp_ai_confirm_steering(&steering, SP_MOVE_RIGHT, 6.0));
}

static void test_pulse_outcomes(void) {
    const SPAINavSample before = {10.0, {SP_MOTION_POSITION, 7, false}, {1, 2, 3, 80}, 8};
    const SPAINavPulse pulse = {before, SP_MOVE_FORWARD, 10.7, 11.9};
    SPAINavSample after = before;
    assert(sp_ai_sample_fresh(10.0, 10.8));
    assert(!sp_ai_sample_fresh(10.0, 11.0));
    assert(!sp_ai_sample_fresh(0, 0));
    assert(!sp_ai_sample_fresh(11.0, 10.0));
    assert(sp_ai_nav_outcome(pulse, after, 11.9) == SP_NAV_NO_SAMPLE);
    ++after.motion.counter;
    after.at = 10.5;
    assert(sp_ai_nav_outcome(pulse, after, 10.6) == SP_NAV_PENDING);
    after.at = 11.3;
    --after.motion.counter;
    assert(sp_ai_nav_outcome(pulse, after, 11.9) == SP_NAV_STALLED);
    after.motion = (SPAIFarmFeedback){SP_MOTION_SPEED, 9, false};
    assert(sp_ai_nav_outcome(pulse, after, 11.9) == SP_NAV_NO_SAMPLE);
    after.motion = (SPAIFarmFeedback){SP_MOTION_POSITION, 9, false};
    assert(sp_ai_nav_outcome(pulse, after, 11.4) == SP_NAV_NO_PROGRESS);
    after.evidence.distance = 88;
    assert(sp_ai_nav_outcome(pulse, after, 11.4) == SP_NAV_NO_PROGRESS);
    after.evidence.distance = 78;
    assert(sp_ai_nav_outcome(pulse, after, 11.4) == SP_NAV_CLOSER);
    after.evidence.distance = SP_AI_DISTANCE_UNKNOWN;
    assert(sp_ai_nav_outcome(pulse, after, 11.4) == SP_NAV_DISPLACED);
    SPAINavPulse side = pulse;
    side.before.column = 4;
    side.move = SP_MOVE_LEFT;
    after.column = 7;
    assert(sp_ai_nav_outcome(side, after, 11.4) == SP_NAV_ALIGNED);
    --after.evidence.target;
    assert(sp_ai_nav_outcome(side, after, 11.4) == SP_NAV_CONTEXT_CHANGED);
    ++after.evidence.target;
    ++after.evidence.position;
    assert(sp_ai_nav_outcome(side, after, 11.4) == SP_NAV_CONTEXT_CHANGED);
    after.at = 12.0;
    assert(sp_ai_nav_outcome(side, after, 12.0) == SP_NAV_NO_SAMPLE);
}

static void test_bounded_retries(void) {
    SPAINavBudget budget = {0};
    assert(sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));
    sp_ai_nav_accept(&budget, SP_MOVE_FORWARD);
    sp_ai_nav_resolve(&budget, SP_NAV_STALLED);
    assert(sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));
    sp_ai_nav_accept(&budget, SP_MOVE_FORWARD);
    sp_ai_nav_resolve(&budget, SP_NAV_NO_PROGRESS);
    assert(!sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));

    budget = (SPAINavBudget){0};
    sp_ai_nav_accept(&budget, SP_MOVE_LEFT);
    sp_ai_nav_resolve(&budget, SP_NAV_ALIGNED);
    sp_ai_nav_accept(&budget, SP_MOVE_FORWARD);
    sp_ai_nav_accept(&budget, SP_MOVE_RIGHT);
    sp_ai_nav_resolve(&budget, SP_NAV_ALIGNED);
    sp_ai_nav_accept(&budget, SP_MOVE_FORWARD);
    assert(!sp_ai_nav_budget_open(budget, SP_MOVE_LEFT));

    budget = (SPAINavBudget){0};
    sp_ai_nav_resolve(&budget, SP_NAV_DISPLACED);
    sp_ai_nav_resolve(&budget, SP_NAV_DISPLACED);
    assert(!sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));
    sp_ai_nav_resolve(&budget, SP_NAV_CLOSER);
    assert(sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));
    for (unsigned i = 0; i < 12; ++i) sp_ai_nav_accept(&budget, SP_MOVE_FORWARD);
    assert(!sp_ai_nav_budget_open(budget, SP_MOVE_FORWARD));
}

static void test_combat_feedback(void) {
    SPAICombatEvidence combat = {.lastHP = 255};
    assert(!sp_ai_observe_damage(&combat, 100, 1));
    for (unsigned i = 0; sp_ai_combat_budget_open(combat); ++i) sp_ai_accept_probe(&combat, 2+i);
    assert(combat.attacks == 4);
    assert(!sp_ai_observe_damage(&combat, 100, 5));
    assert(!combat.measured);
    assert(!sp_ai_observe_damage(&combat, 100, 6));
    assert(combat.measured);
    assert(!sp_ai_observe_damage(&combat, 255, 7));
    assert(!sp_ai_observe_damage(&combat, 90, 8));
    assert(sp_ai_engagement(combat, SP_MOVE_NONE, 16, false, false) == SP_ENGAGE_DAMAGE_UNKNOWN);
    assert(!sp_ai_combat_budget_open(combat));
    assert(!sp_ai_observe_damage(&combat, 89, 8));
    assert(sp_ai_observe_damage(&combat, 89, 9));
    assert(sp_ai_combat_budget_open(combat));
}

static void test_health_status(void) {
    uint8_t packet[] = {'A','I',13,255,255,193,'K',1,'F',1,7,0,'N',1,1,255,255,64+16+8+3};
    assert(sp_ai_health_status(packet, sizeof packet, false) == SP_HEALTH_RESTRICTED);
    assert(sp_ai_health_status(packet, sizeof packet, true) == SP_HEALTH_UNAVAILABLE);
    assert(sp_ai_nav_evidence(packet, sizeof packet).bindings == 3);
    packet[3] = 70;
    assert(sp_ai_health_status(packet, sizeof packet, false) == SP_HEALTH_UNSPECIFIED);
    packet[2] = 1;
    packet[4] = 0;
    packet[17] = 64+48+3;
    assert(sp_ai_health_status(packet, sizeof packet, true) == SP_HEALTH_ABSENT);
    assert(sp_ai_health_status(packet, sizeof packet, false) == SP_HEALTH_PUBLIC);
    packet[17] = 3;
    assert(sp_ai_health_status(packet, sizeof packet, false) == SP_HEALTH_UNSPECIFIED);
}

static void test_simulated_encounter(void) {
    bool recovering = false;
    assert(sp_ai_readiness(1, 80, &recovering) == SP_AI_READY);
    assert(sp_ai_decision(true, 1, 80, 0, 129) == SP_AI_TARGET);
    assert(sp_ai_decision(true, 13, 80, 100, 193) == SP_AI_ATTACK);
    SPAICombatEvidence combat = {.lastHP = 100};
    assert(sp_ai_engagement(combat, SP_MOVE_FORWARD, 80, false, false) == SP_ENGAGE_PROBE);
    sp_ai_accept_probe(&combat, 1);
    assert(sp_ai_engagement(combat, SP_MOVE_FORWARD, 80, false, false) == SP_ENGAGE_APPROACH);
    assert(sp_ai_engagement(combat, SP_MOVE_FORWARD, 16, false, false) == SP_ENGAGE_PROBE);
    assert(sp_ai_engagement(combat, SP_MOVE_FORWARD, SP_AI_DISTANCE_UNKNOWN, false, true) == SP_ENGAGE_PROBE);
    assert(sp_ai_observe_damage(&combat, 52, 2));
    assert(sp_ai_engagement(combat, SP_MOVE_LEFT, 80, true, false) == SP_ENGAGE_PROBE);
    assert(sp_ai_engagement((SPAICombatEvidence){.attacks = 4}, SP_MOVE_NONE, 16, false, false) == SP_ENGAGE_DAMAGE_UNKNOWN);
    assert(sp_ai_engagement((SPAICombatEvidence){.attacks = 4, .measured = true}, SP_MOVE_NONE, 16, false, false) == SP_ENGAGE_NO_DAMAGE);
    assert(sp_ai_decision(true, 181, 80, 0, 133) == SP_AI_WAIT);
    assert(sp_ai_farm_decision(sp_ai_decision(true, 149, 80, 0, 133), 149, 133, 1, false) == SP_AI_LOOT);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 133, 1, true) == SP_AI_TARGET);
    assert(sp_ai_readiness(1, 34, &recovering) == SP_AI_RECOVER);
    assert(sp_ai_readiness(1, 255, &recovering) == SP_AI_HEALTH_HOLD);
    assert(sp_ai_readiness(1, 49, &recovering) == SP_AI_RECOVER);
    assert(sp_ai_readiness(3, 255, &recovering) == SP_AI_DEAD);
    assert(sp_ai_readiness(65, 80, &recovering) == SP_AI_MOUNTED);
    assert(sp_ai_readiness(1, 50, &recovering) == SP_AI_READY);
}

int main(void) {
    test_steering_observations();
    test_pulse_outcomes();
    test_bounded_retries();
    test_combat_feedback();
    test_health_status();
    test_simulated_encounter();
    assert(sp_ai_decision(false,45,100,100,129)==SP_AI_WAIT);
    assert(sp_ai_decision(true,1,255,0,128)==SP_AI_TARGET);
    assert(sp_ai_decision(true,13,255,255,129)==SP_AI_ATTACK);
    assert(sp_ai_decision(true,13,255,255,130)==SP_AI_BIND);
    assert(sp_ai_decision(true,13,20,255,129)==SP_AI_REST);
    assert(sp_ai_decision(true,15,100,255,129)==SP_AI_REST);
    assert(sp_ai_decision(true,77,100,100,129)==SP_AI_REST);
    assert(sp_ai_decision(true,29,100,255,129)==SP_AI_TARGET);
    assert(sp_ai_decision(true,5,100,100,129)==SP_AI_TARGET);
    assert(sp_ai_decision(true,13,100,0,129)==SP_AI_TARGET);
    assert(sp_ai_decision(true,33,100,0,129)==SP_AI_WAIT);
    assert(sp_ai_decision(true,61,100,0,129)==SP_AI_WAIT);
    assert(sp_ai_decision(true,45,100,65,129)==SP_AI_ATTACK);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 133, 0, false) == SP_AI_LOOT);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 129, 0, false) == SP_AI_LOOT_BIND);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 133, 2, false) == SP_AI_LOOT_WAIT);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 21, 133, 0, false) == SP_AI_TARGET);
    assert(sp_ai_farm_decision(SP_AI_WAIT, 181, 133, 0, false) == SP_AI_WAIT);
    assert(sp_ai_farm_decision(SP_AI_REST, 149, 133, 0, false) == SP_AI_REST);
    assert(sp_ai_visible_approach(129, 2, false, false) == SP_MOVE_NONE);
    assert(sp_ai_visible_approach(129 + 8 * 8, 1, false, false) == SP_MOVE_NONE);
    assert(sp_ai_visible_approach(129 + 8 * 5, 2, false, false) == SP_MOVE_LEFT);
    assert(sp_ai_visible_approach(129 + 8 * 11, 2, true, true) == SP_MOVE_RIGHT);
    assert(sp_ai_visible_approach(129 + 8 * 8, 2, true, false) == SP_MOVE_FORWARD);
    assert(sp_ai_visible_approach(129 + 8 * 8, 2, true, true) == SP_MOVE_NONE);
    SPAIApproachExamples examples = {0};
    for (unsigned i = 0; i < 3; ++i) sp_ai_learn_approach(&examples, SP_MOVE_LEFT, SP_MOVE_FORWARD);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_LEFT, false) == SP_MOVE_LEFT);
    sp_ai_learn_approach(&examples, SP_MOVE_LEFT, SP_MOVE_FORWARD);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_LEFT, false) == SP_MOVE_FORWARD);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_RIGHT, false) == SP_MOVE_RIGHT);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_LEFT, true) == SP_MOVE_LEFT);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_NONE, false) == SP_MOVE_NONE);
    sp_ai_learn_approach(&examples, SP_MOVE_LEFT, SP_MOVE_RIGHT);
    assert(examples.lateral[0] == 0);
    sp_ai_learn_approach(&examples, SP_MOVE_LEFT, SP_MOVE_LEFT);
    sp_ai_learn_approach(&examples, SP_MOVE_LEFT, SP_MOVE_LEFT);
    assert(sp_ai_apply_approach(&examples, SP_MOVE_LEFT, false) == SP_MOVE_LEFT);
    const uint8_t packet[] = {'A', 'I', 1, 100, 0, 128, 'K', 1|8|16};
    assert(sp_ai_movement_bindings(packet, 6) == 0);
    assert(sp_ai_movement_bindings(packet, 8) == (1|8|16));
    assert(sp_ai_movement_key(SP_MOVE_FORWARD, 1|8|16) == 'w');
    assert(sp_ai_movement_key(SP_MOVE_BACK, 1|8|16) == 0);
    assert(sp_ai_movement_key(SP_MOVE_LEFT, 1|8|16) == 'a');
    assert(sp_ai_movement_key(SP_MOVE_RIGHT, 1|8|16) == 'e');
    assert(sp_ai_movement_key(SP_MOVE_LEFT, 4|8) == 'q');
    assert(sp_ai_movement_key(SP_MOVE_RIGHT, 32) == 'd');
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 133, 1, true) == SP_AI_TARGET);
    const uint8_t feedbackPacket[] = {'A','I',149,100,0,133,'K',1,'F',SP_MOTION_POSITION,7,1};
    const SPAIFarmFeedback feedback = sp_ai_farm_feedback(feedbackPacket, sizeof feedbackPacket);
    assert(sp_ai_nav_evidence(feedbackPacket, sizeof feedbackPacket).distance == SP_AI_DISTANCE_UNKNOWN);
    const uint8_t navPacket[] = {'A','I',13,100,100,193,'K',1,'F',SP_MOTION_POSITION,7,0,'N',23,8,1,7,3};
    SPAINavEvidence evidence = sp_ai_nav_evidence(navPacket, sizeof navPacket);
    assert(evidence.target == 23 && evidence.position == 8 && evidence.distance == 263);
    assert(evidence.bindings == (SP_AI_TAB_BOUND|SP_AI_ROTATION_BOUND));
    assert(feedback.lootConfirmed && feedback.source == SP_MOTION_POSITION);
    assert(!sp_ai_farm_progress(feedback, feedback));
    assert(sp_ai_farm_progress(feedback, (SPAIFarmFeedback){SP_MOTION_POSITION, 8, false}));
    assert(!sp_ai_farm_progress(feedback, (SPAIFarmFeedback){SP_MOTION_SPEED, 8, false}));
    assert(sp_ai_farm_feedback(feedbackPacket, 8).source == SP_MOTION_UNKNOWN);
    assert(!sp_ai_farm_progress(
        (SPAIFarmFeedback){SP_MOTION_SPEED, 7, false},
        (SPAIFarmFeedback){SP_MOTION_SPEED, 8, false}));
    return 0;
}
