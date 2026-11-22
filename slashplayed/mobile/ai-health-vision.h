#ifndef SP_AI_HEALTH_VISION_H
#define SP_AI_HEALTH_VISION_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { SP_VISUAL_HP_UNKNOWN = 255, SP_HEALTH_SCAN_ROWS = 3 };

static inline unsigned sp_ai_health_capture_interval_ms(unsigned thermal, bool requested, bool paused, bool fresh) {
    static const unsigned intervals[] = {1000, 2500, 4000};  // Nominal, fair, serious.
    if (!requested || paused || !fresh || thermal >= sizeof intervals / sizeof intervals[0]) return 0;
    return intervals[thermal];
}

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
    if (length != 18 || p[0] != 'A' || p[1] != 'H' || p[2] != 2 || p[3] != 1) return 0;
    unsigned left = p[4] * 256 + p[5], top = p[6] * 256 + p[7];
    unsigned right = p[8] * 256 + p[9], bottom = p[10] * 256 + p[11];
    if (right > 4095 || bottom > 4095 || right <= left || bottom <= top) return 0;
    return ((uint64_t)left << 48) | ((uint64_t)top << 32) | ((uint64_t)right << 16) | bottom;
}

static inline bool sp_ai_health_marker(const uint8_t *pixel, bool bgra, bool left) {
    unsigned r = pixel[bgra ? 2 : 0], g = pixel[1], b = pixel[bgra ? 0 : 2];
    return b >= 224 && (left ? r >= 224 && g <= 32 : g >= 224 && r <= 32);
}

static inline bool sp_ai_health_edge(const uint8_t *pixels, size_t width, size_t window, bool bgra,
    bool left, size_t *innerEdge) {
    size_t first = width, last = 0;
    size_t start = left ? 0 : width - window, end = left ? window : width;
    for (size_t x = start; x < end; ++x) {
        if (!sp_ai_health_marker(pixels + x * 4, bgra, left)) continue;
        if (!last) first = x;
        else if (x != last) return false;
        last = x + 1;
    }
    if (!last || last - first < 2 || (left ? first > 2 : width - last > 2)) return false;
    *innerEdge = left ? last : first;
    return true;
}

// The player bar has a magenta left edge and a cyan right edge, both outside the fill.
// Require both edges in all rows before interpreting the green pixels between them.
static inline uint8_t sp_ai_visible_health(const uint8_t *data, size_t width, size_t stride, bool bgra) {
    if (!data || width < 48 || width > 1024 || stride < width * 4) return SP_VISUAL_HP_UNKNOWN;
    size_t edgeWindow = width / 12 + 2;
    if (edgeWindow > 32) edgeWindow = 32;
    size_t firstLeft = 0, firstRight = 0;
    unsigned low = 100, high = 0;
    for (size_t row = 0; row < SP_HEALTH_SCAN_ROWS; ++row) {
        const uint8_t *pixels = data + row * stride;
        size_t left, right;
        if (!sp_ai_health_edge(pixels, width, edgeWindow, bgra, true, &left) ||
            !sp_ai_health_edge(pixels, width, edgeWindow, bgra, false, &right)) return SP_VISUAL_HP_UNKNOWN;
        if (row == 0) {
            firstLeft = left;
            firstRight = right;
        } else if (left > firstLeft + 1 || firstLeft > left + 1 ||
                   right > firstRight + 1 || firstRight > right + 1) return SP_VISUAL_HP_UNKNOWN;
        size_t interior = right - left;
        size_t fill = 0, leading = 0, unexpected = 0;
        for (size_t x = 0; x < interior; ++x) {
            const uint8_t *p = pixels + (left + x) * 4;
            unsigned r = p[bgra ? 2 : 0], g = p[1], b = p[bgra ? 0 : 2];
            bool green = g >= 64 && g >= r + 24 && g >= b + 24;
            if (!green && !fill && leading == x && x < interior / 20) ++leading;
            else if (green && leading + fill == x) ++fill;
            else if (green || r > 85 || g > 85 || b > 85) ++unexpected;
        }
        if (fill < 3 || unexpected > interior / 16) return SP_VISUAL_HP_UNKNOWN;
        unsigned percent = (unsigned)(100 * fill / interior);
        if (percent < low) low = percent;
        if (percent > high) high = percent;
    }
    return high - low <= 5 ? (uint8_t)low : SP_VISUAL_HP_UNKNOWN;
}
#endif
