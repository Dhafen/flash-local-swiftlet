# Slashplayed 1.5.1 med WolkaraForever

Öppna uppdateringen med din befintliga Slashplayed Companion 1.5.1 på Windows.

1. Packa upp den yttre ZIP-filen. Lämna `slashplayed-wolkara-device-kit.zip` som ZIP.
2. Anslut och lås upp din iPhone. Apple Devices ska känna igen den och utvecklarläge ska vara aktiverat.
3. Öppna PowerShell i Companion-mappen. Skriv `./slashplayed-cli.exe --kit ` och dra den inre ZIP-filen till fönstret för att fylla i sökvägen. Tryck Enter.
4. Uppgradera med samma Apple-ID, signeringsteam och bundle-ID, inklusive samma `--bundle-id` om du valde ett eget. Behåll den gamla appen installerad under uppgraderingen.
5. Öppna Slashplayed och starta den befintliga Forever-installationen.

Wolkaras gränssnitt är förvalt på iPhone för Forever och visas på engelska. Du får större gränssnitt, spellhjul, chatt, menyer, karaktärsramar och uppdragskort. Standardlayouten har bara två av Wolkaras klicköppnade hjul (Wheel och Wheel 2). Right Spells och Left Spells börjar på 0. Vid uppgradering fylls lediga platser i hjulen med tidigare sparade sidospells utan att skriva över befintliga val; originalen finns kvar i de dolda sidospellhjulen. Du kan själv slå på sidospellhjul igen i Mobile UI. Slashplayeds extra knappar (Esc, Jump, UI, Edit, kamerahastighet och Reset) är dolda som standard i Forever. Tangentbordet ligger under chatten. Tryck kort för att skriva, eller håll inne tangentbordsknappen för en meny med Escape, Jump, Rotation (F12), byte av touchläge och möjlighet att visa en separat hoppknapp eller återställa alla extra reglage. En liten rund F12-knapp visas på höger sida. Tryck för ett vanligt F12-tangenttryck, eller dra för att flytta knappen (positionen sparas). Tangentbordets långtrycksmeny kan dölja knappen eller återställa positionen. Chatten använder nu F11 internt, inte F12. I spelläget: kort tryck och släpp ger vänsterklick; håll fingret stilla i minst 0,45 sekunder och släpp för högerklick (t.ex. NPC, kistor, föremål). Dra på vänster sida för rörelse, höger sida för kamera, och på gränssnittet för vanliga vänsterdragar. Ett drag ska inte samtidigt ge ett klick. F12 fungerar som tidigare. För att hoppa medan du springer, välj Show / hide Jump button i menyn.

WoW sparar de tidigare spellplatserna i sina befintliga inställningar. Det tidigare MobileCombat-paketet återställer dess menyer om du installerar det igen med samma appidentitet.

Tactara 0.19.0 ingår som ett separat, oförändrat GPL-addon. Befintlig installation skrivs inte över. Aktivera Tactara i AddOns och välj rotation i dess inställningar. Kör `/tac keydown off` utanför strid för att matcha hjulets klick vid släpp; `/tac hide` döljer Tactaras paneler. I Wolkara öppnar du Mobile UI → Customize, trycker på önskad plats i hjulet och väljer Actions → One Button Rotation, AoE Rotation eller Interrupt. Du kan välja flera platser; inga befintliga spells skrivs över automatiskt. Ett tryck skickar ett manuellt klick via spelets secure action-knapp. Rekommenderat: använd den runda F12-knappen i stället för direktklick i hjulet. Kör `/tac keydown auto`, sedan `/tac bind main` utanför strid och tryck på F12-knappen om den inte redan är bunden till huvudrotationen. Ingen chattöppning ska längre konkurrera med F12. Ingen automatisk repetition. Direktklick och svep i strid måste verifieras på fysisk iPhone.

## Experimentell WoW-harness (Apple Intelligence)

AI ON/OFF på höger sida startar och stoppar en lokal beslutsloop. Bind Tactara till F12 och aktivera Apple Intelligence. Ingen tvåminutersgräns. Manuell touch, tangentbord och F12 pausar och ogiltigförklarar gamla beslut; av/på-knappen och livscykelfel stoppar loopen. F12 och högerklick är kvar.

Graph: ReplayKit → Vision OCR + generell bildklassificering + luminansgrid → specialist-router (strid, navigation, uppdrag, loot, återhämtning, scout) → Apples lokala språkmodell → deterministisk granskare → utförande → nästa observation. Specialistpolicyerna använder en liten lokal kunskapsbas för vanliga WoW-mekanismer. Den använder samma modell för vald roll, inte sex parallella modeller. Bara faktiskt utförda handlingar får återkoppling. Anonymiserad statistik över synlig förändring sparas lokalt och kan användas för att undvika upprepade misslyckade rörelser. Inga modellvikter uppdateras, videor sparas inte och inga observationer skickas till molnet.

Funktionen är ett experiment i en tillåten testmiljö. Vision klassificerar hela bildrutan generellt men är inte tränad på WoW. Ingen fullständig visuell spelmodell, kalibrerade hälsomätare, questdatabas, karta, vägplanering eller tillförlitlig återhämtning ingår ännu. Bildfångst, modellens verkliga beslut och förmågan att spela måste verifieras på fysisk iPhone. Den avstår vid oklarhet och vid vissa riskfyllda menyer. Laya ingår inte. Automatiserat spel på servrar som förbjuder det kan leda till avstängning.


### Återställning & diagnostik

Appen startar alltid i Play-läget. Dra på nedre vänstra delen av spelbilden för att visa den flytande styrspaken. Håll inne tangentbordsknappen och välj Restore floating joystick (Play) om den saknas. UI-läget kan användas för att flytta paneler, men kan stängas av igen. Skärmfångstens behörighetsdialog ska inte längre stoppa en pågående AI-start. AI-knappen visar AI ON… (behörighet), AI VIDEO (bildfångst startad), AI THINK (modell), AI WAIT (inget säkert beslut), AI SLOW (för gammalt beslut), AI NO TEXT (ingen läsbar text), AI NO VID (bildrutor saknas), AI CAP! (skärmfångstfel), AI MODEL! (modellfel), samt faktiskt utförd handling. Tryck på samma knapp för att stoppa. Funktion på riktig telefon måste bekräftas.


### Direkt spelläge (ny standard)

AI-knappen läser nu spelstatus från SPHover-addonet genom dess befintliga bildremsprotokoll: hälsa, valt mål, om målet är attackbart/är en NPC, om målet är dött, strid och om spelaren är monterad. Ingen ReplayKit-dialog för detta läge. Apple-modellen får bara en liten strukturerad spelstatus och kan välja en tillåten handling eller vänta. Om modellen inte är tillgänglig, returnerar fel eller överskrider sex sekunder används regelbaserad styrning (RULE F12/TAB), inte en AI-modell. AI DATA = addondata saknas, AI FRIEND = vänligt/icke attackbart mål, AI REST = låg hälsa/död/monterad, AI THINK = modell, AI F12/TAB = planerad åtgärd. Inaktuella data ger inga handlingar. Detta är en första strids-/målsökningsversion: questlogg, navigering och loot är inte implementerade i direktläget. Tidigare OCR-experiment finns i källkoden men är inte standard. Testa på fysisk iPhone i en tillåten spelmiljö.


### Laya-experiment

Installera device-kit på samma sätt som tidigare; ladda även ner den separata artefakten Slashplayed-Laya-Model. Packa upp och flytta mappen SPModels (med Laya/choices.json och Laya/laya.mlpackage) till Slashplayed under På min iPhone via Apple Devices eller Filer. Ta inte bort spelets befintliga mappar. Första AI-starten kan behöva kompilera modellen; LAYA LOAD visar det. LAYA FILE betyder att modellfilerna saknas. LAYA F12/TAB betyder att beslutet skickades, AI INPUT att det blockerades av aktuellt kontroll-/fokusläge, AI DATA att addondata saknas. RULE är ärligt märkt regelreserv vid fel, inte modellinferens. Core ML kör Laya lokalt på Neural Engine + CPU. Denna version använder förtokeniserade 36 tillstånd för strid/målsökning, inte en full språk- eller questplanner. Apple Foundation Models är inte längre standard för detta experiment. Pixel2Play-konverteringen är ännu inte klar; se PIXEL2PLAY.md. Testa endast där autonomt spel är tillåtet.


### Pixel2Play (experiment, frivilligt tillägg)
Om den separata Pixel2Play-exporten är godkänd kan dess `manifest.json`, `policy.mlpackage` och `decoder.mlpackage` kopieras till `SPModels/Pixel2Play` i Slashplayeds dokumentmapp. Behåll Laya även installerad. Samma AI-knapp startar Laya, och om Pixel2Play-filerna finns laddas modellerna vid målsökning. Pixel2Play läser Metal-bildrutor lokalt, använder fyra rutor och föreslår korta WASD-rörelser. P2P MOVE betyder att en rörelse har skickats, inte att modellen har hittat rätt väg. Utan modellpaket fungerar Laya-läget som tidigare. P2P har inte fullständig kamerakontroll, loot eller uppdragshantering och kan inte påstås vara verifierat på telefonen. Testa bara i en tillåten miljö.


### Felsökning och synligt textfält

På iPhone visas ett redigerbart textfält direkt ovanför tangentbordet. Skriv eller klistra in där, rätta text med iOS vanliga markering och tryck Return för att skicka en rad till spelets chatt. Inklistrade radbrytningar blir mellanslag; text skickas inte automatiskt bara för att den klistras in. AI-inmatning blockeras medan tangentbordet är aktivt.

AI STRIP = ingen färsk avkodad SPHover-bildremsa, AI SYNC = remsan hittas men ett komplett meddelande saknas, AI DATA = komplett meddelande men ingen användbar aktuell spelstatus. SPHover slutför nu överföring av meddelanden innan det byter till nästa; fel i UI-skanningen ska inte hindra en giltig spelstatus från att skickas. Kontrollera spconsole.log samt Lua-fel i spelet vid problem. Fysisk iPhone-verifiering återstår. Endast för tillåten testmiljö.

SPHover på iPhone skickar även en separat, checksummad heartbeat var 0,5 sekund. Den påverkar inte UI-rektanglarna. Om spelstatus saknas eller upphör att förnyas förblir AI-inmatning spärrad. Loggen skiljer mellan mottagen heartbeat och giltig spelstatus.

### Visual preview for protected health
When the public API returns protected health, Wolkara attempts to render the normal native health bar without reading or exporting the value. The AI button switches to VIS LOAD, VIS WARMUP, VIS WAIT, VIS FORWARD/BACK/LEFT/RIGHT, VIS FILE or VIS ERR. This is a local Pixel2Play inference preview, not autonomous movement; protected state never authorizes input. Use the installed SPModels/Pixel2Play package. No screenshots are saved. The model's suggestions remain experimental; actual on-device visual accuracy must be validated separately.

### Visual movement experiment
The AI button now explicitly enables a movement-only Pixel2Play path when health is unavailable, for authorized testing. It uses upstream-style categorical sampling and full-frame resize (area averaging rather than Hamming). MOVE shows a bounded movement pulse was sent, VIS INPUT indicates input was blocked, and VIS WAIT indicates no supported movement was predicted. No combat or clicks are authorized by this path and unknown health is never invented. Manual touch, stale frames, and backgrounding block input. WoW policy quality is not validated. Existing model files unchanged.

### Controller movement diagnostic
AI movement now drives the same GCVirtualController left stick as manual movement, using a 0.55-second pulse and explicit release. Hold the keyboard toggle and select Test AI movement (forward) in Game controls while standing in a clear authorized test area. TEST MOVE means the controller accepted the pulse; TEST INPUT means it was not connected. Test does not depend on the model or health. VIS SLOW means the prediction was too old to use. The decoder skips the four trailing mouse slots, which cannot affect the keyboard prefix. F12 remains available manually and Laya calls Tactara through F12 only with fresh valid hostile target/health state. No new model files required. Actual on-device behavior remains unverified.
