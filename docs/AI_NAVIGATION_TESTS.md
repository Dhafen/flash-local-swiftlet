# Reproducerbara agenttester

Kör från roten med C11-kompilator och Lua 5.1. GitHub Actions kör motsvarande tester i combat-addon-tests och stagningen i keyboard-device-kit.

~~~bash
cc -std=c11 -Wall -Wextra -Werror slashplayed/mobile/tests/test_ai_direct.c -o /tmp/sp-ai-direct
/tmp/sp-ai-direct
lua5.1 slashplayed/mobile/tests/test_health_telemetry.lua slashplayed/mobile/HealthTelemetry.lua
cc -std=c11 -Wall -Wextra -Werror slashplayed/mobile/tests/test_touch_zone.c -o /tmp/sp-touch-zone
/tmp/sp-touch-zone
~~~

| Fall | Kontroll |
| --- | --- |
| Målsökning | C-policy väntar under strid utan giltigt mål. Avvisar spelare, vänliga eller döda mål som stridsmål. |
| Stale, okänt och skyddat | C provar gammalt, identiskt, framtida och sent paket. Lua testar okänd hälsa, skyddat mål, saknad position och skyddad bindning. |
| Rörelse, vägg, fel riktning | C provar accepterad puls med stillastående counter, enbart speed, positionsbyte utan närmande, ökande avstånd och minskat avstånd. |
| Avbruten kontext | C avvisar annan mål- eller positionsepok. Lua provar byte av karta och teleport. Staging inspekterar release och stop vid touch, fysisk knapp, bakgrund och kritisk värme. |
| Instabil styrning | C provar två misslyckade utfall, upprepad sidoreversering med framåtrörelse mellan bytena och tolv-pulsgräns. |
| Bindningar | Lua testar rätt W, Q/A, E/D, Tab, F12 och interact. C kontrollerar gamla packets och verifierad rörelsetangent. |
| Combat och loot | C verifierar att accepterad F12 utan HP-minskning når försöksgränsen. Lua kräver en matchad loot-slot. Samma test provar fel källa, rätt källa och fönster som öppnas och stängs utan kvittens. |
| Värme och livscykel | Staging verifierar kopplingen i genererad kod för stopp, opt-in-reset och långsammare poll. Faktiska UIKit-händelser och resursmätningar finns i enhetsprotokollet. |

Den första regressionen gick röd på e2683f0 när två speed-samplingar med olika räknare gav positivt rörelseutfall. Korrigeringen kräver positionskälla vid båda observationerna.
