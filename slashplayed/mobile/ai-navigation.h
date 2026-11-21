#ifndef SP_AI_NAVIGATION_H
#define SP_AI_NAVIGATION_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t map;
    int32_t firstQ4, secondQ4;
    uint8_t heading, epoch;
    bool valid, headingKnown;
} SPAIWorldPose;

static inline uint32_t sp_ai_pose_u32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
}

static inline int32_t sp_ai_pose_i32(const uint8_t *bytes) {
    uint32_t value = sp_ai_pose_u32(bytes);
    return value <= INT32_MAX ? (int32_t)value : -(int32_t)(UINT32_MAX - value) - 1;
}

static inline SPAIWorldPose sp_ai_world_pose(const uint8_t *bytes, unsigned length) {
    if (length != 18 || bytes[0] != 'A' || bytes[1] != 'P' || bytes[2] != 1 ||
        (bytes[3] != 1 && bytes[3] != 3) || !bytes[17]) return (SPAIWorldPose){0};
    return (SPAIWorldPose){sp_ai_pose_u32(bytes + 4), sp_ai_pose_i32(bytes + 8),
        sp_ai_pose_i32(bytes + 12), bytes[16], bytes[17], true, bytes[3] == 3};
}
#endif
