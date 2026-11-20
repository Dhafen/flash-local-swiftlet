#include <assert.h>
#include "../ai-direct.h"
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
    assert(!sp_ai_scout_allowed(SP_AI_TARGET,1,2,0));
    assert(sp_ai_scout_allowed(SP_AI_TARGET,1,3,0));
    assert(!sp_ai_scout_allowed(SP_AI_TARGET,1,3,3));
    assert(!sp_ai_scout_allowed(SP_AI_ATTACK,13,3,0));
    assert(!sp_ai_scout_allowed(SP_AI_TARGET,33,3,0));
    return 0;
}
