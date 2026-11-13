#!/usr/bin/env python3
"""Apply a phone-first HUD to Slashplayed 1.5.1 AFTER keyboard/patch.py.

Keeps the existing keyboard and installs the floating iPhone HUD. The base stays
upstream Slashplayed 1.5.1: never replace the launcher or downgrade to 1.4.0.
Copies the standalone MIT SPTouchBars addon for Forever from pinned sources.
"""
from pathlib import Path
ROOT = Path.cwd()

def replace_once(path: Path, needle: str, replacement: str) -> None:
    s = path.read_text()
    n = s.count(needle)
    if n != 1:
        raise SystemExit(f"Expected one anchor in {path} (got {n}): {needle[:96]!r}")
    path.write_text(s.replace(needle, replacement, 1))

def require(path: Path, terms: list[str]) -> None:
    s = path.read_text()
    missing = [t for t in terms if t not in s]
    if missing:
        raise SystemExit(f"Missing anchors in {path}: {missing}")

def patch_input():
    path = ROOT / "shims/appkit/spevent.m"
    source = Path(__file__).with_name("phone-input.m").read_text()
    declarations, methods = source.split("// SPInputView methods follow.\n")
    require(path, ["SPSoftKeyboardField", "sp_press_soft_escape:"])
    replace_once(path, "@implementation SPInputView {",
                 declarations + "@implementation SPInputView {")
    replace_once(path, "    UIButton *_softEscape;\n",
                 """    UIButton *_softEscape;
    SPMobileStick *_mobileStick;
    UIButton *_mobileJump, *_mobileEdit, *_mobileUI, *_mobileReset, *_mobileSpeed;
    UIPanGestureRecognizer *_mobileJumpPan;
    UITouch *_mobileLeft, *_mobileRight;
    CGPoint _mobileLeftStart, _mobileRightStart, _mobilePrevious;
    CGRect _mobileGameRect;
    CGFloat _mobileLookSpeed;
    BOOL _mobileMoving, _mobileLookDrag, _mobileLooking, _mobileLookCancelled;
    BOOL _mobileJumpHeld, _mobileEditing, _mobileDirect;
""")
    replace_once(path, "        [self addSubview:_softEscape];",
                 "        [self addSubview:_softEscape];\n        [self sp_mobile_setup];")
    replace_once(path, "        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);",
                 "        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);\n"
                 "        [self sp_mobile_layout:game top:top];")
    replace_once(path, "- (void)sp_toggle_soft_keyboard:(UIButton *)button {",
                 "- (void)sp_toggle_soft_keyboard:(UIButton *)button {\n    [self sp_mobile_cancel];")
    replace_once(path, "    if (self.window) [self becomeFirstResponder];",
                 """    if (self.window) [self becomeFirstResponder];
#if !TARGET_OS_VISION
    else [self sp_mobile_cancel];
#endif""")
    for phase in ("Began", "Moved", "Ended", "Cancelled"):
        replace_once(path, f"- (void)touches{phase}:(NSSet<UITouch *> *)touches",
                     f"- (void)sp_base_touches{phase}:(NSSet<UITouch *> *)touches")
    replace_once(path, "- (void)pressesBegan:(NSSet<UIPress *> *)presses",
                 methods + "- (void)pressesBegan:(NSSet<UIPress *> *)presses")


patch_input()

# Bundled addon files, copied from pinned standalone Touchbars project in CI.
addon = ROOT / "addon/SPTouchBars"
for ext in ("toc", "lua", "tga"):
    if not (addon / f"SPTouchBars.{ext}").is_file():
        raise SystemExit(f"Missing MIT Touchbars source {ext}")
cdn = ROOT / "apps/client/spcdn.m"
replace_once(cdn,
    '    for (NSString *name in hover ? @[@"SPMovie", @"SPHover"] : @[@"SPMovie"])\n'
    '        for (NSString *ext in @[@"toc", @"lua"]) {',
r'''    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"SPMovie"];
    if (hover) [names addObject:@"SPHover"];
    // Touch spell circles use Forever-only secure APIs; never install into
    // Retail/Classic clients, and never overwrite a user's SavedVariables.
    if ([game.lastPathComponent isEqualToString:@"_forever_"]) [names addObject:@"SPTouchBars"];
    for (NSString *name in names)
        for (NSString *ext in [name isEqualToString:@"SPTouchBars"] ? @[@"toc", @"lua", @"tga"]
                              : @[@"toc", @"lua"]) {''')
kit = ROOT / "scripts/release/device-kit.sh"
replace_once(kit,
'    for a in SPMovie SPHover; do\n'
'      mkdir -p "$APP/addons/$a"\n'
'      cp "$ROOT/addon/$a/$a.toc" "$ROOT/addon/$a/$a.lua" "$APP/addons/$a/"\n'
'    done',
'''    for a in SPMovie SPHover SPTouchBars; do
      mkdir -p "$APP/addons/$a"
      cp "$ROOT/addon/$a/$a.toc" "$ROOT/addon/$a/$a.lua" "$APP/addons/$a/"
    done
    cp "$ROOT/addon/SPTouchBars/SPTouchBars.tga" "$APP/addons/SPTouchBars/"
    cp "$ROOT/.mobile-source/LICENSE" "$APP/licenses/SlashplayedEnhanced-MIT.txt"
    cp "$ROOT/.touchbars/LICENSE" "$APP/licenses/Touchbars-MIT.txt"''')
# Do not claim this source changes the install's version; the parent
# checkout is always 1.5.1 and no old launcher from Enhanced is included.
print("Patched 1.5.1: floating iPhone controls, Forever Touchbars, MIT notices")
