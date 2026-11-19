#!/usr/bin/env python3
"""Experimental iPhone keyboard overlay for Slashplayed v1.5.1.

Only modifies shims/appkit/spevent.m (UIKit -> existing Mac NSEvent queue).
No credentials or game data; keep the app unchanged until a user tests the kit.
"""
from pathlib import Path
import sys

def once(source: str, needle: str, replacement: str) -> str:
    count = source.count(needle)
    if count != 1:
        raise SystemExit(f"Expected exactly one patch anchor ({count}): {needle[:100]!r}")
    return source.replace(needle, replacement, 1)

source_file = Path(sys.argv[1]) if len(sys.argv) == 2 else Path("shims/appkit/spevent.m")
original = source_file.read_text()
if "SPSoftKeyboardField" in original:
    raise SystemExit("Keyboard patch already applied; refusing to apply twice")

s = once(original,
    "static int sp_logged_events;\n",
    "static int sp_logged_events;\n"
    "static BOOL sp_soft_typing;  // don't log content from iPhone keyboard (names/chat)\n")
s = once(s,
    "if ((max == 0 || sp_logged_events < max) && e->type != SPMouseMoved",
    "if (!sp_soft_typing && (max == 0 || sp_logged_events < max) && e->type != SPMouseMoved")

keyboard_impl = r'''
#if !TARGET_OS_VISION
// Experimental iPhone software keyboard. UIKit text input does not reach WoW's
// native AppKit text fields directly. Convert keyboard edits into the SAME NSEvent
// queue already used by hardware keyboards (sp_key above). Do not change the game.
static unsigned short sp_soft_mac_code(unichar c) {
    unichar lower = (unichar)[[NSString stringWithCharacters:&c length:1].lowercaseString characterAtIndex:0];
    if (lower >= 'a' && lower <= 'z') return sp_hid_to_mac[0x04 + lower - 'a'];
    if (lower >= '1' && lower <= '9') return sp_hid_to_mac[0x1e + lower - '1'];
    if (lower == '0') return sp_hid_to_mac[0x27];
    switch (lower) {
    case ' ': return 0x31;
    case '-': return 0x1b;
    case '=': return 0x18;
    case '.': return 0x2f;
    case ',': return 0x2b;
    case '/': return 0x2c;
    case ';': return 0x29;
    case ':': return 0x29;
    case '(': return 0x19;
    case ')': return 0x1d;
    case '*': return 0x1c;
    case '&': return 0x1a;
    case '%': return 0x17;
    case '^': return 0x16;
    case '$': return 0x15;
    case '#': return 0x14;
    case '_': return 0x1b;
    case '+': return 0x18;
    case '[': case '{': return 0x21;
    case ']': case '}': return 0x1e;
    case 0x5c: case '|': return 0x2a;
    case '<': return 0x2b;
    case '>': return 0x2f;
    case 0x22: return 0x27;
    case '`': case '~': return 0x32;
    case 0x27: return 0x27;
    case '!': return 0x12;
    case '?': return 0x2c;
    case '@': return 0x13;
    default: return 0; // Unicode text still carries its actual characters.
    }
}

static void sp_soft_emit(NSString *characters, unsigned short code, BOOL shift) {
    SPEvent *down = sp_event(SPKeyDown);
    down->keyCode = code;
    down->characters = characters;
    down->charactersIgnoringModifiers = [characters lowercaseString];
    if (shift) down->modifierFlags |= SPShift;
    SPEvent *up = sp_event(SPKeyUp);
    up->keyCode = code;
    up->characters = characters;
    up->charactersIgnoringModifiers = down->charactersIgnoringModifiers;
    if (shift) up->modifierFlags |= SPShift;
    // The normal event logger prints typed characters. Never record text here.
    sp_soft_typing = YES;
    sp_post(down);
    sp_post(up);
    sp_soft_typing = NO;
}

@interface SPSoftKeyboardField : UITextField <UITextFieldDelegate>
@end
@implementation SPSoftKeyboardField
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.delegate = self;
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.autocorrectionType = UITextAutocorrectionTypeNo;
    self.spellCheckingType = UITextSpellCheckingTypeNo;
    self.smartQuotesType = UITextSmartQuotesTypeNo;
    self.smartDashesType = UITextSmartDashesTypeNo;
    self.keyboardType = UIKeyboardTypeDefault;
    self.returnKeyType = UIReturnKeyDone;
    self.textContentType = nil;
    self.placeholder = @"Skriv eller klistra in text här";
    self.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.98];
    self.textColor = UIColor.whiteColor;
    self.tintColor = UIColor.whiteColor;
    self.font = [UIFont systemFontOfSize:17];
    self.borderStyle = UITextBorderStyleRoundedRect;
    self.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.accessibilityLabel = @"Game chat input";
    return self;
}
- (BOOL)becomeFirstResponder {
    self.hidden = NO;
    BOOL result = [super becomeFirstResponder];
    if (!result) self.hidden = YES;
    [self.superview setNeedsLayout];
    return result;
}
- (void)textFieldDidEndEditing:(UITextField *)field {
    field.hidden = YES;
    [field.superview setNeedsLayout];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    // Keep UIKit editing local until an explicit Return. Selection, deletion,
    // autocorrect and Paste therefore edit the exact visible draft.
    // Never execute multiple pasted lines as separate commands.
    NSString *draft = [[field.text ?: @"" componentsSeparatedByCharactersInSet:
                        NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    [draft enumerateSubstringsInRange:NSMakeRange(0, draft.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *part, NSRange subrange, NSRange enclosing, BOOL *stop) {
        unichar c = [part characterAtIndex:0];
        BOOL shift = (c >= 'A' && c <= 'Z') || [@"!@#$%^&*()_+{}|:\"<>?~" rangeOfString:part].location != NSNotFound;
        sp_soft_emit(part, sp_soft_mac_code(c), shift);
    }];
    sp_soft_emit(@"\r", 0x24, NO);
    field.text = @"";
    [field resignFirstResponder];
    [field.superview becomeFirstResponder];
    return NO;
}
@end
#endif

'''
s = once(s, "\n@implementation SPInputView {\n", "\n" + keyboard_impl + "@implementation SPInputView {\n")
s = once(s, "    CGPoint _scroll_last;\n",
    "    CGPoint _scroll_last;\n"
    "#if !TARGET_OS_VISION\n"
    "    SPSoftKeyboardField *_softField;\n"
    "    UIButton *_softToggle;\n"
    "    UIButton *_softEscape;\n"
    "#endif\n")
init_anchor = "    sp_cursor_view.layer.zPosition = 2000;\n    [self addSubview:sp_cursor_view];\n"
init_extra = r'''#if !TARGET_OS_VISION
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        _softField = [[SPSoftKeyboardField alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        _softField.hidden = YES;
        _softField.translatesAutoresizingMaskIntoConstraints = NO;
        _softField.layer.zPosition = 4000;
        [self addSubview:_softField];
        [NSLayoutConstraint activateConstraints:@[
            [_softField.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:12],
            [_softField.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-12],
            [_softField.bottomAnchor constraintEqualToAnchor:self.keyboardLayoutGuide.topAnchor constant:-5],
            [_softField.heightAnchor constraintEqualToConstant:38]
        ]];
        _softToggle = [UIButton buttonWithType:UIButtonTypeSystem];
        [_softToggle setTitle:@"⌨" forState:UIControlStateNormal];
        _softToggle.titleLabel.font = [UIFont systemFontOfSize:23 weight:UIFontWeightSemibold];
        [_softToggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _softToggle.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
        _softToggle.layer.cornerRadius = 10;
        _softToggle.layer.borderWidth = 1;
        _softToggle.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
        _softToggle.layer.zPosition = 3000;
        _softToggle.accessibilityLabel = @"Show or hide keyboard for World of Warcraft";
        [_softToggle addTarget:self action:@selector(sp_toggle_soft_keyboard:)
             forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_softToggle];
        _softEscape = [UIButton buttonWithType:UIButtonTypeSystem];
        [_softEscape setTitle:@"Esc" forState:UIControlStateNormal];
        _softEscape.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [_softEscape setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _softEscape.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
        _softEscape.layer.cornerRadius = 10;
        _softEscape.layer.borderWidth = 1;
        _softEscape.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
        _softEscape.layer.zPosition = 3000;
        _softEscape.accessibilityLabel = @"Escape key for World of Warcraft";
        [_softEscape addTarget:self action:@selector(sp_press_soft_escape:)
             forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_softEscape];
    }
#endif
'''
s = once(s,init_anchor,init_anchor+init_extra)
layout_anchor = "\n- (UIPointerStyle *)pointerInteraction:"
layout_impl = r'''
#if !TARGET_OS_VISION
- (void)layoutSubviews {
    [super layoutSubviews];
    if (_softToggle) {
        CGRect game = sp_game_rect();
        CGFloat right = CGRectGetMaxX(game);
        // Stay inside the game rect, away from the Dynamic Island strip.
        CGFloat top = MAX(8, self.safeAreaInsets.top + 4);
        _softToggle.frame = CGRectMake(MAX(8, right - 58), top, 50, 38);
        _softEscape.frame = CGRectMake(MAX(8, right - 116), top, 50, 38);
    }
}
- (void)sp_press_soft_escape:(UIButton *)button {
    // Send the AppKit Escape key (kVK_Escape 0x35) through the
    // same NSEvent queue as a connected physical keyboard.
    sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0x1b], 0x35, NO);
}
- (void)sp_toggle_soft_keyboard:(UIButton *)button {
    if (_softField.isFirstResponder) {
        [_softField resignFirstResponder];
        [self becomeFirstResponder];  // restore physical keyboard and gamepad input
        button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    } else {
        [_softField becomeFirstResponder];
        button.backgroundColor = [UIColor colorWithRed:0.13 green:0.38 blue:0.62 alpha:0.9];
    }
}
#endif

'''
s = once(s, layout_anchor, "\n"+layout_impl+"- (UIPointerStyle *)pointerInteraction:")
if s.count("SPSoftKeyboardField") < 3 or s.count("sp_soft_emit(") < 4:
    raise SystemExit("Generated overlay was not applied completely")
source_file.write_text(s)
print(f"Patched {source_file}: {len(original)} -> {len(s)} bytes")
