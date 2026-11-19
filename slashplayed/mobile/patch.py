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
(ROOT / "apps/client/SPLayaRuntime.swift").write_bytes(Path(__file__).with_name("SPLayaRuntime.swift").read_bytes())
(ROOT / "apps/client/SPP2PRuntime.swift").write_bytes(Path(__file__).with_name("SPP2PRuntime.swift").read_bytes())
launcher_build = ROOT / "apps/client/build-launcher.sh"
replace_once(launcher_build, "sppatchscreen.swift -o", "sppatchscreen.swift SPLayaRuntime.swift SPP2PRuntime.swift SPAIGraph.swift spgameai.swift -o")
launcher_main = ROOT / "apps/client/launcher.m"
replace_once(launcher_main, "int main(int argc, char **argv) {",
             "extern void sp_game_ai_register(void);\nint main(int argc, char **argv) {\n    sp_game_ai_register();")
shim_build = ROOT / "shims/generated/build.sh"
replace_once(shim_build, '$CC -fobjc-arc -dynamiclib -O1 -Wno-objc-root-class libspAppKit.m',
             'AI_FRAMEWORKS=""\nif [ "$PLATFORM" = ios ]; then AI_FRAMEWORKS="-framework Vision -framework ReplayKit -framework CoreMedia -framework CoreVideo"; fi\n'
             '$CC $AI_FRAMEWORKS -fobjc-arc -dynamiclib -O1 -Wno-objc-root-class libspAppKit.m')

# Extend the existing pixel-strip message; don't request ReplayKit permission for
# the default AI path. Keep the existing UI rectangle decoder compatible.
hover_lua = ROOT / "addon/SPHover/SPHover.lua"
replace_once(hover_lua, "local function scan()", "-- Read-only, compact game telemetry; appended to the existing SPHover message.\nlocal function spAIState()\n    if not SPPhoneTouchRects then return \"\" end\n    local ok, state = pcall(function()\n        if not UnitExists(\"player\") or UnitHealthMax(\"player\") <= 0 then return \"\" end\n        local flags = 1\n        if UnitIsDeadOrGhost(\"player\") then flags = flags + 2 end\n        if UnitExists(\"target\") then\n            flags = flags + 4\n            if UnitCanAttack(\"player\", \"target\") and not UnitIsPlayer(\"target\") then flags = flags + 8 end\n            if UnitIsDeadOrGhost(\"target\") then flags = flags + 16 end\n        end\n        if UnitAffectingCombat(\"player\") then flags = flags + 32 end\n        if IsMounted and IsMounted() then flags = flags + 64 end\n        local hp = floor(max(0, min(100, 100 * UnitHealth(\"player\") / UnitHealthMax(\"player\"))) + 0.5)\n        local targetHP = 0\n        if UnitExists(\"target\") and UnitHealthMax(\"target\") > 0 then\n            targetHP = floor(max(0, min(100, 100 * UnitHealth(\"target\") / UnitHealthMax(\"target\"))) + 0.5)\n        end\n        return string.char(65, 73, flags, hp, targetHP, floor(GetTime() / 2) % 256)\n    end)\n    return ok and state or \"\"\nend\n\nlocal function scan()")
replace_once(hover_lua, "return string.char(floor(n / 256), n % 256) .. table.concat(out)",
             "return string.char(floor(n / 256), n % 256) .. table.concat(out) .. spAIState()")
strip_header = ROOT / "shims/appkit/sphoverstrip.h"
replace_once(strip_header, "(2 + SPH_MAX_RECTS * 6)", "(2 + SPH_MAX_RECTS * 6 + 6)")
hover_native = ROOT / "shims/appkit/sphover.m"
replace_once(hover_native, "    sp_hover_set_rects(fractions, n);", """    sp_hover_set_rects(fractions, n);
#if !TARGET_OS_VISION
    size_t offset = 2 + (size_t)n * 6;
    size_t bytes = sp_hover_asm.count * SPH_PAYLOAD_BYTES;
    if (getenv("SP_PHONE_UI_RECTS"))
        sp_ai_game_update(sp_hover_asm.data + offset, bytes > offset ? bytes - offset : 0);
#endif""")

# Stage opt-in, low-rate direct Metal game-frame readback for validated P2P packages.
replace_once(hover_native, "static void sp_hover_capture(id<MTLCommandBuffer> cb, id drawable) {",
    Path(__file__).with_name("p2p-capture.m").read_text() + "\nstatic void sp_hover_capture(id<MTLCommandBuffer> cb, id drawable) {")
replace_once(hover_native, "    MTLPixelFormat format = tex.pixelFormat;", """#if !TARGET_OS_VISION
    sp_p2p_capture(cb, tex);
#endif
    MTLPixelFormat format = tex.pixelFormat;""")


# The rectangle list can change faster than all its chunks can be presented.
# On the phone, complete two full cycles before replacing a message. If a UI
# frame scan throws, send the read-only heartbeat with the last usable rects.
replace_once(hover_lua, "local message, seq, chunks, chunkIndex = nil, 0, {}, 0",
    """local message, seq, chunks, chunkIndex = nil, 0, {}, 0
local spSentFrames, spLastRects, spLastScanError = 0, string.char(0, 0), nil""")
replace_once(hover_lua, "    chunkIndex = 0\nend\n\nlocal function showChunk",
    "    chunkIndex = 0\n    spSentFrames = 0\nend\n\nlocal function showChunk")
replace_once(hover_lua, "    if sinceScan >= SCAN_INTERVAL then",
    "    if sinceScan >= SCAN_INTERVAL and (not SPPhoneTouchRects or #chunks <= 1 or spSentFrames >= #chunks * 2) then")
replace_once(hover_lua, "        local ok, msg = pcall(scan)\n        if ok and msg ~= message then",
    """        local ok, msg = pcall(scan)
        if SPPhoneTouchRects then
            if ok and type(msg) == "string" and #msg >= 2 then
                local a, b = msg:byte(1, 2)
                spLastRects = msg:sub(1, 2 + (a * 256 + b) * 6)
                spLastScanError = nil
            elseif not ok then
                if spLastScanError ~= tostring(msg) then
                    spLastScanError = tostring(msg)
                    print("SPHover scan error: " .. spLastScanError)
                end
                msg = spLastRects .. spAIState()
                ok = true
            end
        end
        if ok and msg ~= message then""")
replace_once(hover_lua, "        showChunk(chunks[chunkIndex])",
    "        if #chunks > 0 then\n            showChunk(chunks[chunkIndex])\n            spSentFrames = spSentFrames + 1\n        end")
# Protect the initial frame when no scan has succeeded; never modulo zero.
replace_once(hover_lua, "    if #chunks > 1 or chunkIndex == 0 then",
    "    if #chunks > 0 and (#chunks > 1 or chunkIndex == 0) then")
# Log telemetry failures without printing player/chat information. Leave
# invalid state invalid rather than inventing health or attackability.
replace_once(hover_lua, "    return ok and state or \"\"\nend\n\nlocal function scan()",
    """    if not ok then
        if SPHover and SPHover.lastStateError ~= tostring(state) then
            SPHover.lastStateError = tostring(state)
            print("SPHover telemetry error: " .. tostring(state))
        end
        return ""
    end
    if SPHover then SPHover.lastStateError = nil end
    return state
end

local function scan()""")
replace_once(hover_native, "    sp_hover_misses = 0;\n    sp_hover_crop(YES, height);",
    """    sp_hover_misses = 0;
#if !TARGET_OS_VISION
    if (getenv("SP_PHONE_UI_RECTS"))
        sp_ai_strip_at = NSProcessInfo.processInfo.systemUptime;
#endif
    sp_hover_crop(YES, height);""")
