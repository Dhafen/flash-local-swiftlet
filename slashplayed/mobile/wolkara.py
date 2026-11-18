#!/usr/bin/env python3
"""Bundle the original Wolkara HUD and select it on iPhone Forever launches."""
import json
import shutil
from pathlib import Path
from wolkara_english import translate
from wolkara_hud import protect_cooldowns, protect_hud
from wolkara_rotation import actions, picker, turn

root = Path.cwd()
vendor = root / ".wolkara"
addon = root / "addon/WolkaraRoue"
shutil.copytree(vendor / "addons/WolkaraRoue", addon)
for path in addon.glob("*.lua"):
    original = path.read_text(encoding="utf-8")
    adapt = {"Hud.lua": protect_hud, "Actions.lua": protect_cooldowns}
    english = translate(adapt[path.name](original) if path.name in adapt else original)
    rotation = {"Actions.lua": actions, "Picker.lua": picker, "Turn.lua": turn}
    if path.name in rotation:
        english = rotation[path.name](english)
    if path.name == "Chat.lua":
        if english.count('local OPEN_KEY = "F12"') != 1:
            raise ValueError("Unexpected Wolkara chat binding")
        # Reserve F12 for the user's rotation. The keyboard opens chat via F11.
        english = english.replace("F12", "F11")
    if english != original:
        path.write_text(english, encoding="utf-8", newline="\n")
shutil.copyfile(Path(__file__).with_name("WolkaraSetup.lua"), addon / "WolkaraSetup.lua")
toc = addon / "WolkaraRoue.toc"
manifest = toc.read_text()
anchor = "\nCore.lua\n"
if manifest.count(anchor) != 1:
    raise SystemExit("Wolkara manifest no longer has its expected entry point")
toc.write_text(manifest.replace(anchor, "\n## OptionalDeps: SPTouchBars, Tactara\n\nCore.lua\nWolkaraSetup.lua\n", 1))
files = sorted(path.name for path in addon.iterdir() if path.is_file() and path != toc)
files.append(toc.name)

# Ship the upstream addon unchanged and preserve independently installed copies.
tactara = root / ".tactara" / "Tactara"
assert (tactara / "Tactara.toc").is_file()
shutil.copytree(tactara, root / "addon/Tactara")
shutil.copyfile(root / ".tactara/LICENSE", root / "addon/Tactara/LICENSE")

# Keep the old SavedVariables available to the import on upgrade. Both old
# addons must be inert on the phone so they cannot draw a second HUD.
legacy = root / "addon/SlashplayedLegacyHUD"
legacy.mkdir()
for name in ("SPTouchBars", "SPMobileCombat"):
    old_toc = root / f"addon/{name}/{name}.toc"
    metadata = [line for line in old_toc.read_text().splitlines()
                if line.startswith("## ") and not line.startswith(("## Dependencies:", "## OptionalDeps:"))]
    (legacy / old_toc.name).write_text("\n".join(metadata) + "\n")


def replace(path, before, after):
    file = root / path
    text = file.read_text(encoding="utf-8")
    if text.count(before) != 1:
        raise SystemExit(f"Expected one anchor in {path}: {before[:100]!r}")
    file.write_text(text.replace(before, after, 1), encoding="utf-8")


# Lua 5.1's xpcall does not forward arguments. Keep the same callback
# behavior on both stock Lua 5.1 and clients that accept varargs in xpcall.
replace("addon/WolkaraRoue/Core.lua",
        "    local ok, problem = xpcall(fn, Trace, ...)",
        """    local args, count = { ... }, select("#", ...)
    local ok, problem = xpcall(function() return fn(unpack(args, 1, count)) end, Trace)""")

cdn = "apps/client/spcdn.m"
replace(cdn, "#include <stdatomic.h>", "#include <stdatomic.h>\n#include <stdlib.h>")
replace(cdn, "BOOL sp_addons_place(", '''// Install the independent Tactara addon once, never overwrite user files.
static void sp_install_tactara_if_absent(NSFileManager *fm, NSString *source, NSString *dest,
                                         NSMutableArray *written, NSMutableArray *failed) {
    NSString *target = [dest stringByAppendingPathComponent:@"Tactara"];
    if ([fm fileExistsAtPath:target]) return;
    NSString *stage = [dest stringByAppendingPathComponent:
        [@".slashplayed-tactara-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if ([fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil] &&
        [fm copyItemAtPath:[source stringByAppendingPathComponent:@"Tactara"] toPath:stage error:nil] &&
        [fm moveItemAtPath:stage toPath:target error:nil]) {
        [written addObject:@"Tactara"];
    } else {
        [failed addObject:@"Tactara (could not install)"];
        [fm removeItemAtPath:stage error:nil];
    }
}

BOOL sp_addons_place(''')
replace(cdn, '        [names addObjectsFromArray:@[@"SPTouchBars", @"SPMobileCombat"]];',
        '''        if (getenv("SP_PHONE_UI_RECTS")) {
            [names addObject:@"WolkaraRoue"];
            sp_install_tactara_if_absent(fm, addons, [game stringByAppendingPathComponent:@"Interface/AddOns"], written, failed);
        }
        [names addObjectsFromArray:@[@"SPTouchBars", @"SPMobileCombat"]];''')
replace(cdn, '        for (NSString *fileName in [name isEqualToString:@"SPMobileCombat"]',
        '''        for (NSString *fileName in [name isEqualToString:@"WolkaraRoue"]
                ? @[FILES]
                : [name isEqualToString:@"SPMobileCombat"]'''.replace(
                    "FILES", ", ".join("@" + json.dumps(name) for name in files)))
replace(cdn, '            NSData *bytes = [NSData dataWithContentsOfFile:[addons stringByAppendingPathComponent:file]];',
        '''            NSString *source = [addons stringByAppendingPathComponent:file];
            if (getenv("SP_PHONE_UI_RECTS") && [fileName.pathExtension isEqualToString:@"toc"] &&
                ([name isEqualToString:@"SPTouchBars"] || [name isEqualToString:@"SPMobileCombat"])) {
                // Leave the existing controls in place if the replacement HUD failed to copy.
                BOOL ready = YES;
                for (NSString *failure in failed)
                    if ([failure hasPrefix:@"WolkaraRoue/"]) { ready = NO; break; }
                if (ready) source = [[addons stringByAppendingPathComponent:@"SlashplayedLegacyHUD"]
                                     stringByAppendingPathComponent:fileName];
            }
            if ([name isEqualToString:@"WolkaraRoue"] && [fileName.pathExtension isEqualToString:@"toc"]) {
                BOOL ready = YES;
                for (NSString *failure in failed)
                    if ([failure hasPrefix:@"WolkaraRoue/"]) { ready = NO; break; }
                if (!ready) continue;
            }
            NSData *bytes = [NSData dataWithContentsOfFile:source];''')

event = "shims/appkit/spevent.m"
replace(event,
        """    } else {
        [_softField becomeFirstResponder];
        button.backgroundColor""",
        """    } else {
        if (sp_client_window && getenv("SP_PHONE_UI_RECTS"))
            sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70E], 0x67, NO);
        [_softField becomeFirstResponder];
        button.backgroundColor""")

hover = "addon/SPHover/SPHover.lua"
replace(hover, '    if SPMobileCombatHint then', '    if SPPhoneTouchRects then')
replace(hover, '            "SPMobileMenu", "SPMobileCombatPanel", "SPTouchBarsEditor",',
        '''            "WolkaraMobilePicker", "WolkaraMobileSettings", "WolkaraMobileChat",
            "WolkaraMobileQuests",''')

kit = "scripts/release/device-kit.sh"
replace(kit, '    if [ "$p" = xros ]; then',
        '''    if [ "$p" = ios ]; then
      cp -R "$ROOT/addon/WolkaraRoue" "$ROOT/addon/SlashplayedLegacyHUD" "$ROOT/addon/Tactara" "$APP/addons/"
      cp "$ROOT/.wolkara/LICENSE" "$APP/licenses/WolkaraForever-MIT.txt"
      cp "$ROOT/.wolkara/NOTICE.md" "$APP/licenses/WolkaraForever-NOTICE.md"
    fi
    if [ "$p" = xros ]; then''')
print("Staged WolkaraForever's original tap-open UI and saved-layout migration for the iPhone")
