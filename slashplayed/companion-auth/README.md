# Windows Companion authentication experiment

Based on pinned upstream Slashplayed v1.6.1. Host only; use the existing custom 1.5.1 device kit explicitly with `--kit`. No game data, app binary, bundle identifier or certificate policy is changed.

Changes:
- Send XML GrandSlam requests as `text/xml`; keep JSON 2FA and TLS verification unchanged. See https://blog.illixion.com/2026/10/sideloading-error-80046/ for the reported October compatibility change; it is not proof that every 401 is fixed.
- Limit connect and HTTP request times. Retry read-only listDevices only on connection/timeouts or HTTP 502/503/504, at most twice, with delay. Never replay password/2FA or certificate mutations.
- Remove raw response bodies from GrandSlam plist parsing errors. The upstream in-memory account/token handling is unchanged.
- No automatic server switching: the user selects a trusted server. No persistent authentication state added.

After a successful build, extract the ZIP, open PowerShell in the new Companion folder, then use:

```powershell
$kit = "$env:USERPROFILE\Downloads\Slashplayed-iPhone-Wolkara-Windows-Companion\slashplayed-wolkara-device-kit.zip"
.\slashplayed-cli.exe --version
.\slashplayed-cli.exe --kit $kit
```

Use the same Apple account, team and previous bundle identifier (pass --bundle-id only if you previously used a custom value). Never uninstall the existing app to update. Do not revoke certificates automatically. The original CLI default Anisette endpoint and --anisette/--server-client-info options remain. The latter disables delivery of the device renewal token, per upstream.
CI tests do not constitute a successful Apple login or physical device test.
