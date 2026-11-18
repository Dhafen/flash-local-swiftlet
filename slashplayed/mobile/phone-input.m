// Included by patch.py in the pinned Slashplayed AppKit shim.
#if !TARGET_OS_VISION
#include "touch-zone.h"
// The virtual left stick uses the GameController path from Slashplayed Enhanced (MIT).
@interface SPMobileStick : UIView
- (void)setOrigin:(CGPoint)origin displacement:(CGPoint)delta;
- (void)stop;
@end

@implementation SPMobileStick {
    UIView *_knob;
    GCVirtualController *_virtualController;
    CGPoint _value;
    BOOL _connected;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.hidden = YES;
    self.layer.zPosition = 2400;
    self.layer.cornerRadius = 38;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.42].CGColor;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.23];
    _knob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
    _knob.layer.cornerRadius = 13;
    _knob.backgroundColor = [UIColor colorWithWhite:1 alpha:0.53];
    [self addSubview:_knob];
    return self;
}

- (void)connectIfNeeded {
    if (_virtualController || !sp_client_window || !self.window ||
        self.window.windowScene.activationState != UISceneActivationStateForegroundActive) return;
    GCVirtualControllerConfiguration *config = [GCVirtualControllerConfiguration new];
    config.elements = [NSSet setWithObject:GCInputLeftThumbstick];
    config.hidden = YES;
    GCVirtualController *controller = [[GCVirtualController alloc] initWithConfiguration:config];
    _virtualController = controller;
    __weak SPMobileStick *weakSelf = self;
    [controller connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPMobileStick *stick = weakSelf;
            if (!stick || stick->_virtualController != controller) {
                [controller disconnect];
                return;
            }
            stick->_connected = !error && controller.controller != nil;
            if (stick->_connected) {
                [controller setPosition:stick->_value forDirectionPadElement:GCInputLeftThumbstick];
            } else {
                [controller disconnect];
                stick->_virtualController = nil;
                sp_stub_log("input: floating left stick could not connect");
            }
        });
    }];
}

- (void)setOrigin:(CGPoint)origin displacement:(CGPoint)delta {
    const CGFloat travel = 30;
    CGFloat length = hypot(delta.x, delta.y);
    CGFloat strength = length > 0 ? MIN(1, MAX(0, (length / travel - 0.12) / 0.88)) / length : 0;
    CGPoint value = CGPointMake(delta.x * strength, -delta.y * strength);
    self.center = origin;
    _knob.center = CGPointMake(38 + value.x * travel, 38 - value.y * travel);
    BOOL changed = !CGPointEqualToPoint(_value, value);
    _value = value;
    self.hidden = NO;
    [self connectIfNeeded];
    if (_connected && changed) [_virtualController setPosition:value forDirectionPadElement:GCInputLeftThumbstick];
}

- (void)stop {
    _value = CGPointZero;
    self.hidden = YES;
    if (_connected) [_virtualController setPosition:CGPointZero forDirectionPadElement:GCInputLeftThumbstick];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) return;
    [self stop];
    [_virtualController disconnect];
    _virtualController = nil;
    _connected = NO;
}
@end

static CGFloat sp_mobile_speed(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"sp_mobile_look_speed"];
    CGFloat speed = [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : 1;
    return isfinite(speed) && speed >= 0.5 && speed <= 2 ? speed : 1;
}

static NSString *sp_mobile_jump_position_key(void) {
    return getenv("SP_PHONE_UI_RECTS") ? @"sp_wolkara_jump_position" : @"sp_mobile_jump_position";
}

static enum SPMobileZone sp_mobile_touch_zone(CGPoint point, CGRect game) {
    if (CGRectIsEmpty(game)) return SPMobileDefault;
    double x = (point.x - game.origin.x) / game.size.width;
    double y = (point.y - game.origin.y) / game.size.height;
    BOOL interface = NO;
    if (getenv("SP_PHONE_UI_RECTS")) {
        for (size_t i = 0; i < sp_hover_count; i++) {
            if (!CGRectContainsPoint(sp_hover_rects[i], CGPointMake(x, 1 - y))) continue;
            interface = YES;
            break;
        }
    }
    enum SPMobileZone zone = sp_mobile_zone(x, y, interface);
    // Route the central/top world too; keep touches outside the game on the stock path.
    if (getenv("SP_PHONE_UI_RECTS") && zone == SPMobileDefault &&
        x >= 0 && x <= 1 && y >= 0 && y <= 1) return SPMobileInterface;
    return zone;
}

// Like the reference phone layout, Jump owns one finger and emits an
// unmodified Space down/up independently of the movement controller.
@interface SPMobileJumpButton : UIButton
@property(nonatomic, copy) void (^onPress)(BOOL);
@property(nonatomic) BOOL configuring;
@end

@implementation SPMobileJumpButton {
    UITouch *_finger;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, self.configuring ? 0 : -8,
                                          self.configuring ? 0 : -8), point);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.configuring || _finger) return;
    for (UITouch *touch in touches) {
        if (!sp_finger(touch)) continue;
        _finger = touch;
        if (self.onPress) self.onPress(YES);
        break;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_finger || ![touches containsObject:_finger]) return;
    _finger = nil;
    if (self.onPress) self.onPress(NO);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
- (BOOL)accessibilityActivate {
    if (self.configuring || !self.onPress) return NO;
    self.onPress(YES);
    self.onPress(NO);
    return YES;
}
@end

static void sp_mobile_send_jump(BOOL down) {
    SPEvent *event = sp_event(down ? SPKeyDown : SPKeyUp);
    event->keyCode = 0x31;
    event->modifierFlags = 0;
    event->characters = event->charactersIgnoringModifiers = @" ";
    BOOL wasTyping = sp_soft_typing;
    sp_soft_typing = YES;
    sp_post(event);
    sp_soft_typing = wasTyping;
    static unsigned messages;
    if (messages++ < 12) sp_stub_log(down ? "input: touch jump Space down" : "input: touch jump Space up");
}

static void sp_mobile_emit_rotation(void) {
    sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70F], 0x6F, NO);
}

static UIButton *sp_mobile_button(NSString *title, NSString *label, id owner, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    button.layer.cornerRadius = 9;
    button.layer.zPosition = 3000;
    button.accessibilityLabel = label;
    if (action) [button addTarget:owner action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
#endif

#if !TARGET_OS_VISION
#include "game-ai.m"
#endif

// SPInputView methods follow.
#if !TARGET_OS_VISION
- (void)sp_mobile_jump:(BOOL)down {
    if (down) [self sp_mobile_ai_release_key];
    if (_mobileJumpHeld == down) return;
    _mobileJumpHeld = down;
    sp_mobile_send_jump(down);
    _mobileJump.highlighted = down;
    _mobileJump.alpha = down ? 0.72 : 1;
}

- (void)sp_mobile_release_look {
    if (!_mobileLooking) return;
    _mobileLooking = NO;
    // Keep the cursor at its last reported position when leaving a locked drag.
    sp_mouse_button(1, NO, sp_pointer);
}

- (void)sp_mobile_cancel {
    if (!_mobileStick) return;
    [self sp_mobile_ai_release_key];
    [_mobileStick stop];
    [self sp_mobile_release_look];
    [self sp_mobile_jump:NO];
    [self sp_mobile_end_interface];
    // Keep the touch identities until UIKit delivers their end/cancel. An
    // interrupted drag must not be reinterpreted as a tap or restart.
    _mobileMoving = _mobileLeft != nil;
    _mobileLookDrag = _mobileRight != nil;
    _mobileLookCancelled = _mobileRight != nil;
}

- (void)sp_mobile_setup {
    _mobileDirect = ![NSUserDefaults.standardUserDefaults boolForKey:@"sp_mobile_ui_mode"];
    _mobileLookSpeed = sp_mobile_speed();
    _mobileStick = [[SPMobileStick alloc] initWithFrame:CGRectMake(0, 0, 76, 76)];
    [self addSubview:_mobileStick];

    _mobileJump = [[SPMobileJumpButton alloc] initWithFrame:CGRectZero];
    [_mobileJump setTitle:@"Jump" forState:UIControlStateNormal];
    [_mobileJump setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _mobileJump.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _mobileJump.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.76];
    _mobileJump.layer.cornerRadius = 12;
    _mobileJump.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    _mobileJump.layer.borderWidth = 1;
    _mobileJump.layer.zPosition = 3000;
    _mobileJump.accessibilityLabel = @"Jump or swim up";
    __weak SPInputView *weakSelf = self;
    _mobileJump.onPress = ^(BOOL down) {
        SPInputView *input = weakSelf;
        if (!input) return;
        if (down && (input->_mobileEditing || input->_softField.isFirstResponder || !sp_client_window)) return;
        [input sp_mobile_jump:down];
    };
    _mobileJumpPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sp_mobile_drag_jump:)];
    _mobileJumpPan.enabled = NO;
    [_mobileJump addGestureRecognizer:_mobileJumpPan];
    _mobileUI = sp_mobile_button(_mobileDirect ? @"UI" : @"Play", @"Toggle touch UI mode for dragging game panels and spells",
                                self, @selector(sp_mobile_toggle_ui:));
    _mobileEdit = sp_mobile_button(@"Edit", @"Edit phone controls", self, @selector(sp_mobile_toggle_edit:));
    _mobileSpeed = sp_mobile_button([NSString stringWithFormat:@"%.2g×", _mobileLookSpeed],
                                    @"Camera sensitivity", self, @selector(sp_mobile_cycle_speed:));
    _mobileReset = sp_mobile_button(@"Reset", @"Reset camera speed and jump position", self, @selector(sp_mobile_reset:));
    _mobileRotation = sp_mobile_button(@"F12", @"Tactara one-button rotation (F12)", self, @selector(sp_mobile_rotation:));
    _mobileRotation.layer.cornerRadius = 22;
    _mobileRotation.layer.borderWidth = 1;
    _mobileRotation.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    _mobileRotation.accessibilityHint = @"Tap to send F12; drag to reposition";
    _mobileRotationPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sp_mobile_drag_rotation:)];
    _mobileRotationPan.minimumNumberOfTouches = _mobileRotationPan.maximumNumberOfTouches = 1;
    _mobileRotationPan.cancelsTouchesInView = YES;
    [_mobileRotation addGestureRecognizer:_mobileRotationPan];
    _mobileRotation.hidden = YES;
    _mobileAI = [SPGameAIController new];
    _mobileAIButton = sp_mobile_button(@"AI OFF", @"Experimental local AI on/off", self, @selector(sp_mobile_ai_toggle:));
    _mobileAIButton.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _mobileAIButton.layer.cornerRadius = 22;
    _mobileAIButton.hidden = YES;
    _mobileAI.releaseInput = ^{
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_ai_release_key];
    };
    _mobileAI.action = ^(NSString *action, CGPoint point) {
        SPInputView *input = weakSelf;
        if (!input || !input->_mobileAI.active || !sp_client_window || input->_softField.isFirstResponder ||
            !input.window || input.window.windowScene.activationState != UISceneActivationStateForegroundActive ||
            input->_mobileEditing || input->_mobileLeft || input->_mobileRight || input->_mobileInterface ||
            input->_touches.count || sp_mouse_buttons || !input->_mobileDirect ||
            NSProcessInfo.processInfo.systemUptime < input->_mobileAIManualUntil) return;
        if ([action isEqualToString:@"ATTACK"]) sp_mobile_emit_rotation();
        else if ([action isEqualToString:@"TARGET"]) sp_soft_emit(@"\t", 0x30, NO);
        else if ([action isEqualToString:@"FORWARD"]) [input sp_mobile_ai_hold_key:0x0D text:@"w"];
        else if ([action isEqualToString:@"BACK"]) [input sp_mobile_ai_hold_key:0x01 text:@"s"];
        else if ([action isEqualToString:@"LEFT"]) [input sp_mobile_ai_hold_key:0x00 text:@"a"];
        else if ([action isEqualToString:@"RIGHT"]) [input sp_mobile_ai_hold_key:0x02 text:@"d"];
        else if ([action isEqualToString:@"INTERACT"] || [action isEqualToString:@"CLICK"]) {
            CGRect bounds = input.window.bounds;
            CGPoint screen = CGPointMake(CGRectGetMinX(bounds) + point.x * bounds.size.width,
                                          CGRectGetMinY(bounds) + point.y * bounds.size.height);
            CGPoint local = [input convertPoint:screen fromView:input.window];
            if (!CGRectContainsPoint(input->_mobileGameRect, local) ||
                CGRectContainsPoint(input->_mobileAIButton.frame, local) ||
                CGRectContainsPoint(input->_mobileRotation.frame, local) ||
                CGRectContainsPoint(input->_softToggle.frame, local)) return;
            CGPoint position = sp_from_uikit(local);
            NSInteger button = [action isEqualToString:@"INTERACT"] ? 1 : 0;
            sp_mouse_button(button, YES, position);
            sp_mouse_button(button, NO, position);
        }
    };
    _mobileAI.status = ^(NSString *status) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input->_mobileAIButton setTitle:status forState:UIControlStateNormal];
        input->_mobileAIButton.backgroundColor = [status isEqualToString:@"AI ON"]
            ? [UIColor colorWithRed:0.65 green:0.15 blue:0.15 alpha:0.85] : [UIColor colorWithWhite:0 alpha:0.55];
        if ([status isEqualToString:@"AI!"]) input->_mobileAIButton.accessibilityHint =
            @"Model or screen capture unavailable. Check Apple Intelligence and try again.";
    };
    _mobileReset.hidden = _mobileSpeed.hidden = YES;
    for (UIButton *button in @[_mobileJump, _mobileUI, _mobileEdit, _mobileSpeed, _mobileReset, _mobileRotation, _mobileAIButton]) {
        button.exclusiveTouch = NO;
        [self addSubview:button];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sp_mobile_deactivate:)
                                                name:UISceneWillDeactivateNotification object:nil];
}

- (void)sp_mobile_deactivate:(NSNotification *)notification {
    if (notification.object == self.window.windowScene) {
        [_mobileAI stop];
        [self sp_mobile_cancel];
    }
}

// Keep Wolkara's in-game HUD unobstructed. The native keyboard remains the
// and the small F12 control are the only permanent overlays.
- (UIMenu *)sp_mobile_compact_menu {
    __weak SPInputView *weakSelf = self;
    UIAction *escape = [UIAction actionWithTitle:@"Escape" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (input) [input sp_press_soft_escape:nil];
    }];
    UIAction *jump = [UIAction actionWithTitle:@"Jump" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input || !sp_client_window || input->_softField.isFirstResponder) return;
        [input sp_mobile_jump:YES];
        [input sp_mobile_jump:NO];
    }];
    UIAction *showJump = [UIAction actionWithTitle:@"Show / hide Jump button" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_jump:NO];
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        [prefs setBool:![prefs boolForKey:@"sp_wolkara_show_jump"] forKey:@"sp_wolkara_show_jump"];
        [input setNeedsLayout];
    }];
    UIAction *rotation = [UIAction actionWithTitle:@"Rotation (F12)" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_rotation:nil];
    }];
    UIAction *showRotation = [UIAction actionWithTitle:@"Show / hide F12 button" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        [prefs setBool:![prefs boolForKey:@"sp_wolkara_hide_rotation"] forKey:@"sp_wolkara_hide_rotation"];
        [input setNeedsLayout];
    }];
    UIAction *resetRotation = [UIAction actionWithTitle:@"Reset F12 position" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"sp_wolkara_rotation_position"];
        SPInputView *input = weakSelf;
        [input setNeedsLayout];
    }];
    UIAction *mode = [UIAction actionWithTitle:@"Toggle play / UI touch mode" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_toggle_ui:input->_mobileUI];
    }];
    UIAction *legacy = [UIAction actionWithTitle:@"Show / hide extra controls" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_cancel];
        if (input->_mobileEditing) [input sp_mobile_toggle_edit:input->_mobileEdit];
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        [prefs setBool:![prefs boolForKey:@"sp_wolkara_extra_controls"] forKey:@"sp_wolkara_extra_controls"];
        [input setNeedsLayout];
    }];
    return [UIMenu menuWithTitle:@"Game controls" children:@[escape, jump, showJump, rotation, showRotation, resetRotation, mode, legacy]];
}

- (void)sp_mobile_layout:(CGRect)game top:(CGFloat)top {
    if (!CGRectEqualToRect(game, _mobileGameRect)) {
        [self sp_mobile_cancel];
        _mobileGameRect = game;
    }
    CGFloat left = CGRectGetMinX(game) + MAX(8, self.safeAreaInsets.left - CGRectGetMinX(game));
    BOOL wolkaraHUD = getenv("SP_PHONE_UI_RECTS") != NULL;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    BOOL compact = wolkaraHUD && ![prefs boolForKey:@"sp_wolkara_extra_controls"];
    _softEscape.hidden = compact;
    _mobileUI.hidden = _mobileEdit.hidden = compact;
    _mobileSpeed.hidden = _mobileReset.hidden = compact || !_mobileEditing;
    _mobileJump.hidden = compact && ![prefs boolForKey:@"sp_wolkara_show_jump"];
    if (wolkaraHUD) {
        if (!_softToggle.menu) {
            _softToggle.menu = [self sp_mobile_compact_menu];
            _softToggle.showsMenuAsPrimaryAction = NO;
            _softToggle.accessibilityHint = @"Hold for game controls";
        }
        if (!_softField.isFirstResponder && !CGRectIsEmpty(game)) {
            // Center below Wolkara's chat, rather than over the spell wheels.
            CGFloat bottom = MAX(8, self.safeAreaInsets.bottom);
            _softToggle.frame = CGRectMake(CGRectGetMidX(game) - 22,
                CGRectGetMaxY(game) - bottom - 34, 44, 34);
        }
    } else {
        _softToggle.menu = nil;
        _softToggle.accessibilityHint = nil;
    }
    CGFloat controlsY = wolkaraHUD ? CGRectGetMaxY(game) - MAX(8, self.safeAreaInsets.bottom) - 44 : top;
    _mobileUI.frame = CGRectMake(left, controlsY, 46, 44);
    _mobileEdit.frame = CGRectMake(left + 50, controlsY, 50, 44);
    _mobileSpeed.frame = CGRectMake(left + 104, controlsY, 49, 44);
    _mobileReset.frame = CGRectMake(left + 157, controlsY, 53, 44);
    _mobileRotation.hidden = !wolkaraHUD || CGRectIsEmpty(game) || _softField.isFirstResponder ||
        [prefs boolForKey:@"sp_wolkara_hide_rotation"];
    _mobileAIButton.hidden = !wolkaraHUD || CGRectIsEmpty(game) || _softField.isFirstResponder;
    _mobileAIButton.bounds = CGRectMake(0, 0, 44, 44);
    _mobileAIButton.center = [self sp_mobile_clamp_rotation:CGPointMake(
        game.origin.x + 0.88 * game.size.width, game.origin.y + 0.28 * game.size.height)];
    _mobileRotation.bounds = CGRectMake(0, 0, 44, 44);
    if (_mobileRotationPan.state != UIGestureRecognizerStateBegan &&
        _mobileRotationPan.state != UIGestureRecognizerStateChanged) {
        CGPoint fraction = CGPointMake(0.88, 0.72);
        id savedRotation = [prefs objectForKey:@"sp_wolkara_rotation_position"];
        if ([savedRotation isKindOfClass:NSArray.class] && [savedRotation count] == 2 &&
            [savedRotation[0] isKindOfClass:NSNumber.class] && [savedRotation[1] isKindOfClass:NSNumber.class]) {
            CGFloat x = [savedRotation[0] doubleValue], y = [savedRotation[1] doubleValue];
            if (isfinite(x) && isfinite(y)) fraction = CGPointMake(x, y);
        }
        _mobileRotation.center = [self sp_mobile_clamp_rotation:CGPointMake(
            game.origin.x + fraction.x * game.size.width, game.origin.y + fraction.y * game.size.height)];
    }
    _mobileJump.bounds = CGRectMake(0, 0, 66, 50);
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:sp_mobile_jump_position_key()];
    CGPoint fraction = wolkaraHUD ? CGPointMake(0.74, 0.46) : CGPointMake(0.92, 0.53);
    if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
        [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
        CGFloat x = [saved[0] doubleValue], y = [saved[1] doubleValue];
        if (isfinite(x) && isfinite(y)) fraction = CGPointMake(x, y);
    }
    _mobileJump.center = [self sp_mobile_clamp_jump:CGPointMake(game.origin.x + fraction.x * game.size.width,
                                                               game.origin.y + fraction.y * game.size.height)];
}

- (CGPoint)sp_mobile_clamp_jump:(CGPoint)point {
    CGRect inner = CGRectInset(_mobileGameRect, 42, 34);
    if (CGRectIsEmpty(inner)) return CGPointMake(CGRectGetMidX(_mobileGameRect), CGRectGetMidY(_mobileGameRect));
    return CGPointMake(MAX(CGRectGetMinX(inner), MIN(CGRectGetMaxX(inner), point.x)),
                       MAX(CGRectGetMinY(inner), MIN(CGRectGetMaxY(inner), point.y)));
}

- (void)sp_mobile_drag_jump:(UIPanGestureRecognizer *)pan {
    if (!_mobileEditing || CGRectIsEmpty(_mobileGameRect)) return;
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged ||
        pan.state == UIGestureRecognizerStateEnded) {
        CGPoint delta = [pan translationInView:self];
        CGPoint center = _mobileJump.center;
        _mobileJump.center = [self sp_mobile_clamp_jump:CGPointMake(center.x + delta.x, center.y + delta.y)];
        [pan setTranslation:CGPointZero inView:self];
    }
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint point = _mobileJump.center;
        CGRect rect = _mobileGameRect;
        [NSUserDefaults.standardUserDefaults setObject:@[@((point.x - rect.origin.x) / rect.size.width),
                                                         @((point.y - rect.origin.y) / rect.size.height)]
                                              forKey:sp_mobile_jump_position_key()];
    } else if (pan.state == UIGestureRecognizerStateCancelled) {
        [self setNeedsLayout];
    }
}

- (void)sp_mobile_toggle_edit:(UIButton *)button {
    [self sp_mobile_cancel];
    _mobileEditing = !_mobileEditing;
    _mobileJump.configuring = _mobileEditing;
    _mobileJumpPan.enabled = _mobileEditing;
    _mobileReset.hidden = _mobileSpeed.hidden = !_mobileEditing;
    [self setNeedsLayout];
    [button setTitle:_mobileEditing ? @"Done" : @"Edit" forState:UIControlStateNormal];
}

- (CGPoint)sp_mobile_clamp_rotation:(CGPoint)point {
    CGRect safe = CGRectIntersection(_mobileGameRect, UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets));
    CGRect inner = CGRectInset(safe, 24, 24);
    if (CGRectIsEmpty(inner)) return CGPointMake(CGRectGetMidX(_mobileGameRect), CGRectGetMidY(_mobileGameRect));
    return CGPointMake(MAX(CGRectGetMinX(inner), MIN(CGRectGetMaxX(inner), point.x)),
                       MAX(CGRectGetMinY(inner), MIN(CGRectGetMaxY(inner), point.y)));
}

- (void)sp_mobile_drag_rotation:(UIPanGestureRecognizer *)pan {
    if (CGRectIsEmpty(_mobileGameRect)) return;
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged ||
        pan.state == UIGestureRecognizerStateEnded) {
        CGPoint delta = [pan translationInView:self], center = _mobileRotation.center;
        _mobileRotation.center = [self sp_mobile_clamp_rotation:CGPointMake(center.x + delta.x, center.y + delta.y)];
        [pan setTranslation:CGPointZero inView:self];
    }
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint p = _mobileRotation.center;
        CGRect rect = _mobileGameRect;
        [NSUserDefaults.standardUserDefaults setObject:@[@((p.x - rect.origin.x) / rect.size.width),
                                                         @((p.y - rect.origin.y) / rect.size.height)]
                                              forKey:@"sp_wolkara_rotation_position"];
    } else if (pan.state == UIGestureRecognizerStateCancelled) {
        [self setNeedsLayout];
    }
}

- (void)sp_mobile_ai_release_key {
    if (!_mobileAIKeyHeld) return;
    _mobileAIKeyHeld = NO;
    ++_mobileAIKeyGeneration;
    SPEvent *event = sp_event(SPKeyUp);
    event->keyCode = _mobileAIKeyCode;
    event->modifierFlags = 0;
    event->characters = event->charactersIgnoringModifiers = _mobileAIKeyText;
    BOOL wasTyping = sp_soft_typing;
    sp_soft_typing = YES;
    sp_post(event);
    sp_soft_typing = wasTyping;
}
- (void)sp_mobile_ai_hold_key:(unsigned short)code text:(NSString *)text {
    [self sp_mobile_ai_release_key];
    if (!_mobileAI.active) return;
    _mobileAIKeyHeld = YES;
    _mobileAIKeyCode = code;
    _mobileAIKeyText = text;
    NSUInteger generation = ++_mobileAIKeyGeneration;
    SPEvent *event = sp_event(SPKeyDown);
    event->keyCode = code;
    event->modifierFlags = 0;
    event->characters = event->charactersIgnoringModifiers = text;
    BOOL wasTyping = sp_soft_typing;
    sp_soft_typing = YES;
    sp_post(event);
    sp_soft_typing = wasTyping;
    __weak SPInputView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPInputView *input = weakSelf;
        if (input && input->_mobileAIKeyGeneration == generation) [input sp_mobile_ai_release_key];
    });
}
- (void)sp_mobile_ai_toggle:(UIButton *)button {
    if (_mobileAI.active) { [_mobileAI stop]; return; }
    if (!sp_client_window || _softField.isFirstResponder || _mobileEditing ||
        _mobileLeft || _mobileRight || _mobileInterface || _touches.count || sp_mouse_buttons) return;
    [_mobileAI start];
}

- (void)sp_mobile_rotation:(UIButton *)button {
    [self sp_mobile_ai_release_key];
    _mobileAIManualUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    if (!sp_client_window || _softField.isFirstResponder || _mobileEditing ||
        _mobileRotationPan.state == UIGestureRecognizerStateBegan ||
        _mobileRotationPan.state == UIGestureRecognizerStateChanged) return;
    // One physical tap sends one ordinary F12 down/up. Drag cancels the tap.
    sp_mobile_emit_rotation();
}

- (void)sp_mobile_toggle_ui:(UIButton *)button {
    [self sp_mobile_cancel];
    _mobileDirect = !_mobileDirect;
    [NSUserDefaults.standardUserDefaults setBool:!_mobileDirect forKey:@"sp_mobile_ui_mode"];
    [button setTitle:_mobileDirect ? @"UI" : @"Play" forState:UIControlStateNormal];
}

- (void)sp_mobile_cycle_speed:(UIButton *)button {
    _mobileLookSpeed = _mobileLookSpeed < 0.85 ? 1 : _mobileLookSpeed < 1.15 ? 1.35 : _mobileLookSpeed < 1.55 ? 1.8 : 0.7;
    [NSUserDefaults.standardUserDefaults setDouble:_mobileLookSpeed forKey:@"sp_mobile_look_speed"];
    [button setTitle:[NSString stringWithFormat:@"%.2g×", _mobileLookSpeed] forState:UIControlStateNormal];
}

- (void)sp_mobile_reset:(UIButton *)button {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    [prefs removeObjectForKey:sp_mobile_jump_position_key()];
    [prefs removeObjectForKey:@"sp_mobile_look_speed"];
    _mobileLookSpeed = 1;
    [_mobileSpeed setTitle:@"1×" forState:UIControlStateNormal];
    [self setNeedsLayout];
}

- (void)sp_mobile_move_look:(CGPoint)point {
    if (!_mobileLooking) {
        // Don't turn a pending panel/world tap into a simultaneous camera drag.
        if (_mobileInterface || _touches.count || sp_mouse_buttons) {
            if (hypot(point.x - _mobileRightStart.x, point.y - _mobileRightStart.y) >= SP_MOBILE_DRAG_DISTANCE)
                _mobileLookCancelled = YES;
            return;
        }
        CGPoint origin = _mobileLookDrag ? point : _mobileRightStart;
        if (!_mobileLookDrag && hypot(point.x - origin.x, point.y - origin.y) < SP_MOBILE_DRAG_DISTANCE) return;
        _mobileLookDrag = _mobileLooking = YES;
        _mobilePrevious = origin;
        sp_mouse_button(1, YES, sp_from_uikit(origin));
    }
    CGFloat dx = (point.x - _mobilePrevious.x) * _mobileLookSpeed;
    CGFloat dy = (point.y - _mobilePrevious.y) * _mobileLookSpeed;
    _mobilePrevious = point;
    if (!dx && !dy) return;
    if (sp_mouse_frozen) {
        sp_post_motion(SPRightMouseDragged, dx, dy);
    } else {
        sp_mouse_moved_to(CGPointMake(sp_pointer.x + dx, sp_pointer.y - dy), SPRightMouseDragged, NO);
    }
}

- (NSSet<UITouch *> *)sp_mobile_base_touches:(NSSet<UITouch *> *)touches {
    if ((!_mobileInterface || ![touches containsObject:_mobileInterface]) &&
        (!_mobileLeft || ![touches containsObject:_mobileLeft]) &&
        (!_mobileRight || ![touches containsObject:_mobileRight])) return touches;
    NSMutableSet<UITouch *> *base = [touches mutableCopy];
    if (_mobileLeft) [base removeObject:_mobileLeft];
    if (_mobileRight) [base removeObject:_mobileRight];
    if (_mobileInterface) [base removeObject:_mobileInterface];
    return base;
}

- (void)sp_mobile_end_interface {
    _mobileInterfacePending = NO;
    if (!_mobileInterfaceDown) return;
    _mobileInterfaceDown = NO;
    sp_mouse_button(0, NO, sp_pointer);
}

- (void)sp_mobile_tap:(CGPoint)start finish:(CGPoint)end elapsed:(NSTimeInterval)elapsed {
    // The ordinary left click and right click each send exactly one down/up
    // pair. Do not release another finger's camera drag or click through it.
    if (_touches.count || sp_mouse_buttons || !sp_client_window || _softField.isFirstResponder) return;
    enum SPMobileClick click = sp_mobile_click(getenv("SP_PHONE_UI_RECTS") ? elapsed : 0,
                                               hypot(end.x - start.x, end.y - start.y), NO);
    if (click == SPMobileNoClick) return;
    CGPoint position = sp_from_uikit(start);
    sp_mouse_button(click, YES, position);
    sp_mouse_button(click, NO, position);
}
#endif

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    [self sp_mobile_ai_release_key];
    _mobileAIManualUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    if (_mobileDirect && !_mobileEditing && !_softField.isFirstResponder && sp_client_window &&
        !_touches.count && (sp_mouse_buttons == 0 || (_mobileLooking && sp_mouse_buttons == 2))) {
        for (UITouch *touch in touches) {
            if (!sp_finger(touch)) continue;
            CGPoint point = [touch locationInView:self];
            enum SPMobileZone zone = sp_mobile_touch_zone(point, sp_game_rect());
            if (zone == SPMobileInterface && !_mobileInterface) {
                [self sp_mobile_release_look];
                _mobileInterface = touch;
                _mobileInterfaceStart = point;
                _mobileInterfaceAt = touch.timestamp;
                _mobileInterfacePending = getenv("SP_PHONE_UI_RECTS") != NULL;
                // The phone delays stationary UI/world presses until the
                // gesture is classified. A drag still sends left down at its origin.
                _mobileInterfaceDown = !_mobileInterfacePending;
                if (_mobileInterfaceDown) sp_mouse_button(0, YES, sp_from_uikit(point));
            } else if (zone == SPMobileMove && !_mobileLeft) {
                _mobileLeft = touch;
                _mobileLeftStart = point;
                _mobileLeftAt = touch.timestamp;
                _mobileMoving = NO;
            } else if (zone == SPMobileLook && !_mobileRight) {
                _mobileRight = touch;
                _mobileRightStart = point;
                _mobileRightAt = touch.timestamp;
                _mobileLookDrag = _mobileLookCancelled = NO;
            }
        }
    }
    touches = [self sp_mobile_base_touches:touches];
    if (!touches.count || _mobileInterface) return;
    [self sp_mobile_release_look];
#endif
    [self sp_base_touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    if (_mobileLeft && [touches containsObject:_mobileLeft]) {
        CGPoint point = [_mobileLeft locationInView:self];
        CGPoint delta = CGPointMake(point.x - _mobileLeftStart.x, point.y - _mobileLeftStart.y);
        if (!_mobileMoving && hypot(delta.x, delta.y) >= SP_MOBILE_DRAG_DISTANCE) {
            _mobileMoving = YES;
            [_mobileStick setOrigin:_mobileLeftStart displacement:delta];
        } else if (_mobileMoving && !_mobileStick.hidden) {
            [_mobileStick setOrigin:_mobileLeftStart displacement:delta];
        }
    }
    if (_mobileInterface && [touches containsObject:_mobileInterface]) {
        CGPoint point = [_mobileInterface locationInView:self];
        if (_mobileInterfacePending &&
            hypot(point.x - _mobileInterfaceStart.x, point.y - _mobileInterfaceStart.y) >= SP_MOBILE_DRAG_DISTANCE) {
            _mobileInterfacePending = NO;
            if (!_touches.count && !sp_mouse_buttons && sp_client_window) {
                _mobileInterfaceDown = YES;
                sp_mouse_button(0, YES, sp_from_uikit(_mobileInterfaceStart));
            }
        }
        if (_mobileInterfaceDown) {
            CGPoint p = sp_from_uikit(point);
            if (!CGPointEqualToPoint(p, sp_pointer)) sp_mouse_moved_to(p, SPLeftMouseDragged, NO);
        }
    }
    if (_mobileRight && !_mobileLookCancelled && [touches containsObject:_mobileRight])
        [self sp_mobile_move_look:[_mobileRight locationInView:self]];
    touches = [self sp_mobile_base_touches:touches];
    if (!touches.count) return;
#endif
    [self sp_base_touchesMoved:touches withEvent:event];
}

#if !TARGET_OS_VISION
- (NSSet<UITouch *> *)sp_mobile_finish:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    NSSet<UITouch *> *base = [self sp_mobile_base_touches:touches];
    if (_mobileInterface && [touches containsObject:_mobileInterface]) {
        if (!cancelled && _mobileInterfaceDown) {
            CGPoint p = sp_from_uikit([_mobileInterface locationInView:self]);
            sp_mouse_button(0, NO, p);
            _mobileInterfaceDown = NO;
        } else if (!cancelled && _mobileInterfacePending) {
            [self sp_mobile_tap:_mobileInterfaceStart finish:[_mobileInterface locationInView:self]
                       elapsed:_mobileInterface.timestamp - _mobileInterfaceAt];
        }
        [self sp_mobile_end_interface];
        _mobileInterface = nil;
    }
    if (_mobileLeft && [touches containsObject:_mobileLeft]) {
        [_mobileStick stop];
        if (!cancelled && !_mobileMoving && !_mobileInterface)
            [self sp_mobile_tap:_mobileLeftStart finish:[_mobileLeft locationInView:self]
                       elapsed:_mobileLeft.timestamp - _mobileLeftAt];
        _mobileLeft = nil;
    }
    if (_mobileRight && [touches containsObject:_mobileRight]) {
        [self sp_mobile_release_look];
        if (!cancelled && !_mobileLookDrag && !_mobileLookCancelled && !_mobileInterface)
            [self sp_mobile_tap:_mobileRightStart finish:[_mobileRight locationInView:self]
                       elapsed:_mobileRight.timestamp - _mobileRightAt];
        _mobileRight = nil;
    }
    return base;
}
#endif

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    touches = [self sp_mobile_finish:touches cancelled:NO];
    if (!touches.count) return;
#endif
    [self sp_base_touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    touches = [self sp_mobile_finish:touches cancelled:YES];
    if (!touches.count) return;
#endif
    [self sp_base_touchesCancelled:touches withEvent:event];
}
