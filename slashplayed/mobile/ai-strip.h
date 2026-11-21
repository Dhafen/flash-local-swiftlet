#ifndef SP_AI_STRIP_H
#define SP_AI_STRIP_H

#include <stdbool.h>
#include <stdint.h>

enum { SP_AI_STRIP_RECORD_BYTES = 18, SP_AI_STRIP_BUNDLE_BYTES = 4 * SP_AI_STRIP_RECORD_BYTES };

typedef struct {
    const uint8_t *state, *pose, *progression, *health;
} SPAIObservationBundle;

static inline bool sp_ai_strip_is_zero(const uint8_t *bytes, unsigned length) {
    for (unsigned i = 0; i < length; ++i)
        if (bytes[i]) return false;
    return true;
}

// AB carries the existing AI/AP/AX/AH records in fixed slots. Optional records
// are all-zero when absent, so missing pose cannot inherit an earlier sample.
static inline SPAIObservationBundle sp_ai_strip_bundle(const uint8_t *payload, unsigned capacity) {
    if (capacity < SP_AI_STRIP_BUNDLE_BYTES || payload[0] != 'A' || payload[1] != 'I' ||
        !sp_ai_strip_is_zero(payload + SP_AI_STRIP_BUNDLE_BYTES, capacity - SP_AI_STRIP_BUNDLE_BYTES))
        return (SPAIObservationBundle){0};

    SPAIObservationBundle bundle = {.state = payload};
    const uint8_t **slots[] = {&bundle.pose, &bundle.progression, &bundle.health};
    static const uint8_t types[] = {'P', 'X', 'H'};
    for (unsigned i = 0; i < sizeof types; ++i) {
        const uint8_t *record = payload + (i + 1) * SP_AI_STRIP_RECORD_BYTES;
        if (record[0] == 'A' && record[1] == types[i]) *slots[i] = record;
        else if (!sp_ai_strip_is_zero(record, SP_AI_STRIP_RECORD_BYTES)) return (SPAIObservationBundle){0};
    }
    return bundle;
}

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
    unsigned used = 5 + length;
    return sp_ai_strip_is_zero(payload + used, capacity - used) ? result : (SPRuntimeRestriction){0};
}

// The shared pixel strip pads each single-record AI message to its chunk size.
static inline unsigned sp_ai_strip_payload_length(const uint8_t *payload, unsigned capacity) {
    return capacity >= SP_AI_STRIP_RECORD_BYTES &&
        sp_ai_strip_is_zero(payload + SP_AI_STRIP_RECORD_BYTES, capacity - SP_AI_STRIP_RECORD_BYTES)
        ? SP_AI_STRIP_RECORD_BYTES : 0;
}

#endif
