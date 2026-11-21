#ifndef SP_AI_STRIP_H
#define SP_AI_STRIP_H

#include <stdint.h>

enum { SP_AI_STRIP_RECORD_BYTES = 18 };

// The shared pixel strip pads each single-record AI message to its chunk size.
static inline unsigned sp_ai_strip_payload_length(const uint8_t *payload, unsigned capacity) {
    if (capacity < SP_AI_STRIP_RECORD_BYTES) return 0;
    for (unsigned i = SP_AI_STRIP_RECORD_BYTES; i < capacity; ++i)
        if (payload[i]) return 0;
    return SP_AI_STRIP_RECORD_BYTES;
}

#endif
