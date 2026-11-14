# Slashplayed 1.5.1 med mobilmeny och stridskontroller

Använd ditt befintliga Slashplayed Companion 1.5.1 på Windows. Paketet innehåller det osignerade enhetsbygget och dess SHA-256.

1. Packa upp den yttre GitHub Actions-artefakten. Lämna `slashplayed-mobile-combat-device-kit.zip` som ZIP.
2. Lägg enhetsbygget och `SHA256SUMS.txt` i mappen med `slashplayed-cli.exe`. Kontrollera filen i PowerShell med `Get-FileHash .\slashplayed-mobile-combat-device-kit.zip -Algorithm SHA256` och jämför med `SHA256SUMS.txt`.
3. Anslut och lås upp iPhone. Apple Devices ska känna igen den, och utvecklarläge ska vara aktiverat.
4. Kör `.\slashplayed-cli.exe --kit .\slashplayed-mobile-combat-device-kit.zip`. Välj samma Apple-ID, signeringsteam och bundle-ID som den befintliga installationen. Om du tidigare angav ett eget bundle-ID, lägg till `--bundle-id` med exakt samma värde. **Avinstallera aldrig appen inför uppgraderingen.**
5. Öppna Slashplayed och välj den befintliga Forever-installationen. Öppna WoW:s AddOns-meny vid behov och aktivera SPTouchBars, SP Mobile Combat Modes och Hekili Forever.

## Spela med touch

- Dra med vänster tumme i nedre vänstra spelområdet för att röra dig. Släpp för att stanna. Dra i höger spelområde för att styra kameran. Ett kort tryck skickas som vanligt vänsterklick.
- Tryck och drag i synliga spelpaneler går normalt direkt till panelen. **UI** kan användas om en panel saknar registrerad tryckyta. **Play** återställer tumstyrningen. I **Edit** kan du dra **Jump**, byta kamerakänslighet eller återställa de två inställningarna.
- **⌨** öppnar iOS-tangentbordet, **Esc** stänger menyer och **Menu** öppnar stora genvägar till väskor, karta, uppdrag, karaktär, spells, talanger, grupp, chatt, stridsinställningar och spelinställningar. SPTouchBars **Interact** används för NPC-dialog, queststeg och loot. Välj belöningar manuellt.
- Öppna **Menu → Combat** för lägesval. Den egna cooldownen visas på spellknappen, global cooldown visas med ett diskret svep och antal laddningar visas separat. **Recommended** markerar Hekilis förslag när det finns på en synlig spellcirkel. En fristående ikon visas om ingen cirkel matchar. **Manual** tar bort vägledningen. **Custom** visar första tillgängliga spell i din ordnade lista med spell-ID:n. Tryck **Toggle phone wheel** för fyra fasta platser och en **Wheel**-knapp som visar resten. Samma val återställer din sparade layout. Ändra cirklar och tilldelningar via **Edit spell layout** eller `/sptouch`, utanför strid.
- **One button** markerar spellcirkel 1 när du tilldelat den ett namngivet WoW-makro i den aktiva uppsättningen. Varje tryck går genom SPTouchBars befintliga skyddade makroknapp. Spelklienten avgör vilka makrokommandon som är tillåtna i strid.

## Återställning och verifiering

En återgång till ordinarie Slashplayed 1.5.1 görs med samma Companion och appidentitet, utan att avinstallera. Du kan stänga av Hekili och SP Mobile Combat Modes i WoW:s AddOns-meny. En Hekili-installation som redan finns i spelets AddOns-mapp lämnas orörd. Sparade WoW-inställningar ligger i WTF och ingår inte i paketet.

GitHub Actions verifierar kompilering och ZIP-innehåll. På iPhone återstår en in-place-uppgradering, samtidig joystick och kamera, interaktion/loot, spelltryck och cooldowns, samt test efter bakgrund och återkomst. Jämför bildtid, minne och termiskt läge mellan byggen med samma renderingsinställningar och spelscen. Befintliga Slashplayed-loggar rapporterar FPS, GPU-bildtid, minne och termiskt läge.
