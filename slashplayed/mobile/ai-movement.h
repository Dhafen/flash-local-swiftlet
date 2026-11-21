#ifndef SP_AI_MOVEMENT_H
#define SP_AI_MOVEMENT_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint64_t generation;
    double deadline;
    uint8_t key; // Zero means the virtual stick owns the command.
} SPMovementCommand;

static inline bool sp_movement_begin(SPMovementCommand *command, uint8_t key, double now, double duration) {
    if (command->deadline || !isfinite(now) || now < 0 || !(duration > 0 && duration <= 0.70)) return false;
    command->generation = command->generation == UINT64_MAX ? 1 : command->generation + 1;
    command->key = key;
    command->deadline = now + duration;
    return true;
}

static inline bool sp_movement_due(const SPMovementCommand *command, uint64_t generation, double now) {
    return command->deadline && command->generation == generation && now >= command->deadline;
}

// A zero generation is a synchronous cancellation by the input owner.
static inline SPMovementCommand sp_movement_release(SPMovementCommand *command, uint64_t generation) {
    if (!command->deadline || (generation && generation != command->generation)) return (SPMovementCommand){0};
    SPMovementCommand previous = *command;
    command->deadline = 0;
    command->key = 0;
    return previous;
}

#endif
