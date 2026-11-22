// Included by patch.py in the pinned Slashplayed AppKit shim.
#if !TARGET_OS_VISION
#include "touch-zone.h"
// The virtual left stick uses the GameController path from Slashplayed Enhanced (MIT).
@interface SPMobileStick : UIView
- (void)setOrigin:(CGPoint)origin displacement:(CGPoint)delta;
- (void)stop;
- (void)prepareAI;
- (BOOL)driveAI:(CGPoint)axis;
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

- (void)prepareAI { [self connectIfNeeded]; }

// Reuse the actual virtual controller used by the manual touch path.
- (BOOL)driveAI:(CGPoint)axis {
    [self connectIfNeeded];
    if (!_connected || !_virtualController.controller || !self.window ||
        self.window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    _value = axis;
    self.hidden = YES;
    [_virtualController setPosition:axis forDirectionPadElement:GCInputLeftThumbstick];
    return YES;
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
            CGRect rect = sp_hover_rects[i];
            if (rect.size.width * rect.size.height > 0.25) continue;
            if (!CGRectContainsPoint(rect, CGPointMake(x, 1 - y))) continue;
            interface = YES;
            break;
        }
    }
    enum SPMobileZone zone = getenv("SP_PHONE_UI_RECTS")
        ? sp_mobile_phone_zone(x, y, interface) : sp_mobile_zone(x, y, interface);
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
- (void)sp_mobile_ai_status:(NSString *)status {
    BOOL on = _mobileAIStartPending || (_mobileAI.active && !_mobileAI.manualPaused);
    BOOL healthBlocked = [status isEqualToString:@"HP SECRET"] || [status isEqualToString:@"HP UNKNOWN"];
    NSString *detail = healthBlocked ? @"HP BLOCKED" : status;
    if ([status isEqualToString:@"AI ON"] || [status isEqualToString:@"AI OFF"]) detail = nil;
    [_mobileAIButton setTitle:on ? @"AI ON" : @"AI OFF" forState:UIControlStateNormal];
    _mobileAIButton.accessibilityHint = on ? @"Tap to stop AI" : @"Tap to start AI";
    NSString *accessibilityState = on ? @"On" : @"Off";
    _mobileAIButton.accessibilityValue = detail.length ?
        [NSString stringWithFormat:@"%@, %@", accessibilityState, detail] : accessibilityState;
    _mobileAIButton.backgroundColor = healthBlocked ? [UIColor colorWithRed:0.47 green:0.26 blue:0.06 alpha:0.95]
        : on ? [UIColor colorWithRed:0.10 green:0.39 blue:0.22 alpha:0.92] : [UIColor colorWithWhite:0 alpha:0.55];
    _mobileAIStatus.text = detail;
    _mobileAIStatus.hidden = _mobileAIButton.hidden || !detail.length;
}

- (void)sp_mobile_ai_cancel_pending {
    ++_mobileAIKeyGeneration;
    if (_mobileAIStartPending) {
        _mobileAIStartPending = NO;
        [self sp_mobile_ai_status:_mobileAI.manualPaused ? @"AI PAUSED" : nil];
    }
}

- (void)sp_mobile_ai_yield:(id)sender {
    [self sp_mobile_ai_cancel_pending];
    [self sp_mobile_ai_release_key];
    [_mobileAI yieldToManualInput];
    _mobileAIManualUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
}
- (void)sp_mobile_jump:(BOOL)down {
    if (down || _mobileJumpHeld) [self sp_mobile_ai_yield:nil];
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
    [self sp_mobile_ai_yield:nil];
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
    // Always start the session in Play mode; UI mode remains available temporarily.
    _mobileDirect = YES;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"sp_mobile_ui_mode"];
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
    _mobilePhysicalKeys = [NSMutableIndexSet indexSet];
    _mobileAIButton = sp_mobile_button(@"AI OFF", @"Local AI", self, @selector(sp_mobile_ai_toggle:));
    _mobileAIButton.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _mobileAIButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _mobileAIButton.titleLabel.minimumScaleFactor = 0.7;
    _mobileAIButton.layer.cornerRadius = 22;
    _mobileAIButton.hidden = YES;
    _mobileAIStatus = [[UILabel alloc] initWithFrame:CGRectZero];
    _mobileAIStatus.textColor = UIColor.whiteColor;
    _mobileAIStatus.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _mobileAIStatus.textAlignment = NSTextAlignmentCenter;
    _mobileAIStatus.adjustsFontSizeToFitWidth = YES;
    _mobileAIStatus.backgroundColor = [UIColor colorWithWhite:0 alpha:0.64];
    _mobileAIStatus.layer.cornerRadius = 5;
    _mobileAIStatus.clipsToBounds = YES;
    _mobileAIStatus.layer.zPosition = _mobileAIButton.layer.zPosition;
    _mobileAIStatus.userInteractionEnabled = NO;
    _mobileAIStatus.isAccessibilityElement = NO;
    [self addSubview:_mobileAIStatus];
    [self sp_mobile_ai_status:nil];
    // The AI toggle is an explicit request to start or stop automation.
    // TouchDown on the other controls still yields to manual input.
    for (UIButton *button in @[_mobileRotation, _mobileUI, _mobileEdit, _mobileSpeed, _mobileReset, _softToggle])
        [button addTarget:self action:@selector(sp_mobile_ai_yield:) forControlEvents:UIControlEventTouchDown];
    _mobileAI.releaseInput = ^{
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_ai_release_key];
    };
    _mobileAI.action = ^BOOL(NSString *action, CGPoint point, NSTimeInterval captured, NSTimeInterval duration) {
        SPInputView *input = weakSelf;
        if (!input || !input->_mobileAI.active || !input->_mobileAI.autonomousTest || !sp_client_window || input->_softField.isFirstResponder ||
            !input.window || input.window.windowScene.activationState != UISceneActivationStateForegroundActive ||
            input->_mobileEditing || input->_mobileLeft || input->_mobileRight || input->_mobileInterface ||
            input->_touches.count || input->_mobilePhysicalKeys.count || sp_mouse_buttons || !input->_mobileDirect || input->_mobileJumpHeld ||
            input->_mobileRotation.highlighted || input->_mobileAIButton.highlighted || input->_softToggle.highlighted ||
            input->_mobileRotationPan.state == UIGestureRecognizerStateBegan ||
            input->_mobileRotationPan.state == UIGestureRecognizerStateChanged ||
            captured < input->_mobileAIManualUntil || NSProcessInfo.processInfo.systemUptime < input->_mobileAIManualUntil) return NO;
        if (!sp_ai_move(action)) [input sp_mobile_ai_release_key];
        if ([action isEqualToString:@"ATTACK"]) {
            sp_mobile_emit_rotation();
            sp_stub_log("AI input: Tactara F12 rotation");
        }
        else if ([action isEqualToString:@"TARGET"]) sp_soft_emit(@"\t", 0x30, NO);
        else if ([action isEqualToString:@"LOOT"]) {
            if (!(sp_ai_game_meta & 4)) return NO;
            if (sp_ai_game_meta & 1) sp_soft_emit(@"f", 0x03, NO);
            else sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70D], 0x6D, NO);
            sp_stub_log("AI input: interact with selected corpse");
        }
        else if ([action isEqualToString:@"TURN_LEFT"] || [action isEqualToString:@"TURN_RIGHT"])
            return [input sp_mobile_ai_hold_turn:sp_ai_move(action) duration:duration];
        else if ([action isEqualToString:@"FORWARD"]) return [input sp_mobile_ai_hold_axis:CGPointMake(0,1) duration:duration];
        else if ([action isEqualToString:@"BACK"]) return [input sp_mobile_ai_hold_axis:CGPointMake(0,-1) duration:duration];
        else if ([action isEqualToString:@"LEFT"] || [action isEqualToString:@"STRAFE_LEFT"])
            return [input sp_mobile_ai_hold_axis:CGPointMake(-1,0) duration:duration];
        else if ([action isEqualToString:@"RIGHT"] || [action isEqualToString:@"STRAFE_RIGHT"])
            return [input sp_mobile_ai_hold_axis:CGPointMake(1,0) duration:duration];
        else if ([action isEqualToString:@"INTERACT"] || [action isEqualToString:@"CLICK"]) {
            CGRect bounds = input.window.bounds;
            CGPoint screen = CGPointMake(CGRectGetMinX(bounds) + point.x * bounds.size.width,
                                          CGRectGetMinY(bounds) + point.y * bounds.size.height);
            CGPoint local = [input convertPoint:screen fromView:input.window];
            if (!CGRectContainsPoint(input->_mobileGameRect, local) ||
                CGRectContainsPoint(input->_mobileAIButton.frame, local) ||
                CGRectContainsPoint(input->_mobileRotation.frame, local) ||
                CGRectContainsPoint(input->_softToggle.frame, local)) return NO;
            CGPoint position = sp_from_uikit(local);
            NSInteger button = [action isEqualToString:@"INTERACT"] ? 1 : 0;
            sp_mouse_button(button, YES, position);
            sp_mouse_button(button, NO, position);
        } else return NO;
        return YES;
    };
    _mobileAI.status = ^(NSString *status) {
        [weakSelf sp_mobile_ai_status:status];
    };
    _mobileReset.hidden = _mobileSpeed.hidden = YES;
    for (UIButton *button in @[_mobileJump, _mobileUI, _mobileEdit, _mobileSpeed, _mobileReset, _mobileRotation, _mobileAIButton]) {
        button.exclusiveTouch = NO;
        [self addSubview:button];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sp_mobile_deactivate:)
                                                name:UISceneWillDeactivateNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sp_mobile_background:)
                                                name:UISceneDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sp_mobile_activate:)
                                                name:UISceneDidActivateNotification object:nil];
}

- (void)sp_mobile_deactivate:(NSNotification *)notification {
    if (notification.object == self.window.windowScene) {
        [self sp_mobile_cancel];
        [_mobileAI stop];
    }
}
- (void)sp_mobile_background:(NSNotification *)notification {
    if (notification.object == self.window.windowScene) {
        [_mobileAI stop];
        _mobileAI.farmingAuthorized = NO;
        [self sp_mobile_cancel];
        [self sp_mobile_ai_status:nil];
    }
}
- (void)sp_mobile_activate:(NSNotification *)notification {
    if (notification.object != self.window.windowScene) return;
    [self sp_mobile_cancel];
    _mobileLeft = _mobileRight = _mobileInterface = nil;
    _mobileMoving = _mobileLookDrag = _mobileLookCancelled = NO;
    [self setNeedsLayout];
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
    UIAction *play = [UIAction actionWithTitle:@"Restore floating joystick (Play)" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_cancel];
        if (input->_mobileEditing) [input sp_mobile_toggle_edit:input->_mobileEdit];
        if (!input->_mobileDirect) [input sp_mobile_toggle_ui:input->_mobileUI];
        [input setNeedsLayout];
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
    NSArray<UIMenuElement *> *controls = @[
        escape, jump, showJump, rotation, showRotation, resetRotation, play, mode
    ];
    controls = [controls arrayByAddingObject:[self sp_mobile_ai_options]];
    return [UIMenu menuWithTitle:@"Game controls" children:[controls arrayByAddingObject:legacy]];
}

- (UIMenu *)sp_mobile_ai_options {
    __weak SPInputView *weakSelf = self;
    UIAction *observe = [UIAction actionWithTitle:@"End farming test authorization" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        input->_mobileAI.farmingAuthorized = NO;
        [input sp_mobile_ai_status:nil];
    }];
    UIAction *aiTest = [UIAction actionWithTitle:@"Test AI movement (forward)" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_ai_test:0];
    }];
    UIAction *approachTest = [UIAction actionWithTitle:@"Test approach (authorized realm, face selected target)"
        image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (input) [input sp_mobile_ai_test:3];
    }];
    UIAction *aiTeach = [UIAction actionWithTitle:@"Teach AI approach (start / save)" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI toggleTeaching];
    }];
    UIAction *markRoute = [UIAction actionWithTitle:@"Mark straight route leg (start or end)" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        [input->_mobileAI recordRouteMark];
    }];
    UIAction *clearRoute = [UIAction actionWithTitle:@"Clear recorded grind route" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        [input->_mobileAI clearGrindRoute];
    }];
    UIAction *aiTestMode = [UIAction actionWithTitle:@"Authorize farming in this test session" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        UIWindowScene *scene = input.window.windowScene;
        if (!input || !scene || scene.activationState != UISceneActivationStateForegroundActive) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        input->_mobileAI.farmingAuthorized = YES;
        [input sp_mobile_ai_status:@"TEST READY"];
    }];
    UIAction *aiModels = [UIAction actionWithTitle:@"Observe local models" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        input->_mobileAI.farmingAuthorized = NO;
        input->_mobileAI.modelDiagnostics = YES;
        input->_mobileAI.healthDiagnostics = NO;
        [input sp_mobile_ai_start];
    }];
    UIAction *inspectHealth = [UIAction actionWithTitle:@"Observe visible player health" image:nil identifier:nil handler:^(__kindof UIAction *action) {
        SPInputView *input = weakSelf;
        if (!input) return;
        [input sp_mobile_ai_cancel_pending];
        [input->_mobileAI stop];
        input->_mobileAI.farmingAuthorized = NO;
        input->_mobileAI.healthDiagnostics = YES;
        input->_mobileAI.modelDiagnostics = NO;
        [input sp_mobile_ai_start];
    }];
    UIMenu *authorization = [UIMenu menuWithTitle:@"Authorized test session" children:@[aiTestMode, observe]];
    UIMenu *route = [UIMenu menuWithTitle:@"Grind route" children:@[markRoute, clearRoute]];
    return [UIMenu menuWithTitle:@"AI diagnostics" children:@[authorization, aiTest, approachTest, route, inspectHealth, aiModels, aiTeach]];
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
    _mobileAIButton.bounds = CGRectMake(0, 0, 64, 44);
    _mobileAIButton.center = [self sp_mobile_clamp_rotation:CGPointMake(
        game.origin.x + 0.88 * game.size.width, game.origin.y + 0.28 * game.size.height)];
    CGFloat captionWidth = MIN(104, CGRectGetWidth(game));
    CGFloat captionX = MAX(CGRectGetMinX(game), MIN(CGRectGetMaxX(game) - captionWidth,
        _mobileAIButton.center.x - captionWidth * 0.5));
    _mobileAIStatus.frame = CGRectMake(captionX, CGRectGetMaxY(_mobileAIButton.frame) + 2, captionWidth, 17);
    _mobileAIStatus.hidden = _mobileAIButton.hidden || !_mobileAIStatus.text.length;
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

static void sp_mobile_ai_movement_key(unsigned char key, BOOL pressed) {
    BOOL left = key == SP_KEY_ARROW_LEFT, right = key == SP_KEY_ARROW_RIGHT;
    NSString *characters = left ? @"\uf702" : right ? @"\uf703" : [NSString stringWithFormat:@"%c", key];
    SPEvent *event = sp_event(pressed ? SPKeyDown : SPKeyUp);
    event->keyCode = left ? 0x7B : right ? 0x7C : sp_soft_mac_code(key);
    event->characters = characters;
    event->charactersIgnoringModifiers = characters;
    event->modifierFlags = left || right ? SPFunction | SPNumericPad : 0;
    BOOL previousTyping = sp_soft_typing;
    sp_soft_typing = YES;
    sp_post(event);
    sp_soft_typing = previousTyping;
}

- (void)sp_mobile_ai_release_key {
    SPMovementCommand command = sp_movement_release(&_mobileAIMovement, 0);
    if (!command.deadline) return;
    if (command.key) sp_mobile_ai_movement_key(command.key, NO);
    else [_mobileStick stop];
}
- (BOOL)sp_mobile_ai_hold_axis:(CGPoint)axis duration:(NSTimeInterval)duration {
    SPAIMove move = axis.y > 0 ? SP_MOVE_FORWARD : axis.y < 0 ? SP_MOVE_BACK :
        axis.x < 0 ? SP_MOVE_LEFT : axis.x > 0 ? SP_MOVE_RIGHT : SP_MOVE_NONE;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    uint8_t key = sp_ai_sample_fresh(sp_ai_game_at, now) ? sp_ai_movement_key(move, sp_ai_game_move_keys) : 0;
    if (move == SP_MOVE_NONE || !sp_movement_begin(&_mobileAIMovement, key, now, duration)) return NO;
    if (key) {
        sp_mobile_ai_movement_key(key, YES);
        sp_stub_log([[NSString stringWithFormat:@"AI input: held verified key %c", key] UTF8String]);
    } else if ([_mobileStick driveAI:axis]) {
        sp_stub_log([[NSString stringWithFormat:@"AI input: virtual stick %.1f %.1f", axis.x, axis.y] UTF8String]);
    } else {
        sp_movement_release(&_mobileAIMovement, 0);
        sp_stub_log("AI input: no verified key and virtual controller not ready");
        return NO;
    }
    [self sp_mobile_ai_schedule_release:_mobileAIMovement.generation];
    return YES;
}
- (BOOL)sp_mobile_ai_hold_turn:(SPAIMove)move duration:(NSTimeInterval)duration {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!sp_ai_sample_fresh(sp_ai_game_at, now)) return NO;
    uint8_t key = sp_ai_movement_key(move, sp_ai_game_move_keys);
    if (!key || !sp_movement_begin(&_mobileAIMovement, key, now, duration)) return NO;
    sp_mobile_ai_movement_key(key, YES);
    sp_stub_log(move == SP_TURN_LEFT ? "AI input: held verified left-arrow turn" : "AI input: held verified right-arrow turn");
    [self sp_mobile_ai_schedule_release:_mobileAIMovement.generation];
    return YES;
}
- (void)sp_mobile_ai_schedule_release:(uint64_t)generation {
    NSTimeInterval remaining = _mobileAIMovement.deadline - NSProcessInfo.processInfo.systemUptime;
    __weak SPInputView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(remaining, 0.001) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPInputView *input = weakSelf;
        if (!input || !input->_mobileAIMovement.deadline || input->_mobileAIMovement.generation != generation) return;
        if (sp_movement_due(&input->_mobileAIMovement, generation, NSProcessInfo.processInfo.systemUptime))
            [input sp_mobile_ai_release_key];
        else [input sp_mobile_ai_schedule_release:generation];
    });
}
- (void)sp_mobile_ai_check_test:(SPAINavPulse)pulse generation:(NSUInteger)generation
    remaining:(unsigned)remaining lastSample:(SPAINavSample)lastSample {
    if (_mobileAIKeyGeneration != generation) return;
    if (_mobileAI.active || self.window.windowScene.activationState != UISceneActivationStateForegroundActive) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    SPAINavSample after = sp_ai_game_sample();
    if (remaining && (!sp_ai_sample_fresh(after.at, now) || sp_ai_player_health != SP_HEALTH_PUBLIC ||
        !sp_ai_hp_known(sp_ai_game_hp) || sp_ai_game_hp < 35)) {
        [self sp_mobile_ai_release_key];
        [self sp_mobile_ai_status:@"HP BLOCKED"];
        sp_stub_log("AI movement diagnostic: repeated approach stopped without fresh safe player health");
        return;
    }
    SPAINavOutcome outcome = sp_ai_nav_observe(pulse, &after, now, &lastSample);
    if (outcome == SP_NAV_PENDING) {
        __weak SPInputView *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf sp_mobile_ai_check_test:pulse generation:generation remaining:remaining lastSample:lastSample];
        });
        return;
    }
    NSString *status = @"TEST NO DATA";
    switch (outcome) {
        case SP_NAV_CLOSER: status = @"TEST CLOSER"; break;
        case SP_NAV_DISPLACED: status = @"TEST MOVED"; break;
        case SP_NAV_NO_PROGRESS: status = @"TEST NO GAIN"; break;
        case SP_NAV_STALLED: status = @"TEST STALL"; break;
        case SP_NAV_CONTEXT_CHANGED: status = @"TEST TARGET"; break;
        default: break;
    }
    [self sp_mobile_ai_status:status];
    sp_stub_log([[NSString stringWithFormat:@"AI movement diagnostic: %s distance-q4=%u->%u",
        sp_ai_nav_outcome_name(outcome), (unsigned)pulse.before.evidence.distance, (unsigned)after.evidence.distance] UTF8String]);
    [_mobileAI recordManualProbe:pulse outcome:outcome];
    if (sp_ai_forward_probe_repeat(outcome, remaining)) {
        [self sp_mobile_ai_release_key];
        [self sp_mobile_ai_schedule_test:remaining - 1 after:after];
    }
}

// The standalone pulse and opt-in approach probe share the same input adapter.
- (void)sp_mobile_ai_test:(unsigned)remaining {
    [self sp_mobile_ai_cancel_pending];
    if (_mobileAI.active) [_mobileAI stop];
    [self sp_mobile_ai_release_key];
    [_mobileStick prepareAI];
    [self sp_mobile_ai_schedule_test:remaining after:(SPAINavSample){0}];
}

- (void)sp_mobile_ai_schedule_test:(unsigned)remaining after:(SPAINavSample)confirmed {
    NSUInteger generation = ++_mobileAIKeyGeneration;
    NSTimeInterval delay = confirmed.at && NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious ? 2.0 : 1.0;
    __weak SPInputView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPInputView *input = weakSelf;
        if (!input || input->_mobileAIKeyGeneration != generation || input->_mobileAI.active ||
            !sp_client_window || input->_softField.isFirstResponder || !input->_mobileDirect ||
            !input.window || input.window.windowScene.activationState != UISceneActivationStateForegroundActive ||
            input->_mobileEditing || input->_mobileLeft || input->_mobileRight || input->_mobileInterface ||
            input->_touches.count || input->_mobilePhysicalKeys.count || sp_mouse_buttons) return;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (NSProcessInfo.processInfo.thermalState == NSProcessInfoThermalStateCritical) {
            [input sp_mobile_ai_status:@"AI HEAT"];
            return;
        }
        SPAINavSample before = sp_ai_game_sample();
        if (!sp_ai_heartbeat_seen || !sp_ai_sample_fresh(before.at, now)) before = (SPAINavSample){0};
        if (remaining) {
            NSString *blocked = nil;
            if (!input->_mobileAI.farmingAuthorized) blocked = @"TEST MODE";
            else if (sp_ai_player_health != SP_HEALTH_PUBLIC || !sp_ai_hp_known(sp_ai_game_hp) ||
                sp_ai_game_hp < 35) blocked = @"HP BLOCKED";
            else if (confirmed.at && (before.evidence.target != confirmed.evidence.target ||
                before.evidence.position != confirmed.evidence.position)) blocked = @"TEST TARGET";
            else if (!sp_ai_forward_probe_ready(before, sp_ai_game_flags, sp_ai_game_move_keys, now) ||
                (confirmed.at && before.evidence.distance > confirmed.evidence.distance + 2)) blocked = @"TEST HOLD";
            if (blocked) {
                [input sp_mobile_ai_status:blocked];
                sp_stub_log([[NSString stringWithFormat:@"AI movement diagnostic: %@", blocked] UTF8String]);
                return;
            }
        }
        NSTimeInterval hold = 0.60;
        BOOL sent = [input sp_mobile_ai_hold_axis:CGPointMake(0,1) duration:hold];
        [input sp_mobile_ai_status:sent ? @"TEST ACCEPT" : @"TEST INPUT"];
        sp_stub_log(sent ? "AI movement diagnostic: adapter accepted" : "AI movement diagnostic: adapter rejected");
        if (sent) [input sp_mobile_ai_check_test:(SPAINavPulse){before, SP_MOVE_FORWARD, now+hold, now+1.8}
            generation:input->_mobileAIKeyGeneration remaining:remaining lastSample:(SPAINavSample){0}];
    });
}
- (BOOL)sp_mobile_ai_can_start {
    UIWindowScene *scene = self.window.windowScene;
    return sp_client_window && scene && scene.activationState == UISceneActivationStateForegroundActive &&
        !_softField.isFirstResponder && !_mobileEditing && !_mobileJumpHeld &&
        !_mobileLeft && !_mobileRight && !_mobileInterface && !_touches.count && !_mobilePhysicalKeys.count && !sp_mouse_buttons;
}

- (void)sp_mobile_ai_start {
    if (_mobileAIStartPending || ![self sp_mobile_ai_can_start]) return;
    [self sp_mobile_ai_release_key];
    NSUInteger generation = ++_mobileAIKeyGeneration;
    if (_mobileAI.autonomousTest) [_mobileStick prepareAI];
    _mobileAIStartPending = YES;
    [self sp_mobile_ai_status:nil];
    // Wait until UIKit finishes the button event before arming the executor.
    __weak SPInputView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SPInputView *input = weakSelf;
        if (!input || input->_mobileAIKeyGeneration != generation) return;
        input->_mobileAIStartPending = NO;
        if (![input sp_mobile_ai_can_start]) {
            [input sp_mobile_ai_status:input->_mobileAI.manualPaused ? @"AI PAUSED" : nil];
            return;
        }
        if (input->_mobileAI.manualPaused) [input->_mobileAI resumeFromManualInput];
        else [input->_mobileAI start];
    });
}

- (void)sp_mobile_ai_toggle:(UIButton *)button {
    if (_mobileAIStartPending || (_mobileAI.active && !_mobileAI.manualPaused)) {
        [self sp_mobile_ai_cancel_pending];
        [_mobileAI stop];
        return;
    }
    if (_mobileAI.manualPaused && _mobileAI.modelDiagnostics) [_mobileAI stop];
    _mobileAI.modelDiagnostics = NO;
    _mobileAI.healthDiagnostics = NO;
    [self sp_mobile_ai_start];
}

- (void)sp_mobile_rotation:(UIButton *)button {
    [self sp_mobile_ai_yield:button];
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
    [self sp_mobile_ai_yield:nil];
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
            [_mobileAI recordManualSteering:delta];
        } else if (_mobileMoving && !_mobileStick.hidden) {
            [_mobileStick setOrigin:_mobileLeftStart displacement:delta];
            [_mobileAI recordManualSteering:delta];
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
