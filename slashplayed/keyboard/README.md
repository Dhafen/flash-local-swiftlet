# Slashplayed iPhone on-screen keyboard (experimental)

This is an **unverified prototype** built against the upstream **v1.5.1** source (commit 976f9248971238187a82c8c55f69b23054055343). It does not modify Blizzard's WoW client.

## What it attempts
- Adds a small **⌨** button over the iPhone game scene.
- Shows/hides the normal iOS keyboard; autocapitalization is disabled inside the overlay only.
- Adds a separate **Esc** button beside the keyboard toggle for menus/dialogs.
- Converts committed characters, Backspace, Return, and Escape into the existing emulated AppKit NSEvent input queue that receives physical keyboard events.
- Avoids writing text entered from the overlay into the shim input-event diagnostic log.
- Does not change the current installed Slashplayed app until you deliberately re-install with this test kit.

## Status and limitations
- Experimental: **not yet confirmed on a physical iPhone**. Do not promise it works until tested.
- Keyboard appears only on iPhone, not Vision Pro/iPad.
- The keyboard is a manually toggled overlay, not an automatic game-field detector.
- Complex IME/composition, clipboard paste, international characters, UI obstruction, game focus, and modifier combinations need real-device testing.
- The button is placed near the game's upper-right corner and may obscure parts of the game UI.
- If a build or install fails, return to the official 1.5.1 kit. Your files should persist across an in-place app update using the same bundle ID/signing team. Back up valuable data first.

## Build
The GitHub Actions workflow .github/workflows/slashplayed-keyboard.yml checks out pinned upstream v1.5.1, applies patch.py, then builds the unsigned device kit. The uploaded artifact contains slashplayed-keyboard-device-kit.zip.

## Install on Windows (only after successful Actions artifact)
1. Download and extract the official Slashplayed Companion v1.5.1 Windows ZIP from https://github.com/paulstraw/slashplayed/releases/tag/v1.5.1 .
2. Download Slashplayed-iPhone-Keyboard-Kit from the successful Actions run; extract it and place slashplayed-keyboard-device-kit.zip beside slashplayed-cli.exe.
3. Connect and unlock your iPhone. Apple Devices must recognize it; enable Developer Mode.
4. Open PowerShell in the folder with slashplayed-cli.exe and run:

    .\slashplayed-cli.exe --kit .\slashplayed-keyboard-device-kit.zip

5. Use the same Apple ID/team as your existing installation. Don't delete the already-installed Slashplayed first. Never paste Apple or Battle.net credentials into chat or GitHub Actions.
6. Start Slashplayed, select Forever, and look for the keyboard and Esc buttons inside the game. Tap it and test character naming with a non-sensitive test string before using chat.

The upstream companion accepts a custom kit with the explicit --kit option; otherwise it uses the official release's unmodified kit.

The modified device kit is not signed by a trusted distributor and must be signed locally by the companion. This project is unofficial; Blizzard may penalize its use.
