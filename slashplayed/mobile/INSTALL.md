# Slashplayed 1.5.1 med WolkaraForever

Öppna uppdateringen med din befintliga Slashplayed Companion 1.5.1 på Windows.

1. Packa upp den yttre ZIP-filen. Lämna `slashplayed-wolkara-device-kit.zip` som ZIP.
2. Anslut och lås upp din iPhone. Apple Devices ska känna igen den och utvecklarläge ska vara aktiverat.
3. Öppna PowerShell i Companion-mappen. Skriv `./slashplayed-cli.exe --kit ` och dra den inre ZIP-filen till fönstret för att fylla i sökvägen. Tryck Enter.
4. Uppgradera med samma Apple-ID, signeringsteam och bundle-ID, inklusive samma `--bundle-id` om du valde ett eget. Behåll den gamla appen installerad under uppgraderingen.
5. Öppna Slashplayed och starta den befintliga Forever-installationen.

Wolkaras gränssnitt är förvalt på iPhone för Forever och visas på engelska. Du får större gränssnitt, spellhjul, chatt, menyer, karaktärsramar och uppdragskort. Vid första start försöker det fylla hjulen med de befintliga SPTouchBars-platserna eller WoW:s vanliga actionplatser. Slashplayeds extra knappar (Esc, Jump, UI, Edit, kamerahastighet, Reset och Rotation) är dolda som standard i Forever. Tangentbordet ligger under chatten. Tryck kort för att skriva, eller håll inne tangentbordsknappen för en meny med Escape, Jump, Rotation (F8), byte av touchläge och möjlighet att visa en separat hoppknapp eller återställa alla extra reglage. Den flytande styrspaken och kameradrag fungerar som tidigare. För att hoppa medan du springer, välj Show / hide Jump button i menyn.

WoW sparar de tidigare spellplatserna i sina befintliga inställningar. Det tidigare MobileCombat-paketet återställer dess menyer om du installerar det igen med samma appidentitet.

Tactara 0.19.0 ingår som ett separat, oförändrat GPL-addon. Befintlig installation skrivs inte över. Aktivera Tactara i AddOns och välj rotation i dess inställningar. Kör `/tac keydown off` utanför strid för att matcha hjulets klick vid släpp; `/tac hide` döljer Tactaras paneler. I Wolkara öppnar du Mobile UI → Customize, trycker på önskad plats i hjulet och väljer Actions → One Button Rotation, AoE Rotation eller Interrupt. Du kan välja flera platser; inga befintliga spells skrivs över automatiskt. Ett tryck skickar ett manuellt klick via spelets secure action-knapp. Om klienten blockerar det direkta klicket, finns den tidigare F8-lösningen kvar under tangentbordets långtrycksmeny (`/tac bind`, välj F8 och återställ `/tac keydown on` om det behövs). Ingen automatisk repetition. Direktklick och svep i strid måste verifieras på fysisk iPhone.
