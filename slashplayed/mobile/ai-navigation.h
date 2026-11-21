#ifndef SP_AI_NAVIGATION_H
#define SP_AI_NAVIGATION_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t map;
    int32_t firstQ4, secondQ4;
    uint8_t heading, epoch;
    bool valid, headingKnown;
    double observedAt;
    uint8_t sequence;
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
        sp_ai_pose_i32(bytes + 12), bytes[16], bytes[17], true, bytes[3] == 3, 0, 0};
}

enum { SP_ROUTE_MAX_LEGS = 8, SP_ROUTE_RADIUS_Q4 = 8 };
typedef struct { SPAIWorldPose start, end; } SPAIRouteLeg;
typedef struct {
    SPAIRouteLeg legs[SP_ROUTE_MAX_LEGS];
    unsigned count, next;
} SPAIRoute;

typedef enum {
    SP_ROUTE_COMPLETE, SP_ROUTE_UNKNOWN, SP_ROUTE_OFF_ROUTE, SP_ROUTE_REACHED, SP_ROUTE_FACE, SP_ROUTE_FORWARD
} SPAIRouteDecision;

static inline double sp_ai_pose_distance2(SPAIWorldPose a, SPAIWorldPose b) {
    double x = (double)a.firstQ4 - b.firstQ4, y = (double)a.secondQ4 - b.secondQ4;
    return x * x + y * y;
}

static inline unsigned sp_ai_heading_delta(uint8_t a, uint8_t b) {
    unsigned delta = (uint8_t)(a - b);
    return delta <= 128 ? delta : 256 - delta;
}

static inline int sp_ai_heading_error(uint8_t desired, uint8_t current) {
    unsigned delta = (uint8_t)(desired - current);
    return delta <= 128 ? (int)delta : (int)delta - 256;
}

static inline bool sp_ai_route_append(SPAIRoute *route, SPAIWorldPose start, SPAIWorldPose end) {
    if (route->count >= SP_ROUTE_MAX_LEGS || !start.valid || !end.valid ||
        !start.headingKnown || !end.headingKnown || start.map != end.map || start.epoch != end.epoch ||
        sp_ai_heading_delta(start.heading, end.heading) > 8) return false;
    double length2 = sp_ai_pose_distance2(start, end);
    if (length2 < 16 * 16 || length2 > 48 * 48) return false;
    if (route->count) {
        SPAIWorldPose previous = route->legs[route->count - 1].end;
        if (previous.map != start.map || sp_ai_pose_distance2(previous, start) > SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4)
            return false;
    }
    route->legs[route->count++] = (SPAIRouteLeg){start, end};
    return true;
}

static inline SPAIRouteDecision sp_ai_route_probe(const SPAIRoute *route, SPAIWorldPose pose) {
    if (route->next >= route->count) return SP_ROUTE_COMPLETE;
    if (!pose.valid) return SP_ROUTE_UNKNOWN;
    const SPAIRouteLeg *leg = &route->legs[route->next];
    if (pose.map != leg->start.map) return SP_ROUTE_OFF_ROUTE;
    const double radius2 = SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4;
    if (sp_ai_pose_distance2(pose, leg->end) <= radius2 &&
        (route->next + 1 == route->count || sp_ai_pose_distance2(pose, route->legs[route->next + 1].start) <= radius2))
        return SP_ROUTE_REACHED;
    double x = (double)pose.firstQ4 - leg->start.firstQ4, y = (double)pose.secondQ4 - leg->start.secondQ4;
    double dx = (double)leg->end.firstQ4 - leg->start.firstQ4, dy = (double)leg->end.secondQ4 - leg->start.secondQ4;
    double along = x * dx + y * dy, across = x * dy - y * dx;
    double length2 = dx * dx + dy * dy;
    if ((along < 0 && x * x + y * y > radius2) || along > length2 || across * across > radius2 * length2)
        return SP_ROUTE_OFF_ROUTE;
    if (!pose.headingKnown) return SP_ROUTE_UNKNOWN;
    return sp_ai_heading_delta(leg->start.heading, pose.heading) <= 8 ? SP_ROUTE_FORWARD : SP_ROUTE_FACE;
}

static inline double sp_ai_route_hold(const SPAIRoute *route, SPAIWorldPose pose) {
    return sp_ai_pose_distance2(pose, route->legs[route->next].end) <= 16 * 16 ? 0.20 : 0.60;
}
#endif
