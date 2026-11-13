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
    return self;
}
- (BOOL)textField:(UITextField *)field
 shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)replacement {
    // Keep the UIKit field empty, so it never stores WoW chat text.
    // Newlines come through textFieldShouldReturn:. Backspace: deleteBackward.
    if (replacement.length) {
        [replacement enumerateSubstringsInRange:NSMakeRange(0, replacement.length)
                                        options:NSStringEnumerationByComposedCharacterSequences
                                     usingBlock:^(NSString *part, NSRange subrange, NSRange enclosing, BOOL *stop) {
            unichar c = [part characterAtIndex:0];
            BOOL shift = (c >= 'A' && c <= 'Z');
            sp_soft_emit(part, sp_soft_mac_code(c), shift);
        }];
    }
    return NO;
}
- (void)deleteBackward {
    sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0x7f], 0x33, NO);
    [super deleteBackward];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    sp_soft_emit(@"\r", 0x24, NO);
    [field resignFirstResponder];
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
    "#endif\n")
init_anchor = "    sp_cursor_view.layer.zPosition = 2000;\n    [self addSubview:sp_cursor_view];\n"
init_extra = r'''#if !TARGET_OS_VISION
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        _softField = [[SPSoftKeyboardField alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        _softField.alpha = 0.02; // still in hierarchy and eligible for first responder
        [self addSubview:_softField];
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
        _softToggle.frame = CGRectMake(MAX(8, right - 58),
                                      MAX(8, self.safeAreaInsets.top + 4), 50, 38);
    }
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
