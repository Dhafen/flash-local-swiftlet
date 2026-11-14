# Slashplayed 1.5.1 med WolkaraForever

Öppna uppdateringen med din befintliga Slashplayed Companion 1.5.1 på Windows.

1. Packa upp den yttre ZIP-filen. Lämna `slashplayed-wolkara-device-kit.zip` som ZIP.
2. Anslut och lås upp din iPhone. Apple Devices ska känna igen den och utvecklarläge ska vara aktiverat.
3. Öppna PowerShell i Companion-mappen. Skriv `./slashplayed-cli.exe --kit ` och dra den inre ZIP-filen till fönstret för att fylla i sökvägen. Tryck Enter.
4. Uppgradera med samma Apple-ID, signeringsteam och bundle-ID, inklusive samma `--bundle-id` om du valde ett eget. Behåll den gamla appen installerad under uppgraderingen.
5. Öppna Slashplayed och starta den befintliga Forever-installationen.

Wolkaras gränssnitt är förvalt på iPhone för Forever och visas på engelska. Du får större gränssnitt, spellhjul, chatt, menyer, karaktärsramar och uppdragskort. Vid första start försöker det fylla hjulen med de befintliga SPTouchBars-platserna eller WoW:s vanliga actionplatser. Slashplayeds UI- och Edit-knappar ligger längst ner till vänster. Jump kan flyttas via Edit.

WoW sparar de tidigare spellplatserna i sina befintliga inställningar. Det tidigare MobileCombat-paketet återställer dess menyer om du installerar det igen med samma appidentitet.

Installera Tactara i Forever och kör `/tac bind` utanför strid. Stäng iOS-tangentbordet och tryck sedan på **Rotation** för att binda F8. Varje knapptryck skickar en F8-tangenttryckning till spelet. Lämna F8 ledig från andra funktioner.
