# Agentens körlägen och övergångar

| Läge | Observation och input |
| --- | --- |
| Simulerad spelstatus | C-tester använder produktionspolicy och syntetiska paket. Lua-tester mockar offentliga spel-API:er. |
| Rörelsediagnostik | Uttryckligt menyval sänder en enstaka framåtpuls och visar adapter- och positionsutfall. |
| Användarstyrt | AI-knappen startar eller stoppar observation. Touch och F12 styr spelet manuellt. Vid opt-in kan lokala modeller lämna diagnoser. |
| Autonomt test | En separat behörighetsmarkering i samma UI aktiverar AI-knappens regelbaserade testloop. Använd läget i en uttryckligen tillåten testmiljö. |

SPHover läser offentlig spelstatus ungefär två gånger per sekund. ObjC tidsstämplar den ritade observationen innan GPU-callbacken och kräver en ny oberoende heartbeat och högst 0,85 s ålder för input. En åttabitars mål-/positionsepok och kvantiserat horisontellt avstånd räcker för jämförelse inom en kort puls. Råa GUID:n och koordinater stannar i spelprocessens Lua-lager. Skyddade eller saknade värden ger uttryckliga okända tillstånd.

| Fas | Möjliga övergångar och observerade villkor |
| --- | --- |
| SEARCH | Prova Tab upp till fyra accepterade försök. Offentligt valt levande attackbart NPC-mål med identifierare går till ENGAGE. Om inget mål kan väljas visas NO TARGET. |
| ENGAGE | Prova Tactara F12. Observerad skada eller strid går till IN COMBAT. Utan observerad skada kan ett synligt mål ge APPROACH. Närhet inom fyra horisontella distansenheter prioriterar en ny F12-prob. |
| APPROACH | Bekräfta två riktningstecken från färska paket. Skicka en puls på 0,60 s med verifierad tangent, invänta utfall högst 1,8 s. Enbart bekräftad framåtförflyttning med okänt avstånd får en ny F12-prob. |
| IN COMBAT | Mål-HP behöver faktiskt minska för att återställa F12-budgeten. Högst fyra accepterade F12 utan sådan observation. Matchad vald död NPC och avslutad strid går till LOOT CHECK. |
| LOOT CHECK | Prova på verifierad Interact With Target-bindning. En tömd slot som matchar samma corpse ger LOOT OK och återgång till SEARCH. Två försök utan bekräftelse ger LOOT UNCONF. |
| RECOVER | Låg hälsa under 35 % pausar input tills minst 50 % observeras. Monterad eller död spelare pausar. Återhämtning och återupplivning sker manuellt. |
| BLOCKED / STOPPED | Saknade bindningar, okänd hälsa, stale data eller slut på budget blockerar respektive handling. Ett manuellt övertagande, stopp eller appdeaktivering släpper input och ogiltigförklarar väntande arbete. Kritisk temperatur stoppar loopen. |

Vid APPROACH är adapteracceptans, förflyttning, minskat målavstånd och centrerad nameplate separata signaler. Två misslyckade eller två omätbara pulser blockerar upprepning. En andra sidovändning blockeras även med framåtpulser emellan. Totalgränsen är tolv pulser per valt mål. OBS ONLY och loggen kan användas för manuell felsökning.

Native-exekveraren äger UIKit-fokus, modalgränser, tangent ner/upp, deadlines och kontext. Lyckad input innebär accepterad handling. Mål-HP kan falla på grund av andra källor, och en tömd matchad loot-slot behöver kopplas till ett inventarieresultat i fysisk test. Mätning med kvantiserat avstånd visar observerat framsteg över ett intervall. En spellträff eller faktisk nådd punkt kräver ytterligare bevis.

Navigation sparar begränsade räknare för varje observerat utfall lokalt. Menyns manuella steeringexempel kan fortsatt föreslå framåt i stället för sidsteg när horisontellt målavstånd finns. Räknarna och handexemplen uppdaterar inga modellvikter.
