#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../ai-encounter.h"

typedef struct {
    double now, movementEndsAt;
    uint16_t distance;
    uint8_t playerHP, targetHP, positionCounter;
    unsigned targetCommands, movementCommands, attacks, hits, lootCommands, stalls, approaches;
    bool selected, inCombat, looted, blockAllMovement, suppressDamage, rejectAttack;
    SPAIRoute route;
    int32_t routePositionQ4;
    SPAIApproachModel model;
    unsigned modelMoves;
    bool lateralBlocked, lateralPulse;
} GameSimulator;

static bool submit(void *context, const char *action, SPAINavSample sample, double hold) {
    GameSimulator *game = context;
    assert(sample.at == game->now);
    if (!strcmp(action, "TARGET")) {
        ++game->targetCommands;
        bool atSpawn = game->route.count ? game->routePositionQ4 >= 32 : game->now >= 2;
        game->selected = !game->looted && atSpawn;
    } else if (!strcmp(action, "FORWARD") || !strcmp(action, "STRAFE_LEFT")) {
        assert((game->route.count || game->selected) && game->targetHP > 0 && hold == 0.60);
        ++game->movementCommands;
        game->lateralPulse = !strcmp(action, "STRAFE_LEFT");
        game->movementEndsAt = game->now + hold;
    } else if (!strcmp(action, "ATTACK")) {
        assert(game->selected && game->targetHP > 0);
        ++game->attacks;
        if (game->rejectAttack) return false;
        if (game->distance <= 16 && !game->suppressDamage) {
            ++game->hits;
            game->targetHP -= 50;
            game->inCombat = game->targetHP > 0;
        }
    } else if (!strcmp(action, "LOOT")) {
        assert(game->selected && !game->targetHP && game->distance <= 16 && !game->inCombat);
        ++game->lootCommands;
        game->looted = true;
    } else {
        assert(!"unexpected action");
    }
    return true;
}

static void release(void *context) {
    GameSimulator *game = context;
    game->movementEndsAt = 0;
}

static void observe_navigation(void *context, SPAINavOutcome result, SPAINavSample before, SPAINavSample after) {
    GameSimulator *game = context;
    assert(before.evidence.target && before.evidence.target == after.evidence.target);
    if (result == SP_NAV_STALLED) ++game->stalls;
    if (result == SP_NAV_CLOSER) {
        assert(after.evidence.distance < before.evidence.distance);
        ++game->approaches;
    }
}

static void note(void *context, const char *message) {
    GameSimulator *game = context;
    if (!strcmp(message, "AI policy: measured approach model selected forward")) ++game->modelMoves;
}

static SPAIEncounterObservation sample(GameSimulator *game) {
    if (game->movementEndsAt && game->now >= game->movementEndsAt) {
        game->movementEndsAt = 0;
        if (!game->blockAllMovement && !(game->lateralPulse && game->lateralBlocked) && game->movementCommands > 1) {
            if (game->selected) game->distance -= game->distance > 44 ? 28 : game->distance - 16;
            else game->routePositionQ4 += 16;
            ++game->positionCounter;
        }
    }
    uint8_t flags = 1, meta = 129, corpse = 0;
    uint8_t column = game->lateralBlocked && game->distance > 16 ? 6 : 8;
    if (game->selected) {
        if (game->targetHP) {
            flags |= 4 | 8;
            meta = 129 + 8 * column;
        } else {
            flags |= 4 | 16 | 128;
            meta = 133;
            corpse = SP_CORPSE_LOCAL_KILL | SP_CORPSE_LOOT_AVAILABLE | SP_CORPSE_RANGE_IN;
        }
    }
    if (game->inCombat) flags |= 32;
    SPAINavSample nav = {game->now, {SP_MOTION_POSITION, game->positionCounter, game->looted},
        {game->selected ? 1 : 0, 1, SP_AI_TAB_BOUND | SP_AI_ROTATION_BOUND,
            game->selected ? game->distance : SP_AI_DISTANCE_UNKNOWN},
        game->selected && game->targetHP ? column : 0};
    SPAIWorldPose pose = {.map = 0, .secondQ4 = game->routePositionQ4, .heading = 64, .epoch = 1,
        .valid = game->route.count > 0, .headingKnown = true, .observedAt = game->now};
    return (SPAIEncounterObservation){nav, flags, game->playerHP, game->targetHP, meta, 1 | 4, corpse,
        sp_ai_hp_known(game->playerHP) ? SP_HEALTH_PUBLIC : SP_HEALTH_RESTRICTED, pose,
        {game->hits % 4, game->selected && game->hits > 0}};
}

static void run(GameSimulator *game, const char *finish, bool requireLoot) {
    SPAIEncounter planner = {.combatEvidence.lastHP = 255, .route = game->route, .approachModel = game->model};
    SPAIApproachExamples examples = {0};
    SPAIEncounterAdapter adapter = {game, submit, release, observe_navigation, note};
    bool lootConfirmed = false;
    for (game->now = 1; game->now < 35; game->now += 0.5) {
        SPAIEncounterObservation observed = sample(game);
        const char *phase = sp_ai_advance(&planner, observed, game->now, false, &examples, adapter);
        if (!strcmp(phase, "LOOT OK")) {
            lootConfirmed = true;
            game->selected = false;
            game->targetHP = 100;
        }
        if (!strcmp(phase, finish) && (!requireLoot || lootConfirmed)) return;
    }
    fprintf(stderr, "did not reach phase %s\n", finish);
    assert(!"simulator timed out");
}

int main(void) {
    GameSimulator farm = {.distance = 72, .playerHP = 100, .targetHP = 100};
    run(&farm, "SEARCH", true);
    assert(farm.stalls == 1 && farm.approaches >= 2 && farm.hits == 2 && farm.lootCommands == 1);
    assert(farm.targetCommands >= 3);
    printf("Farming cycle: %u stall, %u measured approaches, %u hits, %u loot, returned to search\n",
        farm.stalls, farm.approaches, farm.hits, farm.lootCommands);

    GameSimulator wall = {.distance = 72, .playerHP = 100, .targetHP = 100, .blockAllMovement = true};
    run(&wall, "NAV BLOCK", false);
    assert(wall.stalls == 2 && wall.movementCommands == 2 && wall.hits == 0 && wall.lootCommands == 0);

    GameSimulator noDamage = {.distance = 12, .playerHP = 100, .targetHP = 100, .suppressDamage = true};
    run(&noDamage, "NO DAMAGE", false);
    assert(noDamage.attacks == 4 && noDamage.hits == 0 && noDamage.lootCommands == 0);

    GameSimulator rejected = {.distance = 12, .playerHP = 100, .targetHP = 100, .rejectAttack = true};
    run(&rejected, "INPUT BLOCK", false);
    assert(rejected.attacks == 3 && rejected.hits == 0);

    GameSimulator protectedHealth = {.distance = 12, .playerHP = 255, .targetHP = 100};
    run(&protectedHealth, "HP SECRET", false);
    assert(protectedHealth.targetCommands == 0 && protectedHealth.attacks == 0 && !protectedHealth.selected);

    GameSimulator waypointFarm = {.distance = 12, .playerHP = 100, .targetHP = 100};
    SPAIWorldPose start = {.heading = 64, .epoch = 1, .valid = true, .headingKnown = true};
    SPAIWorldPose end = start;
    end.secondQ4 = 40;
    assert(sp_ai_route_append(&waypointFarm.route, start, end));
    run(&waypointFarm, "SEARCH", true);
    assert(waypointFarm.routePositionQ4 == 32 && waypointFarm.movementCommands == 3);
    assert(waypointFarm.hits == 2 && waypointFarm.lootCommands == 1);

    GameSimulator waypointWall = {.distance = 12, .playerHP = 100, .targetHP = 100, .blockAllMovement = true,
        .route = waypointFarm.route};
    run(&waypointWall, "ROUTE BLOCK", false);
    assert(waypointWall.movementCommands == 2 && waypointWall.routePositionQ4 == 0 && !waypointWall.selected);

    GameSimulator rules = {.distance = 44, .playerHP = 100, .targetHP = 100, .lateralBlocked = true};
    GameSimulator learned = rules;
    SPAINavSample measured = {1, {SP_MOTION_POSITION, 1, false}, {1, 1, 0, 44}, 6};
    for (unsigned i = 0; i < 6; ++i) {
        assert(sp_ai_train_approach(&learned.model, measured, SP_MOVE_LEFT, SP_NAV_STALLED));
        assert(sp_ai_train_approach(&learned.model, measured, SP_MOVE_FORWARD, SP_NAV_CLOSER));
    }
    run(&rules, "NAV BLOCK", false);
    run(&learned, "SEARCH", true);
    assert(rules.modelMoves == 0 && rules.stalls == 2 && rules.hits == 0);
    assert(learned.modelMoves >= 1 && learned.hits == 2 && learned.lootCommands == 1);

    puts("Production planner simulator passed farming, wall, no damage, rejected attack and protected health");
    puts("Recorded route simulator passed waypoint, resumed mob search, farm and route blockage");
    puts("Controlled comparison: rules stopped at the lateral obstruction, trained policy completed farming");
}
