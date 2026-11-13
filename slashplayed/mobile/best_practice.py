#!/usr/bin/env python3
"""Install optional Hekili Forever recommendation addon alongside SPTouchBars.

Run AFTER keyboard/patch.py, mobile/patch.py, mobile/polish.py in the fixed
upstream Slashplayed 1.5.1 checkout. Stage src/Hekili* from the pinned GPLv3
Forever release in addon/ first. This is independent Lua, NOT merged into
the native MIT code: the complete runtime source + licenses ship in the kit.
No automated casting, keypress loops or protected combat manipulation.
"""
from pathlib import Path

root = Path.cwd()
cdn = root / "apps/client/spcdn.m"
kit = root / "scripts/release/device-kit.sh"
vendor = sorted(p.name for p in (root/"addon").glob("Hekili*") if p.is_dir())
expected = {"Hekili", "Hekili_Shared", "Hekili_Warrior", "Hekili_Druid",
            "Hekili_Hunter", "Hekili_Rogue", "Hekili_Mage",
            "Hekili_Paladin", "Hekili_Priest", "Hekili_Shaman", "Hekili_Warlock"}
if not expected.issubset(vendor):
    raise SystemExit(f"Missing expected Hekili Forever source folders: {sorted(expected - set(vendor))}")
if not (root/"addon/Hekili/LICENSE").is_file():
    raise SystemExit("Hekili GPLv3 license missing from full addon source")

def once(path: Path, before: str, after: str):
    s = path.read_text()
    count = s.count(before)
    if count != 1:
        raise SystemExit(f"Expected single anchor in {path}; got {count}: {before[:90]!r}")
    path.write_text(s.replace(before, after, 1))

# sp_addons_place() already copies SPTouchBars only into Forever.
# Copy complete Hekili module trees (not just the .toc/.lua root) on Forever
# launches, preserving all account and character SavedVariables (those live
# elsewhere in WTF). Maintain the full addon source code and 3P licenses.
anchor = '    NSMutableString *text = [NSMutableString stringWithFormat:@"addons: %lu up to date", (unsigned long)same];'
snippet = r'''    if ([game.lastPathComponent isEqualToString:@"_forever_"]) {
        // Hekili Forever is a separate GPLv3 addon with its own sources,
        // licenses, and user settings. Only copy files that differ.
        for (NSString *name in @[@"Hekili", @"Hekili_Shared", @"Hekili_Warrior", @"Hekili_Druid",
                                 @"Hekili_Hunter", @"Hekili_Rogue", @"Hekili_Mage", @"Hekili_Paladin",
                                 @"Hekili_Priest", @"Hekili_Shaman", @"Hekili_Warlock"]) {
            NSString *folder = [addons stringByAppendingPathComponent:name];
            NSDirectoryEnumerator *files = [fm enumeratorAtPath:folder];
            if (!files) {
                [failed addObject:[name stringByAppendingString:@" (no bundled sources)"]];
                continue;
            }
            for (NSString *rel in files) {
                NSString *src = [folder stringByAppendingPathComponent:rel];
                BOOL isDirectory = NO;
                if (![fm fileExistsAtPath:src isDirectory:&isDirectory] || isDirectory) continue;
                NSString *dst = [game stringByAppendingPathComponent:
                                 [@"Interface/AddOns" stringByAppendingPathComponent:
                                  [name stringByAppendingPathComponent:rel]]];
                NSData *bytes = [NSData dataWithContentsOfFile:src];
                if (!bytes) {
                    [failed addObject:[name stringByAppendingFormat:@"/%@ (couldn't read)", rel]];
                    continue;
                }
                if ([[NSData dataWithContentsOfFile:dst] isEqualToData:bytes]) { same++; continue; }
                [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent
                     withIntermediateDirectories:YES attributes:nil error:nil];
                if ([bytes writeToFile:dst atomically:YES])
                    [written addObject:[name stringByAppendingPathComponent:rel]];
                else [failed addObject:[name stringByAppendingFormat:@"/%@ (couldn't write)", rel]];
            }
        }
    }
'''
once(cdn,anchor,snippet+anchor)

needle='    cp "$ROOT/addon/SPTouchBars/SPTouchBars.tga" "$APP/addons/SPTouchBars/"'
replace=needle+'''
    # Independent GPLv3 Hekili Forever recommendation addon: ship its full
    # source distribution including LICENSE and bundled third-party licenses.
    # Do not overwrite character SavedVariables or touch program binaries.
    for a in Hekili Hekili_Shared Hekili_Warrior Hekili_Druid Hekili_Hunter Hekili_Rogue Hekili_Mage Hekili_Paladin Hekili_Priest Hekili_Shaman Hekili_Warlock; do
      cp -R "$ROOT/addon/$a" "$APP/addons/$a"
    done'''
once(kit,needle,replace)

# The distribution uses full source and attribution from the pinned release.
# .toc Version is normally template-substituted by CurseForge packagers.
for path in (root/"addon").glob("Hekili*/*.toc"):
    src=path.read_text()
    if "@project-version@" in src:
        path.write_text(src.replace("@project-version@", "v0.8.1"))
print(f"Added {len(expected)} standalone GPLv3 Hekili Forever addon packages to Forever-only build")
