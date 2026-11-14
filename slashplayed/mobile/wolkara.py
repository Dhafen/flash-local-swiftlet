#!/usr/bin/env python3
"""Bundle the original Wolkara HUD and select it on iPhone Forever launches."""
import json
import shutil
from pathlib import Path

root = Path.cwd()
vendor = root / ".wolkara"
addon = root / "addon/WolkaraRoue"
shutil.copytree(vendor / "addons/WolkaraRoue", addon)
shutil.copyfile(Path(__file__).with_name("WolkaraSetup.lua"), addon / "WolkaraSetup.lua")
toc = addon / "WolkaraRoue.toc"
manifest = toc.read_text()
anchor = "\nCore.lua\n"
if manifest.count(anchor) != 1:
    raise SystemExit("Wolkara manifest no longer has its expected entry point")
toc.write_text(manifest.replace(anchor, "\n## OptionalDeps: SPTouchBars\n\nCore.lua\nWolkaraSetup.lua\n", 1))
files = sorted(path.name for path in addon.iterdir() if path.is_file() and path != toc)
files.append(toc.name)

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
    text = file.read_text()
    if text.count(before) != 1:
        raise SystemExit(f"Expected one anchor in {path}: {before[:100]!r}")
    file.write_text(text.replace(before, after, 1))


# Lua 5.1's xpcall does not forward arguments. Keep the same callback
# behavior on both stock Lua 5.1 and clients that accept varargs in xpcall.
replace("addon/WolkaraRoue/Core.lua",
        "    local ok, problem = xpcall(fn, Trace, ...)",
        """    local args, count = { ... }, select("#", ...)
    local ok, problem = xpcall(function() return fn(unpack(args, 1, count)) end, Trace)""")

cdn = "apps/client/spcdn.m"
replace(cdn, "#include <stdatomic.h>", "#include <stdatomic.h>\n#include <stdlib.h>")
replace(cdn, '        [names addObjectsFromArray:@[@"SPTouchBars", @"SPMobileCombat"]];',
        '''        if (getenv("SP_PHONE_UI_RECTS")) [names addObject:@"WolkaraRoue"];
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
            sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70F], 0x6F, NO);
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
      cp -R "$ROOT/addon/WolkaraRoue" "$ROOT/addon/SlashplayedLegacyHUD" "$APP/addons/"
      cp "$ROOT/.wolkara/LICENSE" "$APP/licenses/WolkaraForever-MIT.txt"
      cp "$ROOT/.wolkara/NOTICE.md" "$APP/licenses/WolkaraForever-NOTICE.md"
    fi
    if [ "$p" = xros ]; then''')
print("Staged WolkaraForever's original UI and first-run action import for the iPhone")
