# iPhone-validering för Slashplayed AI

## Installation och första kontroll

1. Ladda ner Slashplayed-iPhone-Wolkara-Windows-Companion från mobilkörningen för aktuell commit. Packa upp yttre ZIP-filen och kör Get-FileHash på slashplayed-wolkara-device-kit.zip. Jämför SHA256 med SHA256SUMS.txt.
2. Anslut och lås upp telefonen med USB. Kontrollera att Apple Devices och slashplayed-cli.exe devices listar den. Använd Slashplayed CLI 1.5.1 och kör .\\slashplayed-cli.exe --kit "C:\\sökväg\\slashplayed-wolkara-device-kit.zip" i PowerShell. Använd samma signeringsteam och bundle-ID som för befintlig app.
3. Starta den befintliga Forever-installationen. Anteckna CI-commit, iOS-version, Forever-klientens build, testområde, vilka bindningar som används och om Apple Intelligence eller modellpaket är installerade. Bekräfta touch, kamera, Wolkara, Tactara F12 och att spelet renderas lokalt.

## Manuell diagnostik före autonomi

Verifierat den 21 november 2026 på iPhone 17 Pro Max med iOS 27.3 och device-kitet från `d692e5b`. Forever startade och publicerade en fristående SPHover-heartbeat. Det manuella provet loggade verifierad W-bindning, adapteracceptans och sedan `displacement-only`. Skärmen visade `TEST MOVED`. Prov mot hinder, närmande till valt mål och hela farmingcykeln återstår.

1. Ställ spelaren på plan, fri mark där testet är tillåtet. Vänta stilla tills SPHover-telemetri är färsk. Låt modeller vara avstängda.
2. Håll inne tangentbordsknappen och välj **Test AI movement (forward)**. Anteckna först TEST ACCEPT eller TEST INPUT och sedan TEST MOVED, TEST STALL eller TEST NO DATA. Bekräfta med synlig position före och efter pulsen.
3. Upprepa mot ett ofarligt hinder. TEST STALL förutsätter en fungerande positionskälla och oförändrad räknare. Prova att avbryta med touch och att bakgrundslägga appen under pulsen. Lyft alla manuella kontroller och kontrollera att ingen kvarhängande rörelse finns.
4. I godkänt autonomt testläge, ta över medan agenten rör sig och verifiera AI PAUSED, direkt släpp av rörelsetangenten och avsaknad av nya AI-kommandon. Fortsätt styra manuellt. Håll inne AI-knappen och välj **Resume after manual control**. Verifiera att agenten väntar på färsk telemetri innan nästa försök. Tryck kort i pausläge för att kontrollera att sessionen stoppas med AI OFF.

## Godkända autonoma testfall

1. I den uttryckligen tillåtna miljön, bind Tab till närmaste fiende, Tactaras huvudrotation till F12, W till framåt samt Q/A och E/D till sidsteg. Bind F eller F10 till Interact With Target. Välj **Toggle automation on authorized test realm** och tryck på samma AI-knapp.
2. Använd ett stillastående tydligt mål framför spelaren på fri mark. Första milstolpen kräver accepterad puls, färskt positionsutfall och observerat minskat målavstånd för samma mål. Jämför med det som faktiskt syns i spelet. Testa sedan ett hinder och verifiera att NAV BLOCK hindrar fortsatt rörelse.
3. För farmingmilstolpen ska samma mål ge en faktisk spelträff med egen källa, död, matchad loot och inventarieändring, följt av SEARCH. Spara logg och tidsstämplar. F12, mål-HP och indikatorer ensamma räcker inte för bekräftelse av egen träff.
4. Prova utebliven skada, fel bindning, inget mål och stängt lootfönster utan loot. Notera status, väntetid och antal accepterade försök.
5. Kontrollera `kill=player-or-pet` efter ett manuellt dödsfall där rätt mål är valt. Den signalen bygger på offentlig angripar- och målidentitet i `PARTY_KILL`. `interact-range=out` ska ge `LOOT RANGE` och spara försöksbudgeten tills målet går att nå. `loot=available` anger möjlighet att interagera och den senare matchade slotkvittensen anger att en slot tömdes.
6. Kör en manuell F12-attack och sedan motsvarande agentattack i den tillåtna testmiljön. Jämför `AI input: Tactara F12 rotation`, `AI combat: selected target health decreased` och `AI combat: matched local damage on selected target`. Den sista signalen förutsätter att klienten exponerar ett läsbart publikt stridsevent med den egna spelaren som källa. Kontrollera separat att en annan spelares attack och en otillgänglig stridslogg inte kvitterar agentens attack. Forever-stödet för denna källa återstår att verifiera.

## Loggar och resursprov

Hämta spconsole.log från Slashplayeds dokumentmapp under **På min iPhone** via Filer eller Apple Devices fildelning. Hämta roterad logg från samma mapp om appen startats om. Kopiera relevanta rader med **AI telemetry**, **AI health evidence**, **AI world**, **AI phase**, **AI action**, **AI navigation**, **AI input**, **AI combat**, **AI loot**, **AI thermal**, **AI capture** och **AI Pixel2Play**. Loggraden distance-q4 mäts i kvartsenheter och värdet 65535 anger okänt. Ta även med eventuell Lua-feltext och det spelögonblick som raderna avser.

För ett observationsprov, starta AI utan att slå på autonomt testläge eller modelldiagnostik. Stå först utan mål och välj sedan en synlig NPC manuellt. Jämför hur `AI health evidence` skiljer `public`, `restricted`, `unavailable` och `absent`. `AI world` visar om målets identitet, nameplate och avstånd kunde läsas. Skyddad spelarhälsa ger `HP SECRET` i det autonoma testläget och blockerar input.

För vägpunktstelemetri, kontrollera även `pose=public` och `heading=public` när du står still, vrider karaktären, går framåt och byter område. Loggraden visar tillgänglighet utan att skriva ut råa koordinater. Det separata AP-paketet och den ordinarie spelstatusen måste ha samma sekvens och positionsepok. Testa att skyddad eller saknad riktning lämnar `heading=unknown`. Axlarna från `UnitPosition` transporteras i API:ets ordning. Kalibrera deras relation till spelarens riktning innan de används för att styra rörelse.

Spela in en redan genomgången rak sträcka enligt installationsguiden. Återvänd till startpunkten, rikta spelaren åt det inspelade hållet och starta godkänt testläge utan valt mål. Förvänta `SEARCH → ROUTE → WAYPOINT → SEARCH` och att varje rörelse håller sig inom den inspelade korridoren. Upprepa med annan riktning, karta, ett ofarligt hinder och touch mitt i sträckan. Bekräfta att planeringen visar `FACE ROUTE` eller stoppar när riktningsdata saknas. Verifiera att `ROUTE BLOCK` stoppar upprepningar mot hindret. Kör samma väg med en fientlig NPC först vid slutpunkten för att verifiera att sökningen återupptas där.

Enhetsprov den 21 november 2026 på `910380a` visade `player=restricted` med `target=absent` före strid. Spelarposition var offentlig och Tab och F12 var verifierat bundna. På det bygget behöver du välja målet före AI-knappen, eftersom ett manuellt tryck annars stänger observationen.

Enhetsloggen från samma dag visar att iOS gick från FAIR till SERIOUS mellan 12.57 och 13.03. AI visade tidigare HEAT PAUSE fast observationen fortsatte. WoW låg nära 60 FPS även före AI-start. Inga fångst- eller modellmätningar loggades runt övergången. Loggen visar temperaturförloppet men räcker inte för att fördela kostnaden mellan spelrendering och telemetri.

Kör jämförbara pass med samma kameravinkel, upplösning, FPS-gräns, laddstatus och starttemperatur. Börja med normal WoW-rendering och AI av. Jämför observation utan modeller, regler i tillåtet testläge och observation med modelldiagnostik. Anteckna FPS, sessionstid och temperaturstatus. Vid tillgång till Xcode Instruments, mät renderings- och CPU-tid, Core ML, GPU, minne och energi per pass. AI capture rapporterar väntetid vid bildutläsning och tid för skalning på CPU, och AI Pixel2Play rapporterar prediktionstid.

Den lilla lokala rörelsemodellen behöver mätbara utfall för båda rörelserna på samma sida om en nästan centrerad målplatta. Testa i godkänd miljö med färsk offentlig målidentitet, position och avstånd. Jämför `AI policy: rules selected approach` och `AI policy: measured approach model selected forward` med efterföljande `AI navigation`. Kontrollera uteblivet modellval med otillräckligt underlag, borttagen målplatta och medan spelaren är i strid.

Kontrollera att FAIR pausar valfri modellinferens och bildfångst för modelldiagnostik. Modelldiagnostiken får återupptas vid NOMINAL. Vid SERIOUS utvärderar agenten observationer var 0,8 sekund och väntar minst 2 sekunder mellan automatiska rörelsepulser i testläget. Statusen visar aktuell fas, medan AI thermal loggar observationsintervall och modellstatus. Vid CRITICAL visas AI HEAT och agenten stoppar och släpper input. Avsluta värmeprovet om telefonen signalerar överhettning.
