# Implementeringsplan för Slashplayed AI

Målet är att den befintliga AI-knappen ska ge en begriplig väg från observation till verifierad målrörelse och därefter en verifierad farmingcykel i en uttryckligen godkänd testmiljö. Prioritera den lokala regelmotorn och det befintliga inputlagret. WoW kör vidare lokalt på telefonen.

## Verifierad utgångspunkt

På iPhone med `d7bfd0e` visar loggen `OBSERVING`, `player=restricted`, `target=none`, `position=public`, `distance=unknown`, `tab=verified` och `f12=verified`. Observationen skickar ingen input. I autonomt testläge avbryter `sp_ai_advance` före första handlingen om offentlig spelarhälsa saknas. En tidigare manuell W-puls bekräftade positionsförändring. Minskning av avståndet till ett valt mål har ännu inte verifierats på telefonen.

När användaren valde en fientlig NPC kl. 13.27 den 21 november visade samma bygge `identity=public`, `position=public`, `distance=public` och `plate=unknown`. Båda hälsovärdena rapporterades som skyddade. Ingen riktningssignal loggades i det uppföljande provet när användaren såg namnplattan. Därmed finns mätdata för en användarriktad puls mot samma mål. Den automatiska riktningssignalen och bevis för skada återstår.

Telefonen med `9b9034f` loggade `held verified key w`, `adapter accepted` och `target-closer` den 21 november kl. 13.35. Testet skickade en enda puls på 0,60 s. Det är uppmätt närmande under ett användarstartat prov. Resultatet bekräftar varken att målet nåddes eller att flera pulser fungerade.

REA inventerade det verifierade leveranspaketet i evidens `ev_d1a99c37e6a4dfd45b181a992da26f894448913f964b5a662a3bf5b82d8d2f14`. Paketet innehöll iOS-versionen av `libspAppKit.dylib` och inga medföljande Core ML-modellpaket. Observationen gäller själva zip-filen. Modeller kan installeras separat. [WowClassicGrindBots navigationskod](https://github.com/Xian55/WowClassicGrindBot/blob/dev/Core/GoalsComponent/Navigation.cs) använder separat navigationsstatus och övervakar framsteg mot ruttpunkter. Den här deländringen använder samma princip med offentligt avstånd till valt mål och en begränsad rörelsebudget.

## 1. Hitta rätt läge från en knapp

- [x] Döp om observationsfasen till `OBS ONLY` i `slashplayed/mobile/game-ai.m`. Behåll `AI STALE` när observationen saknar färsk data.
- [x] Återanvänd den befintliga testmenyn från AI-knappen i `slashplayed/mobile/phone-input.m`. Kort tryck växlar sessionen. Långtryck när sessionen är avstängd öppnar alternativen. Ett valt autonomt testläge visar `TEST READY` och väntar på ett separat kort tryck.
- [ ] Verifiera på iPhone att långtryck inte skickar input eller startar en session och att åtgärden för en enda W-puls kan köras från menyn. Verifiera att bakgrundsläge återställer till observation och att manuell touch avbryter ett aktivt styrprov.

## 2. Mät de signaler som krävs för målrörelse

- [ ] Logga i `HealthTelemetry.lua` vilken kontroll i `spAITargetColumn` som avvisar namnplattan. Skilj saknad enhet eller ram, förbjuden ram, dold ram och oläsbar koordinat. Använd `AI world` i `game-ai.m` för att verifiera att målidentitet, namnplatta och avstånd till samma mål håller ihop när kameran rör sig och när användaren går närmare. Behåll `unknown` som riktningsvärde vid avvisning.
- [x] Återanvänd `sp_ai_nav_outcome` från `ai-direct.h` för ett användarstartat framåtprov. Visa när målet faktiskt blev närmare och logga före- och efteravstånd. Lägg till ett separat prov i godkänt testläge med högst tre pulser och ny kontroll av mål, position, avstånd och bindning inför varje puls. Användaren riktar karaktären manuellt inför provet.
- [ ] Kör fallen i `tests/test_ai_direct.c` med oförändrat avstånd, minskat avstånd, växlat mål, skyddad position, försenade paket, blockerad rörelse och manuell avbrytning. Kontrollera samma-id före och efter varje puls på telefonen. Utan tillförlitligt målavstånd stannar leveransen vid `TEST MOVED` eller motsvarande precis status.

## 3. Flytta testet från manuell puls till reglerad styrning

- [ ] Använd `HealthTelemetry.lua` och `AI health evidence` för att verifiera att godkänd testmiljö kan leverera färsk offentlig spelarhälsa före och under strid. Om den saknas i målmiljön kan nästa experiment pröva en synlig, entydigt identifierad egen hälsomätare. Håll den separerad som diagnostisk källa tills skyddad, dold, omflyttad och föråldrad visuell information kan avvisas och mätningen jämförts med en oberoende referens för låg och normal hälsa. Behåll `HP SECRET` som stoppvillkor tills en godkänd signal faktiskt fungerar.
- [ ] Återanvänd `sp_ai_advance` i `ai-encounter.h` och exekveraren i `phone-input.m`. Börja på fri mark med ett manuellt valt mål. Kräv `APPROACH` med minst ett uppmätt minskat avstånd till samma mål och en separat räckviddsobservation vid ankomst. Kör hinderprovet och verifiera att pulser upphör efter fastkörning eller upprepade riktningsbyten.
- [ ] Kör `SEARCH` och `ENGAGE` först när det kontrollerade närmandet fungerar. Verifiera att Tab gav ett relevant mål, att F12 följdes av en verifierad träff från spelaren och att `NO DAMAGE` stoppar fortsatta försök när träff saknas. Verifiera loot mot rätt kropp med matchad lootkvittens och inventarieändring, följt av `SEARCH`. Spela upp motsvarande framgångs- och felvägar i `tests/test_ai_direct.c` och `tests/test_health_telemetry.lua`.

## 4. Bygg och mät varje milstolpe

- [ ] Kör befintliga C-, Lua- och staging-tester. Kör `.github/workflows/slashplayed-mobile-touch.yml`, hämta Windows Companion-paketet och verifiera SHA-256. Uppdatera den befintliga appen med samma bundle-ID och signeringsteam.
- [ ] Följ `docs/AI_DEVICE_VALIDATION.md` och spara commit, iOS-version, spelversion, provmiljö, läge, observation, avsett kommando, adapterkvittens och observerat utfall. Jämför temperatur och FPS med samma scens läge och grafikinställningar. Verifiera `AI HEAT` genom ett kontrollerat test av kritisk temperatur i testmiljö utan att värma upp telefonen med avsikt.
- [ ] Redovisa målrörelse och farming som två separata enhetsmilstolpar. Varje status kräver egen enhetslogg med korrekt utfall. Modellbyte motiveras först om en uppmätt brist i observationskvalitet kvarstår och alternativet testats för korrekthet, värme och latens.
