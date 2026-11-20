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
    test_navigation();
    return 0;
}
