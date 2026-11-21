#include <assert.h>
#include <string.h>
#include "../ai-encounter.h"
#include "../ai-navigation.h"

typedef struct {
    const char *lastAction;
    unsigned submissions, releases, outcomes;
    SPAINavOutcome outcome;
    bool accept;
} SPTestAdapter;

static bool test_submit(void *context, const char *action, SPAINavSample sample, double hold) {
    SPTestAdapter *mock = context;
    bool movement = strcmp(action, "FORWARD") == 0 || strncmp(action, "STRAFE_", 7) == 0;
    assert(sample.at > 0 && hold == (movement ? 0.60 : 0));
    mock->lastAction = action;
    ++mock->submissions;
    return mock->accept;
}

static void test_release(void *context) {
    SPTestAdapter *mock = context;
    ++mock->releases;
}

static void test_outcome(void *context, SPAINavOutcome outcome, SPAINavSample before, SPAINavSample after) {
    SPTestAdapter *mock = context;
    assert(before.at > 0 && after.at >= before.at);
    ++mock->outcomes;
    mock->outcome = outcome;
}

static void test_encounter_adapter(void) {
    SPAIEncounter planner = {.combatEvidence.lastHP = 255};
    SPTestAdapter mock = {.accept = false};
    SPAIEncounterAdapter adapter = {&mock, test_submit, test_release, test_outcome, NULL};
    SPAIEncounterObservation observation = {
        .sample = {1, {SP_MOTION_POSITION, 7, false}, {0, 2, 3, SP_AI_DISTANCE_UNKNOWN}, 0},
        .flags = 1, .hp = 80, .meta = 129, .movementKeys = 1
    };
    SPAIApproachExamples examples = {0};
    assert(strcmp(sp_ai_advance(&planner, observation, 1, false, &examples, adapter), "AI INPUT") == 0);
    assert(planner.searchAttempts == 0 && mock.submissions == 1);
    mock.accept = true;
    observation.sample.at = 2;
    assert(strcmp(sp_ai_advance(&planner, observation, 2, true, &examples, adapter), "SEARCH") == 0);
    assert(planner.searchAttempts == 1 && strcmp(mock.lastAction, "TARGET") == 0);
    observation.flags = 13;
    observation.targetHP = 100;
    observation.meta = 193;
    observation.sample = (SPAINavSample){2.5, {SP_MOTION_POSITION, 7, false}, {1, 2, 3, 70}, 8};
    assert(strcmp(sp_ai_advance(&planner, observation, 2.5, false, &examples, adapter), "ENGAGE") == 0);
    assert(strcmp(mock.lastAction, "ATTACK") == 0);
    observation.sample.at = 3.5;
    sp_ai_advance(&planner, observation, 3.5, false, &examples, adapter);
    observation.sample.at = 4;
    assert(strcmp(sp_ai_advance(&planner, observation, 4, true, &examples, adapter), "APPROACH") == 0);
    assert(strcmp(mock.lastAction, "FORWARD") == 0);
    observation.sample.at = 4.5;
    sp_ai_advance(&planner, observation, 4.5, false, &examples, adapter);
    assert(mock.outcomes == 0 && mock.submissions == 4);
    observation.sample.at = 5;
    ++observation.sample.motion.counter;
    observation.sample.evidence.distance = 14;
    sp_ai_advance(&planner, observation, 5, false, &examples, adapter);
    assert(mock.outcomes == 1 && mock.outcome == SP_NAV_CLOSER);
    observation.sample.at = 5.5;
    observation.flags = 45;
    observation.targetHP = 50;
    assert(strcmp(sp_ai_advance(&planner, observation, 5.5, false, &examples, adapter), "IN COMBAT") == 0);
    assert(strcmp(mock.lastAction, "ATTACK") == 0);
    observation.flags = 149;
    observation.meta = 133;
    observation.targetHP = 0;
    observation.sample.at = 6.5;
    observation.corpseEvidence = SP_CORPSE_RANGE_OUT | SP_CORPSE_LOOT_AVAILABLE;
    assert(strcmp(sp_ai_advance(&planner, observation, 6.5, false, &examples, adapter), "LOOT RANGE") == 0);
    assert(planner.lootAttempts == 0 && strcmp(mock.lastAction, "ATTACK") == 0);
    observation.corpseEvidence = SP_CORPSE_RANGE_IN | SP_CORPSE_LOOT_AVAILABLE;
    observation.sample.at = 6.75;
    assert(strcmp(sp_ai_advance(&planner, observation, 6.75, false, &examples, adapter), "LOOT CHECK") == 0);
    assert(strcmp(mock.lastAction, "LOOT") == 0);
    observation.sample.motion.lootConfirmed = true;
    observation.sample.at = 7;
    assert(strcmp(sp_ai_advance(&planner, observation, 7, false, &examples, adapter), "LOOT OK") == 0);
    observation.hp = 30;
    observation.sample.at = 7.5;
    assert(strcmp(sp_ai_advance(&planner, observation, 7.5, false, &examples, adapter), "RECOVER") == 0);
    observation.hp = 50;
    observation.sample.at = 8;
    assert(strcmp(sp_ai_advance(&planner, observation, 8, false, &examples, adapter), "SEARCH") == 0);
    assert(strcmp(mock.lastAction, "TARGET") == 0);
    assert(mock.submissions == 7);
}

static void test_encounter_stops(void) {
    SPAIEncounter planner = {.combatEvidence.lastHP = 255};
    SPTestAdapter mock = {.accept = true};
    SPAIEncounterAdapter adapter = {&mock, test_submit, test_release, test_outcome, NULL};
    SPAIEncounterObservation observation = {
        .sample = {10, {SP_MOTION_POSITION, 7, false}, {1, 2, 3, 70}, 8},
        .flags = 13, .hp = 255, .targetHP = 100, .meta = 193, .movementKeys = 1,
        .playerHealth = SP_HEALTH_RESTRICTED
    };
    SPAIApproachExamples examples = {0};
    assert(strcmp(sp_ai_advance(&planner, observation, 10, false, &examples, adapter), "HP SECRET") == 0);
    assert(mock.submissions == 0);
    observation.hp = 85;
    observation.sample.at = 10.5;
    sp_ai_advance(&planner, observation, 10.5, false, &examples, adapter);
    observation.sample.at = 11;
    sp_ai_advance(&planner, observation, 11, false, &examples, adapter);
    observation.sample.at = 11.5;
    sp_ai_advance(&planner, observation, 11.5, false, &examples, adapter);
    assert(mock.submissions == 2 && strcmp(mock.lastAction, "FORWARD") == 0);
    unsigned releases = mock.releases;
    assert(strcmp(sp_ai_advance(&planner, observation, 13, false, &examples, adapter), "AI STALE") == 0);
    assert(mock.submissions == 2 && mock.releases == releases + 1);
    assert(mock.outcomes == 1 && mock.outcome == SP_NAV_NO_SAMPLE && !planner.pulse.deadline);
    observation.sample.at = 13;
    ++observation.sample.evidence.target;
    observation.sample.evidence.bindings = SP_AI_TAB_BOUND;
    assert(strcmp(sp_ai_advance(&planner, observation, 13, false, &examples, adapter), "F12 BIND") == 0);
    assert(mock.submissions == 2);
}

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

static void test_forward_probe(void) {
    SPAINavSample sample = {10, {SP_MOTION_POSITION, 1, false}, {3, 5, 0, 100}, 0};
    assert(sp_ai_forward_probe_ready(sample, 13, 1, 10.1));
    assert(!sp_ai_forward_probe_ready(sample, 13 | 32, 1, 10.1));
    assert(!sp_ai_forward_probe_ready(sample, 13, 0, 10.1));
    assert(!sp_ai_forward_probe_ready(sample, 13, 1, 14));
    assert(sp_ai_forward_probe_repeat(SP_NAV_CLOSER, 2));
    assert(!sp_ai_forward_probe_repeat(SP_NAV_NO_PROGRESS, 2));
    assert(!sp_ai_forward_probe_repeat(SP_NAV_CONTEXT_CHANGED, 2));
    assert(!sp_ai_forward_probe_repeat(SP_NAV_CLOSER, 1));
    sample.evidence.distance = SP_AI_DISTANCE_UNKNOWN;
    assert(!sp_ai_forward_probe_ready(sample, 13, 1, 10.1));
    sample.evidence.distance = 32;
    assert(!sp_ai_forward_probe_ready(sample, 13, 1, 10.1));
}

static void test_manual_takeover_preserves_encounter(void) {
    SPAIEncounter planner = {.target = 9, .searchAttempts = 2, .lootAttempts = 1,
        .combatEvidence.lastHP = 43, .pulse.deadline = 12, .nextAction = 11,
        .lastDamageAt = 9.5, .navBudget.pulses = 4};
    SPTestAdapter mock = {0};
    SPAIEncounterAdapter adapter = {&mock, test_submit, test_release, test_outcome, NULL};
    sp_ai_suspend_encounter(&planner, adapter);
    assert(mock.releases == 1 && mock.submissions == 0);
    assert(!planner.pulse.deadline && !planner.lastDamageAt && planner.combatEvidence.lastHP == 255);
    assert(planner.target == 9 && planner.searchAttempts == 2 && planner.lootAttempts == 1);
    assert(planner.navBudget.pulses == 4);
}

int main(void) {
    uint8_t posePacket[] = {65, 80, 1, 3, 0, 0, 0, 0, 255, 255, 255, 251, 0, 0, 0, 8, 64, 7};
    SPAIWorldPose pose = sp_ai_world_pose(posePacket, sizeof posePacket);
    assert(pose.valid && pose.headingKnown && pose.map == 0 && pose.firstQ4 == -5 && pose.secondQ4 == 8);
    assert(pose.heading == 64 && pose.epoch == 7);
    assert(!sp_ai_world_pose(posePacket, sizeof posePacket - 1).valid);
    posePacket[3] = 1;
    pose = sp_ai_world_pose(posePacket, sizeof posePacket);
    assert(pose.valid && !pose.headingKnown);
    posePacket[17] = 0;
    assert(!sp_ai_world_pose(posePacket, sizeof posePacket).valid);
    test_manual_takeover_preserves_encounter();
    test_forward_probe();
    test_encounter_adapter();
    test_encounter_stops();
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
    assert(sp_ai_corpse_evidence(feedbackPacket, sizeof feedbackPacket) == 0);
    const uint8_t corpsePacket[] = {'A','I',149,100,0,133,'K',1,'F',SP_MOTION_POSITION,7,
        1|SP_CORPSE_LOCAL_KILL|SP_CORPSE_LOOT_AVAILABLE|SP_CORPSE_RANGE_OUT};
    assert(sp_ai_corpse_evidence(corpsePacket, sizeof corpsePacket) ==
        (SP_CORPSE_LOCAL_KILL|SP_CORPSE_LOOT_AVAILABLE|SP_CORPSE_RANGE_OUT));
    assert(sp_ai_farm_feedback(corpsePacket, sizeof corpsePacket).lootConfirmed);
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
