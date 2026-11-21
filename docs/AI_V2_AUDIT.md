# Slashplayed Agent V2

## Bas och körväg

- Fork `Dhafen/flash-local-swiftlet`, bas `work/slashplayed-levelbot-engine` vid `ada4a90c93f3483ad5ca2ef937f4cc5312b45a03` och PR #8. Tidigare mobilintegration finns på `experiment/slashplayed-laya-p2p`. Ersättningsgren `work/slashplayed-agent-v2`.
- Byggflödet lägger mobilpatcharna över Slashplayed 1.5.1, pinnad till upstream `976f9248971238187a82c8c55f69b23054055343`. Forkens byggflöde äger paketeringen.
- `phone-input.m` äger knappar, touch, joystick och tangentadapter. `game-ai.m` äger session och diagnostik. `ai-encounter.h` äger den tidigare aktiva encounterplaneraren och `ai-navigation.h` äger rutter. SPHover levererar offentliga observationer från `HealthTelemetry.lua` via den befintliga renderingsremsan, vars integration genereras i `patch.py`.
- Den oanropade `startScreen`-vägen med ReplayKit, helbilds-OCR och generell Vision-klassificering har tagits bort. Den lokala Metal-fångsten för hälsodiagnostik och Pixel2Play finns kvar. Laya och Pixel2Play föreslår enbart i diagnostikläge. Den tidigare encounterplaneraren fungerar som inkopplad bas tills dess ersättare klarar samma simulerade scenarier.

## Tekniska referenser och arkitekturval

- Wodex beskriver hur en lokal runtime verifierar observationer efter handlingar, och hur bekräftade rutter återanvänds i en atlas. Implementationen är privat. Demonstrationerna är från Steam Deck och ger ingen uppmätt iPhone-prestanda. [Wodex](https://github.com/simpx/wodex)
- WowClassicGrindBot har en publik navigationsimplementation med vägpunkt, avstånd och fastkörningslogik. Den använder andra observationskällor och separat pathfinding. Ingen extern kod importerades. [Navigationskällan](https://github.com/Xian55/WowClassicGrindBot/blob/c5bc4fb614b2054f10b1b377581d39fcb205c2fa/Core/GoalsComponent/Navigation.cs)
- WoW Eye har MIT-licens och dokumenterar Forever-data för kartmarkörer, kompass och questmål. MCP-sidan läser ögonblicksbilder vid UI-omladdning. Det passar som referens för senare questplanering och lokalt kartminne. Rörelse behöver färskare signaler från renderingsremsan. [WoW Eye](https://github.com/TravinDSO/woweye)
- GOAP kan välja mellan flera mål när förutsättningarna går att observera. En kort reaktiv prioritetsordning kan avbryta en väntande handling vid manuell input, skyddad telemetri eller låg hälsa. Använd spelmotorns offentliga fakta före bildtolkning. Metal-utläsningen av hälsomätaren är en avgränsad kandidat för jämförelseprov. Vision eller Core ML kräver ett mätbart problem och en märkt testmängd. [Orkins GDC-presentation](https://gdcvault.com/play/1013459/Three-States-and-a-Plan) · [Apple Vision](https://developer.apple.com/documentation/vision) · [Core ML](https://developer.apple.com/documentation/coreml)

## Första rörelse- och observationsändringarna

- Bygget `ada4a90` installerades med befintlig appidentitet på iPhone 17 Pro Max. På telefonen gav samma levande fientliga mål offentlig identitet och skalärt avstånd, medan pose, riktning och målvektor var okända. Hälsan förblev skyddad. Klienten exponerade även loot och interaktionsavstånd för en vald kropp. Provet kördes i observationsläget.
- Renderingsremsan levererar 113 nyttolastbyte inklusive nollutfyllnad. Pose, XP och hälsomätarens geometri kräver en 18 byte lång post. Native-dispatchen normaliserar nu formatet före avkodning och avvisar extra data. Regressionen använder samma utfyllnad som på telefonen.
- `ai-movement.h` håller en tidsbegränsad rörelse i taget och äger dess key-up eller återställning av joystick. Ägarskapet har egen generation. Normal utgång för rörelse och avbrott av diagnos eller agent har separata generationer, så manuell övertagning kan stoppa väntande återkoppling. Adapteracceptans blir aldrig bevis på rörelse. Utfallet kräver en ny lokal observation i `sp_ai_nav_observe`.

## Milstolpar på fysisk enhet

Efter installation av detta bygge ska observationsloggen först visa om `pose`, `heading` och `target-vector` återkommer. Prova därefter en manuell puls mot en levande fiende med samma mål före och efter, och kontrollera `TEST CLOSER` ihop med ändrat avstånd. Prova sedan avbrott och key-up. Autonoma testfall förutsätter en uttryckligen godkänd testmiljö och tillförlitlig spelarhälsa.

Ingen fysisk milstolpe för kontinuerlig navigation, verifierad första kill, 20 kills, 30-minuterssession eller quest från accept till turn-in har godkänts.
