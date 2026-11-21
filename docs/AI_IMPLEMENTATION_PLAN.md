# Implementeringsplan för Slashplayed AI

Målet är att den befintliga AI-knappen ska ge en begriplig väg från observation till verifierad målrörelse och därefter en verifierad farmingcykel i en uttryckligen godkänd testmiljö. Prioritera den lokala regelmotorn och det befintliga inputlagret. WoW kör vidare lokalt på telefonen.

## Verifierad utgångspunkt

På iPhone med `d7bfd0e` visar loggen `OBSERVING`, `player=restricted`, `target=none`, `position=public`, `distance=unknown`, `tab=verified` och `f12=verified`. Observationen skickar ingen input. I autonomt testläge avbryter `sp_ai_advance` före första handlingen om offentlig spelarhälsa saknas. En tidigare manuell W-puls bekräftade positionsförändring. Minskning av avståndet till ett valt mål har ännu inte verifierats på telefonen.

## 1. Hitta rätt läge från en knapp

- [x] Döp om observationsfasen till `OBS ONLY` i `slashplayed/mobile/game-ai.m`. Behåll `AI STALE` när observationen saknar färsk data.
- [x] Återanvänd den befintliga testmenyn från AI-knappen i `slashplayed/mobile/phone-input.m`. Kort tryck växlar sessionen. Långtryck när sessionen är avstängd öppnar alternativen. Ett valt autonomt testläge visar `TEST READY` och väntar på ett separat kort tryck.
- [ ] Verifiera på iPhone att långtryck inte skickar input eller startar en session och att åtgärden för en enda W-puls kan köras från menyn. Verifiera att bakgrundsläge återställer till observation och att manuell touch avbryter ett aktivt styrprov.

## 2. Mät de signaler som krävs för målrörelse

- [ ] Välj en stillastående NPC manuellt i observation medan telefonen står på fri mark. Använd `AI world` i `game-ai.m` för att verifiera att målidentitet, nameplate och avstånd till samma mål håller ihop när kameran rör sig och när användaren går närmare. Gör ett andra prov med terräng som stoppar karaktären. Anteckna exakt vilka värden som blir skyddade, saknas eller är inaktuella.
- [ ] Lägg i `phone-input.m` till ett användarstartat prov med ett redan valt mål som återanvänder `sp_ai_nav_outcome` från `ai-direct.h`. Begränsa provet till en framåtpuls om högst 0,60 s på fri mark. Kräv färsk startposition, stabil målidentitet, verifierad W-bindning och disambiguera `closer`, `displaced`, `stalled`, målförlust och avbruten input i loggen. En knapptryckning utan bekräftad rörelse ska ge ett mätbart fel.
- [ ] Kör fallen i `tests/test_ai_direct.c` med oförändrat avstånd, minskat avstånd, växlat mål, skyddad position, försenade paket, blockerad rörelse och manuell avbrytning. Kontrollera samma-id före och efter varje puls på telefonen. Utan tillförlitligt målavstånd stannar leveransen vid `TEST MOVED` eller motsvarande precis status.

## 3. Flytta testet från manuell puls till reglerad styrning

- [ ] Använd `HealthTelemetry.lua` och `AI health evidence` för att verifiera att godkänd testmiljö kan leverera färsk offentlig spelarhälsa före och under strid. Om den saknas i målmiljön kan nästa experiment pröva en synlig, entydigt identifierad egen hälsomätare. Håll den separerad som diagnostisk källa tills skyddad, dold, omflyttad och föråldrad visuell information kan avvisas och mätningen jämförts med en oberoende referens för låg och normal hälsa. Behåll `HP SECRET` som stoppvillkor tills en godkänd signal faktiskt fungerar.
- [ ] Återanvänd `sp_ai_advance` i `ai-encounter.h` och exekveraren i `phone-input.m`. Börja på fri mark med ett manuellt valt mål. Kräv `APPROACH` med minst ett uppmätt minskat avstånd till samma mål och en separat räckviddsobservation vid ankomst. Kör hinderprovet och verifiera att pulser upphör efter fastkörning eller upprepade riktningsbyten.
- [ ] Kör `SEARCH` och `ENGAGE` först när det kontrollerade närmandet fungerar. Verifiera att Tab gav ett relevant mål, att F12 följdes av en verifierad träff från spelaren och att `NO DAMAGE` stoppar fortsatta försök när träff saknas. Verifiera loot mot rätt kropp med matchad lootkvittens och inventarieändring, följt av `SEARCH`. Spela upp motsvarande framgångs- och felvägar i `tests/test_ai_direct.c` och `tests/test_health_telemetry.lua`.

## 4. Bygg och mät varje milstolpe

- [ ] Kör befintliga C-, Lua- och staging-tester. Kör `.github/workflows/slashplayed-mobile-touch.yml`, hämta Windows Companion-paketet och verifiera SHA-256. Uppdatera den befintliga appen med samma bundle-ID och signeringsteam.
- [ ] Följ `docs/AI_DEVICE_VALIDATION.md` och spara commit, iOS-version, spelversion, provmiljö, läge, observation, avsett kommando, adapterkvittens och observerat utfall. Jämför temperatur och FPS med samma scens läge och grafikinställningar. Verifiera `AI HEAT` genom ett kontrollerat test av kritisk temperatur i testmiljö utan att värma upp telefonen med avsikt.
- [ ] Redovisa målrörelse och farming som två separata enhetsmilstolpar. Varje status kräver egen enhetslogg med korrekt utfall. Modellbyte motiveras först om en uppmätt brist i observationskvalitet kvarstår och alternativet testats för korrekthet, värme och latens.
