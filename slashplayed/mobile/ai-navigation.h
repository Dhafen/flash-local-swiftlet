#ifndef SP_AI_NAVIGATION_H
#define SP_AI_NAVIGATION_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

typedef struct {
    uint32_t map;
    int32_t firstQ4, secondQ4;
    uint8_t heading, epoch;
    bool valid, headingKnown;
    double observedAt;
    uint8_t sequence;
    int16_t targetFirstQ4, targetSecondQ4;
    bool targetKnown;
} SPAIWorldPose;

static inline uint32_t sp_ai_pose_u32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
}

static inline int32_t sp_ai_pose_i32(const uint8_t *bytes) {
    uint32_t value = sp_ai_pose_u32(bytes);
    return value <= INT32_MAX ? (int32_t)value : -(int32_t)(UINT32_MAX - value) - 1;
}

static inline SPAIWorldPose sp_ai_world_pose(const uint8_t *bytes, unsigned length) {
    if (length != 18 || bytes[0] != 'A' || bytes[1] != 'P' || !bytes[17] ||
        !(bytes[3] & 1)) return (SPAIWorldPose){0};
    SPAIWorldPose pose = {.valid = true, .headingKnown = (bytes[3] & 2) != 0,
        .heading = bytes[16], .epoch = bytes[17]};
    if (bytes[2] == 1 && bytes[3] <= 3) {
        pose.map = sp_ai_pose_u32(bytes + 4);
        pose.firstQ4 = sp_ai_pose_i32(bytes + 8);
        pose.secondQ4 = sp_ai_pose_i32(bytes + 12);
        return pose;
    }
    if (bytes[2] != 2 || bytes[3] > 7) return (SPAIWorldPose){0};
    pose.map = (uint32_t)bytes[4] * 256 + bytes[5];
    for (unsigned i = 0; i < 2; ++i) {
        const uint8_t *p = bytes + 6 + i * 3;
        int32_t value = (int32_t)p[0] * 65536 + p[1] * 256 + p[2];
        if (value >= 8388608) value -= 16777216;
        if (i == 0) pose.firstQ4 = value;
        else pose.secondQ4 = value;
    }
    int first = bytes[12] * 256 + bytes[13], second = bytes[14] * 256 + bytes[15];
    pose.targetFirstQ4 = (int16_t)(first <= 32767 ? first : first - 65536);
    pose.targetSecondQ4 = (int16_t)(second <= 32767 ? second : second - 65536);
    pose.targetKnown = (bytes[3] & 4) != 0;
    return pose;
}

enum { SP_ROUTE_MAX_LEGS = 8, SP_ROUTE_RADIUS_Q4 = 8 };
typedef struct { SPAIWorldPose start, end; bool calibrated; } SPAIRouteLeg;
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
    route->legs[route->count++] = (SPAIRouteLeg){start, end, false};
    return true;
}

static inline void sp_ai_route_calibrate_leg(SPAIRouteLeg *leg, SPAIWorldPose first, SPAIWorldPose second) {
    if (!first.valid || !second.valid || !first.headingKnown || !second.headingKnown ||
        first.map != leg->start.map || second.map != first.map ||
        first.epoch != leg->start.epoch || second.epoch != first.epoch || second.observedAt <= first.observedAt ||
        sp_ai_heading_delta(first.heading, leg->start.heading) > 5 ||
        sp_ai_heading_delta(second.heading, leg->start.heading) > 5 ||
        sp_ai_pose_distance2(first, second) < 16) return;
    double dx = (double)leg->end.firstQ4 - leg->start.firstQ4, dy = (double)leg->end.secondQ4 - leg->start.secondQ4;
    double x = (double)second.firstQ4 - first.firstQ4, y = (double)second.secondQ4 - first.secondQ4;
    double along = x * dx + y * dy, cross = x * dy - y * dx;
    leg->calibrated = along > 0 && 16 * cross * cross <= along * along;
}

static inline SPAIRouteDecision sp_ai_route_probe_leg(const SPAIRoute *route, unsigned legIndex, SPAIWorldPose pose) {
    if (legIndex >= route->count) return SP_ROUTE_COMPLETE;
    if (!pose.valid) return SP_ROUTE_UNKNOWN;
    const SPAIRouteLeg *leg = &route->legs[legIndex];
    if (pose.map != leg->start.map) return SP_ROUTE_OFF_ROUTE;
    const double radius2 = SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4;
    if (sp_ai_pose_distance2(pose, leg->end) <= radius2 &&
        (legIndex + 1 == route->count || sp_ai_pose_distance2(pose, route->legs[legIndex + 1].start) <= radius2))
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

static inline SPAIRouteDecision sp_ai_route_probe(const SPAIRoute *route, SPAIWorldPose pose) {
    return sp_ai_route_probe_leg(route, route->next, pose);
}

static inline unsigned sp_ai_route_later_entry(const SPAIRoute *route, SPAIWorldPose pose) {
    if (!pose.valid || !pose.headingKnown) return route->count;
    unsigned match = route->count;
    for (unsigned i = route->next + 1; i < route->count; ++i) {
        const SPAIRouteLeg *leg = &route->legs[i];
        if (!leg->calibrated || pose.epoch != leg->start.epoch) continue;
        SPAIRouteDecision decision = sp_ai_route_probe_leg(route, i, pose);
        bool canTurnAtStart = decision == SP_ROUTE_FACE &&
            sp_ai_pose_distance2(pose, leg->start) <= SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4;
        if (decision != SP_ROUTE_FORWARD && !canTurnAtStart) continue;
        if (match != route->count) return route->count;
        match = i;
    }
    return match;
}

static inline double sp_ai_route_hold(const SPAIRoute *route, SPAIWorldPose pose) {
    return sp_ai_pose_distance2(pose, route->legs[route->next].end) <= 16 * 16 ? 0.20 : 0.60;
}

static inline double sp_ai_axis_angle(double x, double y, double tx, double ty) {
    return atan2(x * ty - y * tx, x * tx + y * ty) * (128.0 / 3.14159265358979323846);
}

static inline bool sp_ai_projected_approach(SPAIWorldPose before, SPAIWorldPose after) {
    if (!before.valid || !before.targetKnown || !after.valid || before.map != after.map ||
        before.epoch != after.epoch || after.observedAt <= before.observedAt) return false;
    double dx = (double)after.firstQ4 - before.firstQ4, dy = (double)after.secondQ4 - before.secondQ4;
    double tx = before.targetFirstQ4, ty = before.targetSecondQ4;
    double along = dx * tx + dy * ty;
    return along > 0 && along * along >= 4 * (tx * tx + ty * ty);
}

static inline bool sp_ai_recorded_leg_contains(SPAIRouteLeg leg, double firstQ4, double secondQ4) {
    double x = firstQ4 - leg.start.firstQ4, y = secondQ4 - leg.start.secondQ4;
    double dx = (double)leg.end.firstQ4 - leg.start.firstQ4, dy = (double)leg.end.secondQ4 - leg.start.secondQ4;
    double along = x * dx + y * dy, across = x * dy - y * dx, length2 = dx * dx + dy * dy;
    const double radius2 = SP_ROUTE_RADIUS_Q4 * SP_ROUTE_RADIUS_Q4;
    if (along < 0) return x * x + y * y <= radius2;
    if (along > length2) {
        x -= dx;
        y -= dy;
        return x * x + y * y <= radius2;
    }
    return length2 > 0 && across * across <= radius2 * length2;
}

static inline bool sp_ai_target_in_recorded_corridor(const SPAIRoute *route, SPAIWorldPose pose) {
    for (unsigned i = 0; i < route->count; ++i) {
        SPAIRouteLeg leg = route->legs[i];
        if (leg.calibrated && leg.start.map == pose.map &&
            sp_ai_recorded_leg_contains(leg, pose.firstQ4, pose.secondQ4) &&
            sp_ai_recorded_leg_contains(leg, (double)pose.firstQ4 + pose.targetFirstQ4,
                (double)pose.secondQ4 + pose.targetSecondQ4)) return true;
    }
    return false;
}

static inline bool sp_ai_target_heading(const SPAIRoute *route, SPAIWorldPose pose, uint8_t *desired) {
    if (!pose.valid || !pose.headingKnown || !pose.targetKnown ||
        (!pose.targetFirstQ4 && !pose.targetSecondQ4)) return false;
    bool calibrated = false;
    for (unsigned i = 1; i < route->count; ++i) {
        SPAIRouteLeg a = route->legs[i - 1], b = route->legs[i];
        if (!a.calibrated || !b.calibrated || a.start.map != pose.map || b.start.map != pose.map) continue;
        int heading = sp_ai_heading_error(b.start.heading, a.start.heading);
        unsigned separation = sp_ai_heading_delta(b.start.heading, a.start.heading);
        if (separation < 48 || separation > 80) continue;
        double ax = (double)a.end.firstQ4 - a.start.firstQ4, ay = (double)a.end.secondQ4 - a.start.secondQ4;
        double bx = (double)b.end.firstQ4 - b.start.firstQ4, by = (double)b.end.secondQ4 - b.start.secondQ4;
        double observed = sp_ai_axis_angle(ax, ay, bx, by);
        if (fabs(fabs(observed) - separation) > 10.0) continue;
        double sign = ((observed > 0) == (heading > 0)) ? 1 : -1;
        uint8_t fromA = (uint8_t)(a.start.heading + lround(sign * sp_ai_axis_angle(ax, ay, pose.targetFirstQ4, pose.targetSecondQ4)));
        uint8_t fromB = (uint8_t)(b.start.heading + lround(sign * sp_ai_axis_angle(bx, by, pose.targetFirstQ4, pose.targetSecondQ4)));
        if (sp_ai_heading_delta(fromA, fromB) > 10 || (calibrated && sp_ai_heading_delta(*desired, fromA) > 10))
            return false;
        *desired = fromA;
        calibrated = true;
    }
    return calibrated;
}
#endif
