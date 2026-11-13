#!/usr/bin/env python3
"""Polish the pinned Slashplayed 1.5.1 phone HUD after keyboard + mobile patches.

This changes only the generated compatibility shim and adds no automation.
Compiles with the existing iPhone kit CI. Camera and Jump positions are stored
in iOS NSUserDefaults; game content and spell/key bindings are not changed.
"""
from pathlib import Path

event = Path("shims/appkit/spevent.m")
s = event.read_text()
def once(needle: str, replacement: str) -> None:
    global s
    n = s.count(needle)
    if n != 1:
        raise SystemExit(f"expected unique input anchor (found {n}): {needle[:105]!r}")
    s = s.replace(needle, replacement, 1)

if "sp_mobile_frame_for" in s:
    raise SystemExit("Phone HUD polish already applied")

# The original mobile patch mistakenly converted UIKit touch points into
# AppKit before passing them to *UIKit-coordinate* sp_mouse_button/moved_to.
# That error produces wrong camera jumps, especially near the island cutout.
once("sp_mouse_button(1, NO, sp_from_uikit(_previous));",
     "sp_mouse_button(1, NO, _previous);")
once("sp_mouse_button(1, YES, sp_from_uikit(_previous));",
     "sp_mouse_button(1, YES, _previous);")
once("sp_mouse_moved_to(sp_from_uikit(point), SPRightMouseDragged, YES);",
     "sp_mouse_moved_to(point, SPRightMouseDragged, YES);")

helpers = r'''
// Persist normalized positions so orientation/available game rect can change.
// This never edits WoW's own game/character/graphics settings.
static CGRect sp_mobile_frame_for(NSString *key, CGRect game, CGSize size, CGPoint fallback) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:key];
    CGPoint fraction = fallback;
    if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
        [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
        CGFloat x = [saved[0] doubleValue], y = [saved[1] doubleValue];
        if (isfinite(x) && isfinite(y)) fraction = CGPointMake(MAX(0, MIN(1, x)), MAX(0, MIN(1, y)));
    }
    CGFloat cx = CGRectGetMinX(game) + fraction.x * CGRectGetWidth(game);
    CGFloat cy = CGRectGetMinY(game) + fraction.y * CGRectGetHeight(game);
    CGFloat minX = CGRectGetMinX(game) + size.width / 2 + 8;
    CGFloat maxX = CGRectGetMaxX(game) - size.width / 2 - 8;
    CGFloat minY = CGRectGetMinY(game) + size.height / 2 + 8;
    CGFloat maxY = CGRectGetMaxY(game) - size.height / 2 - 8;
    cx = MAX(minX, MIN(MAX(minX, maxX), cx));
    cy = MAX(minY, MIN(MAX(minY, maxY), cy));
    return CGRectMake(cx-size.width/2, cy-size.height/2, size.width, size.height);
}
static void sp_mobile_save_position(UIView *button, NSString *key, CGRect game) {
    if (CGRectGetWidth(game) <= 0 || CGRectGetHeight(game) <= 0) return;
    CGFloat minX = CGRectGetMinX(game) + button.bounds.size.width / 2 + 8;
    CGFloat maxX = CGRectGetMaxX(game) - button.bounds.size.width / 2 - 8;
    CGFloat minY = CGRectGetMinY(game) + button.bounds.size.height / 2 + 8;
    CGFloat maxY = CGRectGetMaxY(game) - button.bounds.size.height / 2 - 8;
    CGFloat cx = MAX(minX, MIN(MAX(minX,maxX), button.center.x));
    CGFloat cy = MAX(minY, MIN(MAX(minY,maxY), button.center.y));
    button.center = CGPointMake(cx, cy);
    [NSUserDefaults.standardUserDefaults setObject:@[@((cx - game.origin.x)/game.size.width),
                                                     @((cy - game.origin.y)/game.size.height)] forKey:key];
}
static CGFloat sp_mobile_look_size(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"sp_mobile_look_size"];
    CGFloat size = [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : 144;
    return (isfinite(size) && size >= 112 && size <= 210) ? size : 144;
}
static CGFloat sp_mobile_look_speed(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"sp_mobile_look_speed"];
    CGFloat speed = [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : 1;
    return (isfinite(speed) && speed >= 0.5 && speed <= 2) ? speed : 1;
}
static UIButton *sp_mobile_hud_button(NSString *title, NSString *accessibility, id owner, SEL selector) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.64];
    b.layer.cornerRadius = 10;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
    b.layer.zPosition = 3000;
    b.accessibilityLabel = accessibility;
    [b addTarget:owner action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}
'''
once("@interface SPMobileCameraPad : UIControl\n@end",
     helpers+"@interface SPMobileCameraPad : UIControl\n"
     "- (void)setEditing:(BOOL)editing;\n@end")
once("    UILabel *_title;\n}\n- (instancetype)initWithFrame:(CGRect)frame {",
     "    UILabel *_title;\n    BOOL _editing;\n}\n"
     "- (void)setEditing:(BOOL)editing {\n"
     "    if (editing) [self stopLooking];\n"
     "    _editing = editing;\n"
     "    self.layer.borderColor = (editing ? UIColor.systemTealColor : UIColor.whiteColor).CGColor;\n"
     "}\n"
     "- (instancetype)initWithFrame:(CGRect)frame {")
once('    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.53];',
     '    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];')
once('    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.53];\n}',
     '    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];\n}')
once('        _finger = t;\n        _previous = [t locationInView:self.superview];\n'
     '        sp_mouse_button(1, YES, _previous);',
     '        _finger = t;\n        _previous = [t locationInView:self.superview];\n'
     '        if (_editing) break; // edit mode drags pad instead of rotating camera\n'
     '        sp_mouse_button(1, YES, _previous);')
once('    CGPoint point = [_finger locationInView:self.superview];\n'
     '    float dx = point.x - _previous.x;\n'
     '    float dy = point.y - _previous.y;\n'
     '    _previous = point;',
     '    CGPoint point = [_finger locationInView:self.superview];\n'
     '    float dx = point.x - _previous.x;\n'
     '    float dy = point.y - _previous.y;\n'
     '    _previous = point;\n'
     '    if (_editing) {\n'
     '        self.center = CGPointMake(self.center.x + dx, self.center.y + dy);\n'
     '        sp_mobile_save_position(self, @"sp_mobile_look_position", sp_game_rect());\n'
     '        return;\n'
     '    }\n'
     '    CGFloat speed = sp_mobile_look_speed();\n'
     '    dx *= speed; dy *= speed;')
# On unlocked pointer position, feed relative scaled motion into the game,
# preserving finger's absolute path for future deltas.
once('        sp_mouse_moved_to(point, SPRightMouseDragged, YES);',
     '        CGPoint p = CGPointMake(sp_pointer.x + dx, sp_pointer.y + dy);\n'
     '        sp_mouse_moved_to(p, SPRightMouseDragged, YES);')
# Native overlay controls, in addition to the existing joystick/LOOK/Jump/keyboard/Esc.
once('    UIButton *_mobileJump;\n',
     '    UIButton *_mobileJump;\n'
     '    UIButton *_mobileEdit;\n'
     '    UIButton *_mobileReset;\n'
     '    UIButton *_mobileResize;\n'
     '    UIButton *_mobileSpeed;\n'
     '    UIPanGestureRecognizer *_mobileJumpPan;\n'
     '    BOOL _mobileEditing;\n'
     '    BOOL _mobileJumpHeld;\n')
once('        [self addSubview:_mobileJump];\n',
r'''        [self addSubview:_mobileJump];
        _mobileJumpPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sp_mobile_drag_jump:)];
        _mobileJumpPan.enabled = NO; // when playing, a tap is always a jump
        [_mobileJump addGestureRecognizer:_mobileJumpPan];

        _mobileEdit = sp_mobile_hud_button(@"Edit", @"Edit or finish phone control layout", self,
                                          @selector(sp_mobile_toggle_edit:));
        [self addSubview:_mobileEdit];
        _mobileReset = sp_mobile_hud_button(@"Reset", @"Reset phone LOOK and Jump positions", self,
                                           @selector(sp_mobile_reset:));
        _mobileReset.hidden = YES;
        [self addSubview:_mobileReset];
        _mobileResize = sp_mobile_hud_button(@"LOOK+", @"Change camera look zone size", self,
                                            @selector(sp_mobile_resize:));
        _mobileResize.hidden = YES;
        [self addSubview:_mobileResize];
        _mobileSpeed = sp_mobile_hud_button(@"1x", @"Adjust camera movement sensitivity", self,
                                           @selector(sp_mobile_speed:));
        _mobileSpeed.hidden = YES;
        [self addSubview:_mobileSpeed];
''')
once('        _mobileCamera.frame = CGRectMake(MAX(CGRectGetMinX(play)+130, right - 99),\n'
     '                                          CGRectGetMidY(play) - 44, 86, 86);\n'
     '        _mobileJump.frame = CGRectMake(MAX(CGRectGetMinX(play)+180, CGRectGetMidX(play)+30),\n'
     '                                        MAX(CGRectGetMinY(play)+100, CGRectGetMaxY(play)-74), 66, 57);',
r'''        // Save positions as fractions of the game area; never overlap the island
        // or place controls outside the screen after rotation.
        CGFloat lookSize = sp_mobile_look_size();
        if (_mobileCamera) _mobileCamera.frame = sp_mobile_frame_for(
            @"sp_mobile_look_position", play, CGSizeMake(lookSize,lookSize), CGPointMake(0.62,0.48));
        _mobileJump.frame = sp_mobile_frame_for(
            @"sp_mobile_jump_position", play, CGSizeMake(72,60), CGPointMake(0.69,0.84));
        CGFloat left = CGRectGetMinX(play);
        _mobileEdit.frame = CGRectMake(left+8, top, 52, 38);
        _mobileReset.frame = CGRectMake(left+66, top, 58, 38);
        _mobileResize.frame = CGRectMake(left+130, top, 68, 38);
        _mobileSpeed.frame = CGRectMake(left+204, top, 52, 38);''')
once('- (void)sp_mobile_jump_down:(UIButton *)button {\n'
     '    sp_mobile_jump(YES);',
     '- (void)sp_mobile_jump_down:(UIButton *)button {\n'
     '    if (_mobileEditing || _mobileJumpHeld) return;\n'
     '    _mobileJumpHeld = YES;\n'
     '    sp_mobile_jump(YES);')
once('- (void)sp_mobile_jump_up:(UIButton *)button {\n'
     '    sp_mobile_jump(NO);',
     '- (void)sp_mobile_jump_up:(UIButton *)button {\n'
     '    if (!_mobileJumpHeld) return;\n'
     '    _mobileJumpHeld = NO;\n'
     '    sp_mobile_jump(NO);')
once('- (void)sp_mobile_jump_down:(UIButton *)button {',
r'''- (void)sp_mobile_toggle_edit:(UIButton *)button {
    _mobileEditing = !_mobileEditing;
    if (_mobileEditing && _mobileJumpHeld) [self sp_mobile_jump_up:_mobileJump];
    [_mobileCamera setEditing:_mobileEditing];
    _mobileJumpPan.enabled = _mobileEditing;
    _mobileReset.hidden = !_mobileEditing;
    _mobileResize.hidden = !_mobileEditing;
    _mobileSpeed.hidden = !_mobileEditing;
    [button setTitle:_mobileEditing ? @"Done" : @"Edit" forState:UIControlStateNormal];
    _mobileJump.layer.borderColor = (_mobileEditing ? UIColor.systemTealColor : UIColor.whiteColor).CGColor;
    [self setNeedsLayout];
}
- (void)sp_mobile_drag_jump:(UIPanGestureRecognizer *)pan {
    if (!_mobileEditing) return;
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [pan translationInView:self];
        UIView *view = pan.view;
        view.center = CGPointMake(view.center.x+delta.x, view.center.y+delta.y);
        [pan setTranslation:CGPointZero inView:self];
        sp_mobile_save_position(view, @"sp_mobile_jump_position", sp_game_rect());
    }
}
- (void)sp_mobile_reset:(UIButton *)button {
    if (!_mobileEditing) return;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    [prefs removeObjectForKey:@"sp_mobile_look_position"];
    [prefs removeObjectForKey:@"sp_mobile_jump_position"];
    [prefs removeObjectForKey:@"sp_mobile_look_size"];
    [prefs removeObjectForKey:@"sp_mobile_look_speed"];
    [_mobileSpeed setTitle:@"1x" forState:UIControlStateNormal];
    [self setNeedsLayout];
}
- (void)sp_mobile_resize:(UIButton *)button {
    if (!_mobileEditing) return;
    CGFloat size = sp_mobile_look_size();
    CGFloat next = size < 153 ? 176 : size < 198 ? 204 : 120;
    [NSUserDefaults.standardUserDefaults setDouble:next forKey:@"sp_mobile_look_size"];
    [self setNeedsLayout];
}
- (void)sp_mobile_speed:(UIButton *)button {
    if (!_mobileEditing) return;
    CGFloat now = sp_mobile_look_speed();
    CGFloat next = now < 0.85 ? 1 : now < 1.15 ? 1.35 : now < 1.55 ? 1.8 : 0.7;
    [NSUserDefaults.standardUserDefaults setDouble:next forKey:@"sp_mobile_look_speed"];
    [button setTitle:[NSString stringWithFormat:@"%.1fx", next] forState:UIControlStateNormal];
}
- (void)sp_mobile_jump_down:(UIButton *)button {''')
# Tests are static guardrails; build CI supplies ObjC compiler checks.
for required in ("sp_mobile_toggle_edit:", "sp_mobile_drag_jump:", "sp_mobile_speed:",
                 "sp_mobile_frame_for(", "sp_mobile_save_position(", "sp_mobile_look_size",
                 "if (_editing) break;", "sp_mouse_button(1, YES, _previous)"):
    if required not in s:
        raise SystemExit(f"generated code lost {required}")
event.write_text(s)
print("Mobile polish: fixed camera coordinate conversion; editable LOOK/Jump, size/speed, saved portrait/landscape layout")
