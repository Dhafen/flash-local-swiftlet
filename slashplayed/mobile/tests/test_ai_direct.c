#include <assert.h>
#include "../ai-direct.h"
static void test_navigation(void) {
    SPAINavigation nav = {0};
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_FORWARD) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_FORWARD) == SP_MOVE_FORWARD);
    sp_ai_nav_sent(&nav, SP_MOVE_FORWARD);

    // 30 minutes of synthetic 1 Hz noisy observations, with progress each pulse.
    for (unsigned second = 0; second < 1800; ++second) {
        SPAIMove proposal = second % 2 ? SP_MOVE_FORWARD : SP_MOVE_BACK;
        SPAIMove selected = sp_ai_nav_proposal(&nav, proposal);
        assert(selected != SP_MOVE_BACK);
        if (selected == SP_MOVE_FORWARD) {
            sp_ai_nav_sent(&nav, selected);
            sp_ai_nav_feedback(&nav, true);
        }
    }
    assert(sp_ai_nav_duration(&nav, SP_MOVE_FORWARD) == 0.70);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_NONE) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_BACK);

    // Two pulse windows without scene change permit one perpendicular recovery.
    sp_ai_nav_feedback(&nav, false);
    assert(sp_ai_nav_duration(&nav, SP_MOVE_FORWARD) == 0.42);
    sp_ai_nav_feedback(&nav, false);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_BACK) == SP_MOVE_LEFT);
    sp_ai_nav_sent(&nav, SP_MOVE_LEFT);
    sp_ai_nav_feedback(&nav, false);
    assert(nav.blocked);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_FORWARD) == SP_MOVE_NONE);
    assert(sp_ai_nav_proposal(&nav, SP_MOVE_RIGHT) == SP_MOVE_NONE);

    // Leave a complete movement pulse and neutral interval before Tab/F12.
    assert(sp_ai_nav_has_slot(10.0, 11.0));
    assert(!sp_ai_nav_has_slot(10.0, 10.9));
    assert(!sp_ai_nav_has_slot(10.0, 9.0));
}
int main(void) {
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
    assert(!sp_ai_nav_allowed(SP_AI_ATTACK,13,1));
    assert(sp_ai_nav_allowed(SP_AI_ATTACK,13,2));
    assert(!sp_ai_nav_allowed(SP_AI_ATTACK,45,4));
    assert(sp_ai_nav_allowed(SP_AI_TARGET,1,0));
    assert(!sp_ai_nav_allowed(SP_AI_TARGET,33,0));
    assert(!sp_ai_nav_allowed(SP_AI_BIND,13,4));
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
    SPAIFarmPlan plan = sp_ai_plan_farm(SP_AI_TARGET, 1, 129, 0, false, &examples);
    assert(plan.phase == SP_FARM_SEARCH && plan.usePixel2Play);
    plan = sp_ai_plan_farm(SP_AI_ATTACK, 13, 129, 1, false, &examples);
    assert(plan.phase == SP_FARM_ENGAGE && !plan.usePixel2Play);
    plan = sp_ai_plan_farm(SP_AI_ATTACK, 13, 129 + 8 * 8, 0, false, &examples);
    assert(plan.phase == SP_FARM_APPROACH && plan.movement == SP_MOVE_FORWARD);
    assert(sp_ai_nav_has_slot(0.8, sp_ai_direct_interval(SP_AI_ATTACK, true)));
    assert(!sp_ai_nav_has_slot(0.8, sp_ai_direct_interval(SP_AI_ATTACK, false)));
    plan = sp_ai_plan_farm(SP_AI_ATTACK, 45, 129 + 8 * 8, 2, false, &examples);
    assert(plan.phase == SP_FARM_APPROACH && plan.movement == SP_MOVE_FORWARD);
    plan = sp_ai_plan_farm(SP_AI_ATTACK, 45, 129 + 8 * 11, 2, true, &examples);
    assert(plan.phase == SP_FARM_COMBAT && plan.movement == SP_MOVE_NONE && !plan.usePixel2Play);
    plan = sp_ai_plan_farm(SP_AI_LOOT, 149, 133, 0, false, &examples);
    assert(plan.phase == SP_FARM_LOOT && !plan.usePixel2Play);
    const uint8_t packet[] = {'A', 'I', 1, 100, 0, 128, 'K', 1|8|16};
    assert(sp_ai_movement_bindings(packet, 6) == 0);
    assert(sp_ai_movement_bindings(packet, 8) == (1|8|16));
    assert(sp_ai_movement_key(SP_MOVE_FORWARD, 1|8|16) == 'w');
    assert(sp_ai_movement_key(SP_MOVE_BACK, 1|8|16) == 0);
    assert(sp_ai_movement_key(SP_MOVE_LEFT, 1|8|16) == 'a');
    assert(sp_ai_movement_key(SP_MOVE_RIGHT, 1|8|16) == 'e');
    assert(sp_ai_movement_key(SP_MOVE_LEFT, 4|8) == 'q');
    assert(sp_ai_movement_key(SP_MOVE_RIGHT, 32) == 'd');
    assert(sp_ai_visible_move_spacing(true) > sp_ai_visible_move_spacing(false));
    assert(sp_ai_visible_move_duration(SP_MOVE_FORWARD, true) < sp_ai_visible_move_duration(SP_MOVE_FORWARD, false));
    assert(sp_ai_visible_move_duration(SP_MOVE_LEFT, true) < sp_ai_visible_move_duration(SP_MOVE_LEFT, false));
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 2, 3, 0, true) == SP_MOVE_NONE);
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 3, 2, 0, false) == SP_MOVE_NONE);
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 3, 3, 0, false) == SP_MOVE_LEFT);
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 3, 0, 1, true) == SP_MOVE_FORWARD);
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 5, 0, 2, false) == SP_MOVE_RIGHT);
    assert(sp_ai_search_step(SP_AI_TARGET, 1, 5, 3, 3, true) == SP_MOVE_NONE);
    assert(sp_ai_search_step(SP_AI_TARGET, 5, 5, 3, 0, true) == SP_MOVE_NONE);
    assert(sp_ai_search_step(SP_AI_TARGET, 33, 5, 3, 0, true) == SP_MOVE_NONE);
    assert(sp_ai_search_step(SP_AI_ATTACK, 13, 5, 3, 0, true) == SP_MOVE_NONE);
    assert(sp_ai_farm_decision(SP_AI_TARGET, 149, 133, 1, true) == SP_AI_TARGET);
    const uint8_t feedbackPacket[] = {'A','I',149,100,0,133,'K',1,'F',SP_MOTION_POSITION,7,1};
    const SPAIFarmFeedback feedback = sp_ai_farm_feedback(feedbackPacket, sizeof feedbackPacket);
    assert(feedback.lootConfirmed && feedback.source == SP_MOTION_POSITION);
    assert(!sp_ai_farm_progress(feedback, feedback));
    assert(sp_ai_farm_progress(feedback, (SPAIFarmFeedback){SP_MOTION_POSITION, 8, false}));
    assert(!sp_ai_farm_progress(feedback, (SPAIFarmFeedback){SP_MOTION_SPEED, 8, false}));
    assert(sp_ai_farm_feedback(feedbackPacket, 8).source == SP_MOTION_UNKNOWN);
    assert(sp_ai_patrol_step(SP_AI_TARGET, 1, 0, 0) == SP_MOVE_FORWARD);
    assert(sp_ai_patrol_step(SP_AI_TARGET, 1, 3, 0) == SP_MOVE_BACK);
    assert(sp_ai_patrol_step(SP_AI_TARGET, 1, 12, 0) == SP_MOVE_NONE);
    assert(sp_ai_patrol_step(SP_AI_TARGET, 1, 3, 2) == SP_MOVE_NONE);
    assert(sp_ai_patrol_step(SP_AI_ATTACK, 13, 0, 0) == SP_MOVE_NONE);
    test_navigation();
    return 0;
}
