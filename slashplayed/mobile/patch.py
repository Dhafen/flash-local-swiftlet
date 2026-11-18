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
    source = source.replace('#include "touch-zone.h"', Path(__file__).with_name("touch-zone.h").read_text())
    source = source.replace('#include "game-ai.m"', Path(__file__).with_name("game-ai.m").read_text())
    declarations, methods = source.split("// SPInputView methods follow.\n")
    require(path, ["SPSoftKeyboardField", "sp_press_soft_escape:"])
    for phase in ("Began", "Moved", "Ended", "Cancelled"):
        replace_once(path, f"- (void)touches{phase}:(NSSet<UITouch *> *)touches",
                     f"- (void)sp_base_touches{phase}:(NSSet<UITouch *> *)touches")
    replace_once(path, "@implementation SPInputView {",
                 declarations + "@implementation SPInputView {")
    replace_once(path, "    UIButton *_softEscape;\n",
                 """    UIButton *_softEscape;
    SPMobileStick *_mobileStick;
    SPMobileJumpButton *_mobileJump;
    UIButton *_mobileEdit, *_mobileUI, *_mobileReset, *_mobileSpeed;
    UIButton *_mobileRotation, *_mobileAIButton;
    SPGameAIController *_mobileAI;
    BOOL _mobileAIKeyHeld;
    unsigned short _mobileAIKeyCode;
    NSUInteger _mobileAIKeyGeneration;
    NSString *_mobileAIKeyText;
    NSTimeInterval _mobileAIManualUntil;
    UIPanGestureRecognizer *_mobileJumpPan, *_mobileRotationPan;
    UITouch *_mobileLeft, *_mobileRight, *_mobileInterface;
    CGPoint _mobileLeftStart, _mobileRightStart, _mobilePrevious, _mobileInterfaceStart;
    NSTimeInterval _mobileLeftAt, _mobileRightAt, _mobileInterfaceAt;
    BOOL _mobileInterfacePending;
    CGRect _mobileGameRect;
    CGFloat _mobileLookSpeed;
    BOOL _mobileMoving, _mobileLookDrag, _mobileLooking, _mobileLookCancelled;
    BOOL _mobileJumpHeld, _mobileEditing, _mobileDirect, _mobileInterfaceDown;
""")
    replace_once(path, "        [self addSubview:_softEscape];",
                 "        [self addSubview:_softEscape];\n        [self sp_mobile_setup];")
    replace_once(path, "        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);",
                 "        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);\n"
                 "        [self sp_mobile_layout:game top:top];")
    replace_once(path, "- (void)sp_toggle_soft_keyboard:(UIButton *)button {",
                 "- (void)sp_toggle_soft_keyboard:(UIButton *)button {\n    [self sp_mobile_cancel];\n    [self setNeedsLayout];")
    replace_once(path, "    if (self.window) [self becomeFirstResponder];",
                 """    if (self.window) [self becomeFirstResponder];
#if !TARGET_OS_VISION
    else { [_mobileAI stop]; [self sp_mobile_cancel]; }
#endif""")
    replace_once(path, "- (void)pressesBegan:(NSSet<UIPress *> *)presses",
                 methods + "- (void)pressesBegan:(NSSet<UIPress *> *)presses")


patch_input()

# Reuse the stock rect transport on Forever/iPhone. Keep hover-only UIKit
# views off the phone; the input router consumes the rects directly.
launcher = ROOT / "apps/client/launcher.m"
replace_once(launcher, "    sp_addons_place([dir", """    BOOL hoverRects = TARGET_OS_VISION;
#if !TARGET_OS_VISION
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        [flavor isEqualToString:@"forever"]) {
        hoverRects = YES;
        setenv("SP_PHONE_UI_RECTS", "1", 1);
    }
#endif
    sp_addons_place([dir""")
replace_once(launcher, "                    TARGET_OS_VISION, &addons);",
             "                    hoverRects, &addons);")
event = ROOT / "shims/appkit/spevent.m"
replace_once(event, "    memcpy(sp_hover_rects, rects, n * sizeof *rects);",
             "    if (n) memcpy(sp_hover_rects, rects, n * sizeof *rects);")
replace_once(event, "    sp_hover_count = n;\n    [sp_hover_layer setNeedsLayout];",
             """    sp_hover_count = n;
#if !TARGET_OS_VISION
    if (getenv("SP_PHONE_UI_RECTS")) return;
#endif
    [sp_hover_layer setNeedsLayout];""")
hover = ROOT / "addon/SPHover/SPHover.lua"
hover.with_name("SPHover.vision.lua").write_bytes(hover.read_bytes())
hover.write_text("SPPhoneTouchRects = true\n" + hover.read_text())
replace_once(hover, "    local f = EnumerateFrames()",
             """    local function addPanel(frame)
        if not frame or isForbidden(frame) or not frame:IsVisible() then return end
        local l, b, r, t = screenRect(frame)
        if not l then return end
        l, b, r, t = max(l, 0), max(b, 0), min(r, sw), min(t, sh)
        if r - l < 4 or t - b < 4 then return end
        local x, y = quantize(l / sw), quantize(b / sh)
        local w, h = quantize((r - l) / sw), quantize((t - b) / sh)
        n = n + 1
        out[n] = string.char(floor(x / 16), x % 16 * 16 + floor(y / 256), y % 256,
                             floor(w / 16), w % 16 * 16 + floor(h / 256), h % 256)
    end
    if SPMobileCombatHint then
        for _, name in ipairs({
            "SPMobileMenu", "SPMobileCombatPanel", "SPTouchBarsEditor",
            "WorldMapFrame", "ContainerFrameCombinedBags", "CharacterFrame",
            "PlayerSpellsFrame", "QuestFrame", "QuestLogFrame", "GossipFrame",
            "LootFrame", "SettingsPanel", "GameMenuFrame", "ItemRefTooltip",
            "CommunitiesFrame", "MerchantFrame", "PVEFrame", "BankFrame",
        }) do pcall(addPanel, _G[name]) end
        for index = 1, 13 do pcall(addPanel, _G["ContainerFrame" .. index]) end
    end
    local f = EnumerateFrames()""")

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
    if [ "$p" = xros ]; then
      cp "$ROOT/addon/SPHover/SPHover.vision.lua" "$APP/addons/SPHover/SPHover.lua"
    fi
    cp "$ROOT/.mobile-source/LICENSE" "$APP/licenses/SlashplayedEnhanced-MIT.txt"
    cp "$ROOT/.touchbars/LICENSE" "$APP/licenses/Touchbars-MIT.txt"''')
# Do not claim this source changes the install's version; the parent
# checkout is always 1.5.1 and no old launcher from Enhanced is included.
print("Patched 1.5.1: floating iPhone controls, Forever Touchbars, MIT notices")

# Build the local-model bridge into the existing Swift host, not a second app.
ai_swift = ROOT / "apps/client/spgameai.swift"
ai_swift.write_bytes(Path(__file__).with_name("spgameai.swift").read_bytes())
(ROOT / "apps/client/SPAIGraph.swift").write_bytes(Path(__file__).with_name("SPAIGraph.swift").read_bytes())
launcher_build = ROOT / "apps/client/build-launcher.sh"
replace_once(launcher_build, "sppatchscreen.swift -o", "sppatchscreen.swift SPAIGraph.swift spgameai.swift -o")
launcher_main = ROOT / "apps/client/launcher.m"
replace_once(launcher_main, "int main(int argc, char **argv) {",
             "extern void sp_game_ai_register(void);\nint main(int argc, char **argv) {\n    sp_game_ai_register();")
shim_build = ROOT / "shims/generated/build.sh"
replace_once(shim_build, '$CC -fobjc-arc -dynamiclib -O1 -Wno-objc-root-class libspAppKit.m',
             'AI_FRAMEWORKS=""\nif [ "$PLATFORM" = ios ]; then AI_FRAMEWORKS="-framework Vision -framework ReplayKit -framework CoreMedia -framework CoreVideo"; fi\n'
             '$CC $AI_FRAMEWORKS -fobjc-arc -dynamiclib -O1 -Wno-objc-root-class libspAppKit.m')
