#ifndef SP_AI_HEALTH_VISION_H
#define SP_AI_HEALTH_VISION_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { SP_VISUAL_HP_UNKNOWN = 255, SP_HEALTH_SCAN_ROWS = 3 };

static inline bool sp_ai_health_bounds_fresh(uint64_t boundsAt, uint64_t now) {
    return boundsAt && now >= boundsAt && now - boundsAt <= 1500;
}
typedef struct { double at; uint8_t hp; } SPHealthReference;
typedef enum {
    SP_HEALTH_COMPARE_PENDING, SP_HEALTH_COMPARE_PAIRED, SP_HEALTH_COMPARE_UNREADABLE,
    SP_HEALTH_COMPARE_CHANGING, SP_HEALTH_COMPARE_UNKNOWN, SP_HEALTH_COMPARE_UNBRACKETED
} SPHealthComparison;

static inline SPHealthComparison sp_ai_compare_visible_health(const SPHealthReference *samples, unsigned count,
    double capturedAt, uint8_t visual, double now, uint8_t *reference) {
    const double maxGap = 0.85;
    const SPHealthReference *before = NULL, *after = NULL, *simultaneous = NULL;
    *reference = SP_VISUAL_HP_UNKNOWN;
    for (unsigned i = 0; i < count; ++i) {
        if (samples[i].at < capturedAt) before = &samples[i];
        else if (samples[i].at == capturedAt) simultaneous = &samples[i];
        else { after = &samples[i]; break; }
    }
    if (!before || capturedAt - before->at > maxGap) return SP_HEALTH_COMPARE_UNBRACKETED;
    if (!after) return now - capturedAt < maxGap ? SP_HEALTH_COMPARE_PENDING : SP_HEALTH_COMPARE_UNBRACKETED;
    if (after->at - capturedAt > maxGap) return SP_HEALTH_COMPARE_UNBRACKETED;
    if (before->hp > 100 || after->hp > 100 || (simultaneous && simultaneous->hp > 100))
        return SP_HEALTH_COMPARE_UNKNOWN;
    if (before->hp != after->hp || (simultaneous && before->hp != simultaneous->hp))
        return SP_HEALTH_COMPARE_CHANGING;
    *reference = before->hp;
    return visual <= 100 ? SP_HEALTH_COMPARE_PAIRED : SP_HEALTH_COMPARE_UNREADABLE;
}

static inline uint64_t sp_ai_health_region(const uint8_t *p, unsigned length) {
    if (length != 18 || p[0] != 'A' || p[1] != 'H' || p[2] != 1 || p[3] != 1) return 0;
    unsigned left = p[4] * 256 + p[5], top = p[6] * 256 + p[7];
    unsigned right = p[8] * 256 + p[9], bottom = p[10] * 256 + p[11];
    if (right > 4095 || bottom > 4095 || right <= left || bottom <= top) return 0;
    return ((uint64_t)left << 48) | ((uint64_t)top << 32) | ((uint64_t)right << 16) | bottom;
}

// Evaluate only the visible green player bar. A thin leading border still contributes to the denominator.
// Missing fill or inconsistent rows are unknown.
static inline uint8_t sp_ai_visible_health(const uint8_t *data, size_t width, size_t stride, bool bgra) {
    if (width < 48 || width > 1024 || stride < width * 4) return SP_VISUAL_HP_UNKNOWN;
    unsigned low = 100, high = 0, total = 0;
    for (size_t row = 0; row < SP_HEALTH_SCAN_ROWS; ++row) {
        size_t fill = 0, leading = 0, unexpected = 0;
        for (size_t x = 0; x < width; ++x) {
            const uint8_t *p = data + row * stride + x * 4;
            unsigned r = p[bgra ? 2 : 0], g = p[1], b = p[bgra ? 0 : 2];
            bool green = g >= 64 && g >= r + 24 && g >= b + 24;
            if (!green && !fill && leading == x && x < width / 20) ++leading;
            else if (green && leading + fill == x) ++fill;
            else if (green || r > 85 || g > 85 || b > 85) ++unexpected;
        }
        if (fill < 3 || unexpected > width / 16) return SP_VISUAL_HP_UNKNOWN;
        unsigned percent = (unsigned)((100 * fill + width / 2) / width);
        if (percent < low) low = percent;
        if (percent > high) high = percent;
        total += percent;
    }
    return high - low <= 5 ? (uint8_t)((total + 1) / SP_HEALTH_SCAN_ROWS) : SP_VISUAL_HP_UNKNOWN;
}
#endif
