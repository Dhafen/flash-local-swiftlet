#ifndef SP_AI_STRIP_H
#define SP_AI_STRIP_H

#include <stdbool.h>
#include <stdint.h>

enum { SP_AI_STRIP_RECORD_BYTES = 18 };

typedef struct {
    uint8_t kind;
    char action[97];
} SPRuntimeRestriction;

static inline SPRuntimeRestriction sp_ai_strip_restriction(const uint8_t *payload, unsigned capacity) {
    if (capacity < 5 || payload[0] != 'A' || payload[1] != 'E' || payload[2] != 1 ||
        (payload[3] != 1 && payload[3] != 2)) return (SPRuntimeRestriction){0};
    unsigned length = payload[4];
    SPRuntimeRestriction result = {.kind = payload[3]};
    if (!length || length >= sizeof result.action || length > capacity - 5) return (SPRuntimeRestriction){0};
    for (unsigned i = 0; i < length; ++i) {
        uint8_t c = payload[5 + i];
        bool symbol = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            c == '_' || c == ':' || c == '.' || c == '(' || c == ')' || c == ' ';
        if (!symbol) return (SPRuntimeRestriction){0};
        result.action[i] = (char)c;
    }
    for (unsigned i = 5 + length; i < capacity; ++i)
        if (payload[i]) return (SPRuntimeRestriction){0};
    return result;
}

// The shared pixel strip pads each single-record AI message to its chunk size.
static inline unsigned sp_ai_strip_payload_length(const uint8_t *payload, unsigned capacity) {
    if (capacity < SP_AI_STRIP_RECORD_BYTES) return 0;
    for (unsigned i = SP_AI_STRIP_RECORD_BYTES; i < capacity; ++i)
        if (payload[i]) return 0;
    return SP_AI_STRIP_RECORD_BYTES;
}

#endif
