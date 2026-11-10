# Slashplayed på iPhone via GitHub Actions + Windows 11

Det här är ett **isolerat experiment** i en separat gren, inte en ändring av Flash Local. Bygget använder ursprunglig källkod från [paulstraw/slashplayed](https://github.com/paulstraw/slashplayed) på exakt commit `860d04e88afefc4fe7dbb6a2dba945250e5c2ecf`.

## Vad byggs?

- På GitHubs Xcode 27-runner: `slashplayed-device-kit.zip` (en osignerad app för iPhone utan WoW-spelfiler).
- På GitHubs Windows-runner: `slashplayed-companion.exe` (installationsverktyget för USB och Apple-ID-signering).
- Ett kombinerat `Slashplayed-iPhone-Windows.zip` med installationsinstruktioner.

Inga Apple-, Battle.net- eller andra autentiseringsuppgifter används i CI. Inga Blizzard-filer paketeras i bygget. Detta är ett test av en inofficiell lösning, inte en färdig eller godkänd iOS-app.

## Hämta resultatet

Öppna **Actions → Slashplayed Windows installer for iPhone**, välj en framgångsrik körning och hämta artefakten **Slashplayed-iPhone-Windows**. Testa inte att installera förrän **alla tre jobb är gröna**. GitHub-artifakter går ut efter sju dagar.

## Installera från Windows

1. Installera **Apple Devices** från Microsoft Store på Windows 11-datorn och **LocalDevVPN** från App Store på iPhone.
2. Packa upp `Slashplayed-iPhone-Windows.zip` och anslut upplåst iPhone till Windows-datorn med en datakabel.
3. Öppna PowerShell i mappen där både `slashplayed-companion.exe` och `slashplayed-device-kit.zip` ligger.
4. Kör `./slashplayed-companion.exe devices` för att kontrollera anslutningen.
5. Kör `./slashplayed-companion.exe --kit ./slashplayed-device-kit.zip` och följ anvisningarna. Använd gärna ett separat Apple-konto. Ett gratis konto kräver ny signering var sjunde dag.
6. Starta Slashplayed på telefonen, aktivera LocalDevVPN vid spelstart och installera WoW därifrån med ditt eget abonnemang.

**Risk:** Blizzard godkänner inte denna metod och kan vidta åtgärder mot ditt Battle.net-konto. Windows-programmet kan utlösa SmartScreen eftersom det är osignerat. Läs och kontrollera källkoden och checksumman innan du kör exe-filen.

Källor: [originalets Windows-guide](https://github.com/paulstraw/slashplayed/blob/main/docs/setup-without-a-mac.md) och [projektets README](https://github.com/paulstraw/slashplayed).
