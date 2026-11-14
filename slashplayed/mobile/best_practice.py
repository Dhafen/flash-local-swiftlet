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
    NSString *stage = [dest stringByAppendingPathComponent:
                        [@".slashplayed-hekili-" stringByAppendingString:NSUUID.UUID.UUIDString]];
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
                ? @[@"SPMobileCombat.toc", @"SPMobileCombat.lua", @"Rotation.lua", @"Menu.lua", @"SPMobileCombat.license"]
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
once(bars,
     'local RETAIL = WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE',
     'local RETAIL = select(4, GetBuildInfo()) ~= 16001 and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE')
once(bars, "local function refresh()\n", '''local function updateCombatHint()
    if not SPMobileCombatHint then return end
    local recommended, oneButton = SPMobileCombatHint()
    local matched = false
    for _, button in ipairs(spells) do
        local visible = button:IsShown() and not editing
        local entry = visible and binding(button)
        local spell = recommended and entry and content(entry)
        local resolved = spell and readable(spell) and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spell)
        local recommend = spell and readable(spell) and (spell == recommended or readable(resolved) and resolved == recommended)
        local one = visible and oneButton and button.index == 1 and entry and entry.kind == "macro"
        button.combatHint:SetShown(recommend and true or false)
        button.oneButtonLabel:SetShown(one and true or false)
        if recommend then matched = true end
    end
    if SPMobileCombatShowHint then SPMobileCombatShowHint(matched, editing) end
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
# Keep the stock action button bindings and the client cooldown widgets.
model = Path(__file__).with_name("SpellCooldowns.lua").read_text().removesuffix("return model\n")
source = (root / bars).read_text()
start = source.index("local function cooldown(button, spell, item)")
end = source.index("local function updateButton(", start)
widgets = Path(__file__).with_name("CooldownWidgets.lua").read_text()
(root / bars).write_text(source[:start] + model + widgets + "\n" + source[end:])
once(bars, 'ipairs({ "cooldown", "chargeCooldown" })',
     'ipairs({ "globalCooldown", "cooldown", "chargeCooldown" })')
once(bars, 'cd:SetHideCountdownNumbers(field == "chargeCooldown")',
     'cd:SetHideCountdownNumbers(field ~= "cooldown")')
once(bars, '    button.chargeCooldown:SetDrawSwipe(false)',
     '    button.globalCooldown:SetSwipeColor(0, 0, 0, 0.30)\n'
     '    button.chargeCooldown:SetDrawSwipe(false)')
once(bars, '    cooldown(button, spell, item)',
     '    button.icon:SetDesaturated(cooldown(button, spell, item, count))')
once(bars, 'if readable(count) and (count == nil or count == 1) then',
     'if readable(count) and (count == nil or (item and count == 1)) then')
# Opt-in phone layout uses existing bindings. The secure handler only reveals
# preassigned buttons, and the existing set switch remains available.
once(bars, "local function defaultUtility(i)", '''local function phoneSpell(i)
    local points = { {0.92, 0.40}, {0.84, 0.51}, {0.94, 0.61}, {0.79, 0.35},
        {0.82, 0.70}, {0.75, 0.62}, {0.69, 0.52}, {0.64, 0.41},
        {0.62, 0.30}, {0.65, 0.19}, {0.72, 0.12}, {0.80, 0.13} }
    return { x = points[i][1], y = points[i][2], size = i == 1 and 70 or 56 }
end

local function defaultUtility(i)''')
once(bars, '    local config = configFor(button)\n    local w, h',
     '''    local config = configFor(button)
    if db.phoneArc and button.kind == "spells" and not editing then config = phoneSpell(button.index) end
    local w, h''')
once(bars, '        if visible then button:Show() else button:Hide() end',
     '''        if self:GetAttribute("phone-arc") and not self:GetAttribute("editing") and i > 4
            and not self:GetAttribute("phone-wheel") then visible = false end
        if visible then button:Show() else button:Hide() end''')
once(bars, '    header:SetAttribute("editpage", editPage)',
     '''    header:SetAttribute("editpage", editPage)
    header:SetAttribute("phone-arc", db.phoneArc == true)
    if SPTouchBarsWheel then SPTouchBarsWheel:SetShown(db.phoneArc == true and not editing) end''')
once(bars, 'i <= (button.kind == "spells" and db.count or db.utilityCount)',
     'i <= (button.kind == "spells" and (db.phoneArc and 12 or db.count) or db.utilityCount)')
once(bars, '    createPanel()\n    createSettings()', '''    local wheel = CreateFrame("Button", "SPTouchBarsWheel", header, "SecureHandlerClickTemplate,UIPanelButtonTemplate")
    wheel:SetSize(74, 48)
    wheel:SetPoint("RIGHT", UIParent, "RIGHT", -9, 125)
    wheel:SetText("Wheel")
    wheel:RegisterForClicks("LeftButtonUp")
    SecureHandlerSetFrameRef(wheel, "header", header)
    wheel:SetAttribute("_onclick", [[
        local header = self:GetFrameRef("header")
        header:SetAttribute("phone-wheel", not header:GetAttribute("phone-wheel"))
        header:RunAttribute("update-page")
    ]])
    createPanel()
    createSettings()''')
once(bars, 'SLASH_SPTOUCHBARS1 = "/sptouch"', '''function SPTouchBarsTogglePhoneArc()
    if not initialized or InCombatLockdown() then return end
    db.phoneArc = not db.phoneArc
    header:SetAttribute("phone-wheel", false)
    apply()
    return db.phoneArc
end

SLASH_SPTOUCHBARS1 = "/sptouch"''')
print(f"Staged {len(modules)} Hekili source modules and the mobile combat UI")
