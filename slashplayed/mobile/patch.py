#!/usr/bin/env python3
"""Apply a phone-first HUD to Slashplayed 1.5.1 AFTER keyboard/patch.py.

Copies a pinned, MIT-licensed joystick from Slashplayed Enhanced. The base stays
upstream Slashplayed 1.5.1: never replace the launcher or downgrade to 1.4.0.
Copies the standalone MIT SPTouchBars addon for Forever from pinned sources.
"""
from pathlib import Path
import sys

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

# Only the controller component from the Enhanced fork; its 1.4.0 launcher
# cannot safely replace a known-working 1.5.1 device installation.
joystick = ROOT / "shims/appkit/spjoystick.m"
if not joystick.is_file():
    raise SystemExit("Missing pinned MIT joystick source (from Enhanced fork)")
src = joystick.read_text()
require(joystick, ["atomic_load(&sp_game_presented)", "GCVirtualController", "SPJoystick"])
# Latest upstream uses an actual game NSWindow; don't use Enhanced's
# custom first-frame variable, which does not exist in upstream 1.5.1.
src = src.replace("atomic_load(&sp_game_presented)", "(sp_client_window != nil)")
joystick.write_text(src)

event_path = ROOT / "shims/appkit/spevent.m"
require(event_path, ["SPSoftKeyboardField", "sp_press_soft_escape:", "sp_soft_emit",
                     "    UIButton *_softEscape;", "    CGPoint _scroll_last;"])

mobile_source = r'''
#if !TARGET_OS_VISION
// MIT-licensed SPJoystick comes from Slashplayed Enhanced, pinned in CI.
// Its virtual GCController maps to Forever's native gamepad support.
#include "spjoystick.m"

// A self-contained, two-thumb camera pad. Unlike a tap, a hold + drag
// forwards right mouse movement to WoW. No synthetic cursor tapping and no
// game memory access; only the game's existing NSEvent queue.
@interface SPMobileCameraPad : UIControl
@end
@implementation SPMobileCameraPad {
    UITouch *_finger;
    CGPoint _previous;
    UILabel *_title;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.multipleTouchEnabled = NO;
    self.exclusiveTouch = NO;
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    self.layer.zPosition = 2600;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.53];
    _title = [[UILabel alloc] initWithFrame:self.bounds];
    _title.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _title.text = @"LOOK";
    _title.textAlignment = NSTextAlignmentCenter;
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];
    self.accessibilityLabel = @"Hold and drag to rotate the World of Warcraft camera";
    return self;
}
- (void)stopLooking {
    if (!_finger) return;
    sp_mouse_button(1, NO, sp_from_uikit(_previous));
    _finger = nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.53];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_finger) return;
    for (UITouch *t in touches) {
        if (t.type != UITouchTypeDirect) continue;
        _finger = t;
        _previous = [t locationInView:self.superview];
        sp_mouse_button(1, YES, sp_from_uikit(_previous));
        self.backgroundColor = [UIColor colorWithRed:0.1 green:0.39 blue:0.58 alpha:0.85];
        break;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_finger || ![touches containsObject:_finger]) return;
    CGPoint point = [_finger locationInView:self.superview];
    float dx = point.x - _previous.x;
    float dy = point.y - _previous.y;
    _previous = point;
    if (sp_mouse_frozen) {
        // GameController raw movement expects Y up, while UIKit's Y grows down.
        sp_raw_moved(dx, -dy);
    } else {
        sp_mouse_moved_to(sp_from_uikit(point), SPRightMouseDragged, YES);
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_finger && [touches containsObject:_finger]) [self stopLooking];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_finger && [touches containsObject:_finger]) [self stopLooking];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopLooking];
}
@end

static void sp_mobile_jump(BOOL down) {
    SPEvent *e = sp_event(down ? SPKeyDown : SPKeyUp);
    e->keyCode = 0x31; // kVK_Space
    e->characters = e->charactersIgnoringModifiers = @" ";
    // Avoid diagnostic logging for this overlay; no text is recorded.
    sp_soft_typing = YES;
    sp_post(e);
    sp_soft_typing = NO;
}
#endif

'''
replace_once(event_path, "\n@implementation SPInputView {\n",
             "\n" + mobile_source + "@implementation SPInputView {\n")
replace_once(event_path, '    UIButton *_softEscape;\n',
    '    UIButton *_softEscape;\n'
    '    SPJoystick *_mobileJoystick;\n'
    '    SPMobileCameraPad *_mobileCamera;\n'
    '    UIButton *_mobileJump;\n')
# Append to initializer, after the already working iPhone keyboard/Esc.
replace_once(event_path, '        [self addSubview:_softEscape];\n',
r'''        [self addSubview:_softEscape];

        _mobileJoystick = [[SPJoystick alloc] initWithFrame:CGRectZero];
        [self addSubview:_mobileJoystick];
        _mobileCamera = [[SPMobileCameraPad alloc] initWithFrame:CGRectZero];
        [self addSubview:_mobileCamera];
        _mobileJump = [UIButton buttonWithType:UIButtonTypeSystem];
        [_mobileJump setTitle:@"Jump" forState:UIControlStateNormal];
        _mobileJump.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [_mobileJump setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _mobileJump.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _mobileJump.layer.cornerRadius = 14;
        _mobileJump.layer.borderWidth = 1;
        _mobileJump.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
        _mobileJump.layer.zPosition = 2600;
        _mobileJump.accessibilityLabel = @"Hold to jump or swim up";
        [_mobileJump addTarget:self action:@selector(sp_mobile_jump_down:)
              forControlEvents:UIControlEventTouchDown];
        [_mobileJump addTarget:self action:@selector(sp_mobile_jump_up:)
              forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self addSubview:_mobileJump];
''')
replace_once(event_path,
'        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);',
r'''        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);
        CGRect play = sp_game_rect();
        if (_mobileJoystick) [_mobileJoystick layoutInRect:play];
        _mobileCamera.frame = CGRectMake(MAX(CGRectGetMinX(play)+130, right - 99),
                                          CGRectGetMidY(play) - 44, 86, 86);
        _mobileJump.frame = CGRectMake(MAX(CGRectGetMinX(play)+180, CGRectGetMidX(play)+30),
                                        MAX(CGRectGetMinY(play)+100, CGRectGetMaxY(play)-74), 66, 57);''')
replace_once(event_path, '- (void)sp_press_soft_escape:(UIButton *)button {',
r'''- (void)sp_mobile_jump_down:(UIButton *)button {
    sp_mobile_jump(YES);
    button.backgroundColor = [UIColor colorWithRed:0.1 green:0.39 blue:0.58 alpha:0.85];
}
- (void)sp_mobile_jump_up:(UIButton *)button {
    sp_mobile_jump(NO);
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
}
- (void)sp_press_soft_escape:(UIButton *)button {''')

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
print("Patched 1.5.1: iOS joystick, camera drag, jump, Forever Touchbars, MIT notices")
