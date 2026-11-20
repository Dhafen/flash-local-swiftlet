// Pure decision policy for the opt-in authorized test environment.
#ifndef SP_AI_DIRECT_H
#define SP_AI_DIRECT_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { SP_AI_WAIT, SP_AI_REST, SP_AI_TARGET, SP_AI_ATTACK, SP_AI_BIND } SPAIDecision;
static inline bool sp_ai_hp_known(uint8_t hp) { return hp <= 100; }
static inline bool sp_ai_hostile(uint8_t flags, uint8_t hp) {
    return (flags & 4) && (flags & 8) && !(flags & 16) && (!sp_ai_hp_known(hp) || hp > 0);
}
static inline SPAIDecision sp_ai_decision(bool fresh, uint8_t flags, uint8_t hp, uint8_t targetHP, uint8_t meta) {
    if (!fresh || !(flags & 1)) return SP_AI_WAIT;
    if ((flags & (2|64)) || (sp_ai_hp_known(hp) && hp < 35)) return SP_AI_REST;
    if (!sp_ai_hostile(flags,targetHP)) return SP_AI_TARGET;
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
#endif
