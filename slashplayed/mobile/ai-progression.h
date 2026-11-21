#ifndef SP_AI_PROGRESSION_H
#define SP_AI_PROGRESSION_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t xp, maximum;
    uint16_t level, quests;
    bool xpKnown, questCountKnown;
} SPAIProgression;

static inline uint32_t sp_ai_progression_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static inline SPAIProgression sp_ai_progression(const uint8_t *p, unsigned length) {
    if (length != 18 || p[0] != 'A' || p[1] != 'X' || p[2] != 1 || p[3] > 3 || p[16] || p[17])
        return (SPAIProgression){0};
    SPAIProgression progress = {.quests = (uint16_t)(p[14] * 256 + p[15]), .questCountKnown = (p[3] & 2) != 0};
    uint32_t xp = sp_ai_progression_u32(p + 4), maximum = sp_ai_progression_u32(p + 8);
    uint16_t level = (uint16_t)(p[12] * 256 + p[13]);
    if ((p[3] & 1) && level && maximum && xp <= maximum) {
        progress.xpKnown = true;
        progress.xp = xp;
        progress.maximum = maximum;
        progress.level = level;
    }
    return progress;
}

typedef enum { SP_XP_UNVERIFIED, SP_XP_UNCHANGED, SP_XP_GAINED, SP_XP_LEVEL_UP } SPAIXPOutcome;

static inline SPAIXPOutcome sp_ai_xp_outcome(SPAIProgression earlier, SPAIProgression current) {
    if (!earlier.xpKnown || !current.xpKnown || current.level < earlier.level) return SP_XP_UNVERIFIED;
    if (current.level > earlier.level) return SP_XP_LEVEL_UP;
    if (current.maximum != earlier.maximum || current.xp < earlier.xp) return SP_XP_UNVERIFIED;
    return current.xp > earlier.xp ? SP_XP_GAINED : SP_XP_UNCHANGED;
}
#endif
