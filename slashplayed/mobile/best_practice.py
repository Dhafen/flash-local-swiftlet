#!/usr/bin/env python3
"""Stage Hekili Forever as independent GPL source and install the phone combat UI."""
import shutil
from pathlib import Path

root = Path.cwd()
vendor = root / ".hekili" / "src"
modules = sorted(path.name for path in vendor.glob("Hekili*") if path.is_dir())
expected = {
    "Hekili", "Hekili_Shared", "Hekili_Warrior", "Hekili_Druid", "Hekili_Hunter",
    "Hekili_Rogue", "Hekili_Mage", "Hekili_Paladin", "Hekili_Priest",
    "Hekili_Shaman", "Hekili_Warlock",
}
if set(modules) != expected:
    raise SystemExit(f"Unexpected Hekili source folders: {modules}")
for name in ("LICENSE", "LICENSE-wowsims.txt", "Libs/CREDITS.md"):
    if not (vendor / "Hekili" / name).is_file():
        raise SystemExit(f"Missing Hekili license notice: {name}")

for name in modules:
    folder = root / "addon" / name
    shutil.copytree(vendor / name, folder)
    for toc in folder.glob("*.toc"):
        toc.write_text(toc.read_text().replace("@project-version@", "v0.8.1"))

shutil.copytree(Path(__file__).parent / "addons/SPMobileCombat", root / "addon/SPMobileCombat")

def once(path: str, before: str, after: str):
    file = root / path
    source = file.read_text()
    if source.count(before) != 1:
        raise SystemExit(f"Expected one anchor in {path}: {before[:100]!r}")
    file.write_text(source.replace(before, after, 1))

cdn = "apps/client/spcdn.m"
module_list = ", ".join(f'@"{name}"' for name in modules)
once(cdn, "BOOL sp_addons_place(", r'''// Keep independently installed Hekili versions and their settings intact.
static void sp_install_hekili_if_absent(NSFileManager *fm, NSString *source, NSString *dest,
                                        NSMutableArray *written, NSMutableArray *failed) {
    NSArray<NSString *> *names = @[MODULES];
    for (NSString *name in names)
        if ([fm fileExistsAtPath:[dest stringByAppendingPathComponent:name]]) return;
    if (![fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil]) {
        [failed addObject:@"Hekili (couldn't create AddOns directory)"];
        return;
    }
    NSString *stage = [dest stringByAppendingPathComponent:@".slashplayed-hekili-stage"];
    if ([fm fileExistsAtPath:stage]) {
        [failed addObject:@"Hekili (previous staging folder exists)"];
        return;
    }
    if (![fm createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:nil]) {
        [failed addObject:@"Hekili (couldn't stage)"];
        return;
    }
    NSMutableArray<NSString *> *installed = [NSMutableArray array];
    BOOL copied = YES;
    for (NSString *name in names) {
        if (![fm copyItemAtPath:[source stringByAppendingPathComponent:name]
                       toPath:[stage stringByAppendingPathComponent:name] error:nil]) {
            copied = NO;
            break;
        }
    }
    if (copied) for (NSString *name in names) {
        if (![fm moveItemAtPath:[stage stringByAppendingPathComponent:name]
                       toPath:[dest stringByAppendingPathComponent:name] error:nil]) break;
        [installed addObject:name];
    }
    if (installed.count == names.count) {
        [written addObject:@"Hekili Forever"];
    } else {
        for (NSString *name in installed) [fm removeItemAtPath:[dest stringByAppendingPathComponent:name] error:nil];
        [failed addObject:@"Hekili (couldn't install all modules)"];
    }
    [fm removeItemAtPath:stage error:nil];
}

BOOL sp_addons_place('''.replace("MODULES", module_list))
once(cdn,
     'if ([game.lastPathComponent isEqualToString:@"_forever_"]) [names addObject:@"SPTouchBars"];',
     '''if ([game.lastPathComponent isEqualToString:@"_forever_"]) {
        [names addObjectsFromArray:@[@"SPTouchBars", @"SPMobileCombat"]];
        sp_install_hekili_if_absent(fm, addons, [game stringByAppendingPathComponent:@"Interface/AddOns"], written, failed);
    }''')
once(cdn,
     '''        for (NSString *ext in [name isEqualToString:@"SPTouchBars"] ? @[@"toc", @"lua", @"tga"]
                              : @[@"toc", @"lua"]) {
            NSString *file = [NSString stringWithFormat:@"%@/%@.%@", name, name, ext];''',
     '''        for (NSString *fileName in [name isEqualToString:@"SPMobileCombat"]
                ? @[@"SPMobileCombat.toc", @"SPMobileCombat.lua", @"Rotation.lua", @"SPMobileCombat.license"]
                : [name isEqualToString:@"SPTouchBars"] ? @[@"SPTouchBars.toc", @"SPTouchBars.lua", @"SPTouchBars.tga"]
                : @[[name stringByAppendingPathExtension:@"toc"], [name stringByAppendingPathExtension:@"lua"]]) {
            NSString *file = [name stringByAppendingPathComponent:fileName];''')

kit = "scripts/release/device-kit.sh"
copy = '    cp "$ROOT/addon/SPTouchBars/SPTouchBars.tga" "$APP/addons/SPTouchBars/"'
once(kit, copy, copy + f'''
    # Independent Hekili distribution, including all license and source files.
    for addon in SPMobileCombat {" ".join(modules)}; do
      cp -R "$ROOT/addon/$addon" "$APP/addons/$addon"
    done''')

# The overlay is purely visual. The secure SPTouchBars bindings and click path stay in the original addon.
bars = "addon/SPTouchBars/SPTouchBars.lua"
once(bars, "local function refresh()\n", '''local function updateCombatHint()
    if not SPMobileCombatHint then return end
    local recommended, oneButton = SPMobileCombatHint()
    local matched = false
    for _, button in ipairs(spells) do
        local visible = button:IsShown() and not editing
        local entry = visible and binding(button)
        local spell = recommended and entry and content(entry)
        local recommend = spell and readable(spell) and spell == recommended
        local one = visible and oneButton and button.index == 1 and entry and entry.kind == "macro"
        button.combatHint:SetShown(recommend and true or false)
        button.oneButtonLabel:SetShown(one and true or false)
        if recommend then matched = true end
    end
    SPMobileCombatShowHint(matched)
end

local function refresh()
''')
once(bars, '''        end
    end
end

local function cursorBinding()''', '''        end
    end
    updateCombatHint()
end

local function cursorBinding()''')
once(bars, '    button.slotLabel:SetPoint("CENTER")', '''    button.slotLabel:SetPoint("CENTER")
    if kind == "spells" then
        button.combatHint = circle(textFrame, "OVERLAY", 2, 0.32, 1, 0.72, 0.85)
        button.combatHint:SetTexture("Interface\\\\AddOns\\\\SPTouchBars\\\\SPTouchBars")
        button.combatHint:SetTexCoord(0.5, 0.75, 0, 1)
        button.combatHint:Hide()
        button.oneButtonLabel = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.oneButtonLabel:SetPoint("TOP", button, "TOP", 0, -5)
        button.oneButtonLabel:SetText("1-Tap")
        button.oneButtonLabel:Hide()
    end''')
print(f"Staged {len(modules)} Hekili source modules and the mobile combat UI")
