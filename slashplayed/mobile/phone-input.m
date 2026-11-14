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
    return sp_mobile_zone(x, y, interface);
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

// SPInputView methods follow.
#if !TARGET_OS_VISION
- (void)sp_mobile_jump:(BOOL)down {
    if (_mobileJumpHeld == down) return;
    _mobileJumpHeld = down;
    SPEvent *event = sp_event(down ? SPKeyDown : SPKeyUp);
    event->keyCode = 0x31;
    event->characters = event->charactersIgnoringModifiers = @" ";
    sp_soft_typing = YES;
    sp_post(event);
    sp_soft_typing = NO;
    _mobileJump.alpha = down ? 0.72 : 1;
}

- (void)sp_mobile_jump_down:(UIButton *)button {
    if (!_mobileEditing && !_softField.isFirstResponder) [self sp_mobile_jump:YES];
}

- (void)sp_mobile_jump_up:(UIButton *)button { [self sp_mobile_jump:NO]; }

- (void)sp_mobile_release_look {
    if (!_mobileLooking) return;
    _mobileLooking = NO;
    // Keep the cursor at its last reported position when leaving a locked drag.
    sp_mouse_button(1, NO, sp_pointer);
}

- (void)sp_mobile_cancel {
    if (!_mobileStick) return;
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

    _mobileJump = sp_mobile_button(@"Jump", @"Jump or swim up", self, NULL);
    [_mobileJump addTarget:self action:@selector(sp_mobile_jump_down:) forControlEvents:UIControlEventTouchDown];
    [_mobileJump addTarget:self action:@selector(sp_mobile_jump_up:)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _mobileJumpPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sp_mobile_drag_jump:)];
    _mobileJumpPan.enabled = NO;
    [_mobileJump addGestureRecognizer:_mobileJumpPan];
    _mobileUI = sp_mobile_button(_mobileDirect ? @"UI" : @"Play", @"Toggle touch UI mode for dragging game panels and spells",
                                self, @selector(sp_mobile_toggle_ui:));
    _mobileEdit = sp_mobile_button(@"Edit", @"Edit phone controls", self, @selector(sp_mobile_toggle_edit:));
    _mobileSpeed = sp_mobile_button([NSString stringWithFormat:@"%.2g×", _mobileLookSpeed],
                                    @"Camera sensitivity", self, @selector(sp_mobile_cycle_speed:));
    _mobileReset = sp_mobile_button(@"Reset", @"Reset camera speed and jump position", self, @selector(sp_mobile_reset:));
    _mobileReset.hidden = _mobileSpeed.hidden = YES;
    for (UIButton *button in @[_mobileJump, _mobileUI, _mobileEdit, _mobileSpeed, _mobileReset]) {
        button.exclusiveTouch = NO;
        [self addSubview:button];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sp_mobile_deactivate:)
                                                name:UISceneWillDeactivateNotification object:nil];
}

- (void)sp_mobile_deactivate:(NSNotification *)notification {
    if (notification.object == self.window.windowScene) [self sp_mobile_cancel];
}

- (void)sp_mobile_layout:(CGRect)game top:(CGFloat)top {
    if (!CGRectEqualToRect(game, _mobileGameRect)) {
        [self sp_mobile_cancel];
        _mobileGameRect = game;
    }
    CGFloat left = CGRectGetMinX(game) + MAX(8, self.safeAreaInsets.left - CGRectGetMinX(game));
    _mobileUI.frame = CGRectMake(left, top, 46, 44);
    _mobileEdit.frame = CGRectMake(left + 50, top, 50, 44);
    _mobileSpeed.frame = CGRectMake(left + 104, top, 49, 44);
    _mobileReset.frame = CGRectMake(left + 157, top, 53, 44);
    _mobileJump.bounds = CGRectMake(0, 0, 56, 48);
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:@"sp_mobile_jump_position"];
    CGPoint fraction = CGPointMake(0.70, 0.83);
    if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
        [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
        CGFloat x = [saved[0] doubleValue], y = [saved[1] doubleValue];
        if (isfinite(x) && isfinite(y)) fraction = CGPointMake(x, y);
    }
    _mobileJump.center = [self sp_mobile_clamp_jump:CGPointMake(game.origin.x + fraction.x * game.size.width,
                                                               game.origin.y + fraction.y * game.size.height)];
}

- (CGPoint)sp_mobile_clamp_jump:(CGPoint)point {
    CGRect inner = CGRectInset(_mobileGameRect, 32, 28);
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
                                              forKey:@"sp_mobile_jump_position"];
    } else if (pan.state == UIGestureRecognizerStateCancelled) {
        [self setNeedsLayout];
    }
}

- (void)sp_mobile_toggle_edit:(UIButton *)button {
    [self sp_mobile_cancel];
    _mobileEditing = !_mobileEditing;
    _mobileJumpPan.enabled = _mobileEditing;
    _mobileReset.hidden = _mobileSpeed.hidden = !_mobileEditing;
    [button setTitle:_mobileEditing ? @"Done" : @"Edit" forState:UIControlStateNormal];
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
    [prefs removeObjectForKey:@"sp_mobile_jump_position"];
    [prefs removeObjectForKey:@"sp_mobile_look_speed"];
    _mobileLookSpeed = 1;
    [_mobileSpeed setTitle:@"1×" forState:UIControlStateNormal];
    [self setNeedsLayout];
}

- (void)sp_mobile_move_look:(CGPoint)point {
    if (!_mobileLooking) {
        if (_touches.count || sp_mouse_buttons) return;
        CGPoint origin = _mobileLookDrag ? point : _mobileRightStart;
        if (!_mobileLookDrag && hypot(point.x - origin.x, point.y - origin.y) < 7) return;
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
    if (!_mobileInterfaceDown) return;
    _mobileInterfaceDown = NO;
    sp_mouse_button(0, NO, sp_pointer);
}

- (void)sp_mobile_tap:(CGPoint)start {
    [self sp_mobile_release_look];
    if (_touches.count || sp_mouse_buttons) return;
    CGPoint position = sp_from_uikit(start);
    sp_mouse_button(0, YES, position);
    sp_mouse_button(0, NO, position);
}
#endif

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    if (_mobileDirect && !_mobileEditing && !_softField.isFirstResponder && sp_client_window &&
        !_touches.count && (sp_mouse_buttons == 0 || (_mobileLooking && sp_mouse_buttons == 2))) {
        for (UITouch *touch in touches) {
            if (!sp_finger(touch)) continue;
            CGPoint point = [touch locationInView:self];
            enum SPMobileZone zone = sp_mobile_touch_zone(point, sp_game_rect());
            if (zone == SPMobileInterface && !_mobileInterface) {
                [self sp_mobile_release_look];
                _mobileInterface = touch;
                _mobileInterfaceDown = YES;
                sp_mouse_button(0, YES, sp_from_uikit(point));
            } else if (zone == SPMobileMove && !_mobileLeft) {
                _mobileLeft = touch;
                _mobileLeftStart = point;
                _mobileMoving = NO;
            } else if (zone == SPMobileLook && !_mobileRight) {
                _mobileRight = touch;
                _mobileRightStart = point;
                _mobileLookDrag = _mobileLookCancelled = NO;
            }
        }
    }
    touches = [self sp_mobile_base_touches:touches];
    if (!touches.count || _mobileInterfaceDown) return;
    [self sp_mobile_release_look];
#endif
    [self sp_base_touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_VISION
    if (_mobileLeft && [touches containsObject:_mobileLeft]) {
        CGPoint point = [_mobileLeft locationInView:self];
        CGPoint delta = CGPointMake(point.x - _mobileLeftStart.x, point.y - _mobileLeftStart.y);
        if (!_mobileMoving && hypot(delta.x, delta.y) >= 7) {
            _mobileMoving = YES;
            [_mobileStick setOrigin:_mobileLeftStart displacement:delta];
        } else if (_mobileMoving && !_mobileStick.hidden) {
            [_mobileStick setOrigin:_mobileLeftStart displacement:delta];
        }
    }
    if (_mobileInterfaceDown && [touches containsObject:_mobileInterface]) {
        CGPoint p = sp_from_uikit([_mobileInterface locationInView:self]);
        if (!CGPointEqualToPoint(p, sp_pointer)) sp_mouse_moved_to(p, SPLeftMouseDragged, NO);
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
        }
        [self sp_mobile_end_interface];
        _mobileInterface = nil;
    }
    if (_mobileLeft && [touches containsObject:_mobileLeft]) {
        [_mobileStick stop];
        if (!cancelled && !_mobileMoving) [self sp_mobile_tap:_mobileLeftStart];
        _mobileLeft = nil;
    }
    if (_mobileRight && [touches containsObject:_mobileRight]) {
        [self sp_mobile_release_look];
        if (!cancelled && !_mobileLookDrag) [self sp_mobile_tap:_mobileRightStart];
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
