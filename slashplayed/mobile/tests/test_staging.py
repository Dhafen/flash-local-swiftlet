import plistlib
import re
import sys
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wolkara_english import translate
from wolkara_hud import protect_cooldowns, protect_hud
from wolkara_rotation import actions, picker, turn

root = Path(sys.argv[1])
event = (root / "shims/appkit/spevent.m").read_text()
cdn = (root / "apps/client/spcdn.m").read_text()
kit = (root / "scripts/release/device-kit.sh").read_text()
assert 'SP_PHONE_UI_RECTS' in (root / 'apps/client/launcher.m').read_text()
assert 'sp_mobile_end_interface' in event
assert '@interface SPGameAIController' in event
assert 'sp_ai_game_update' in event and 'pollDirect:' in event
assert 'decideGameState:candidate:completion:' in event
assert 'sp_ai_game_update(sp_hover_asm.data + offset' in (root / "shims/appkit/sphover.m").read_text()
assert 'SPH_MAX_RECTS * 6 + 6' in (root / "shims/appkit/sphoverstrip.h").read_text()
assert '.. spAIState()' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'local function aiHeartbeat()' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'showChunk(aiFrame)' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'sp_ai_heartbeat(frame[2], frame + 5, SPH_PAYLOAD_BYTES)' in (root / "shims/appkit/sphover.m").read_text()
assert 'seq == sp_ai_heartbeat_seq' in event
assert '[_mobileAI stop];' in event
assert 'sp_mobile_emit_rotation()' in event
assert 'RPSampleBufferTypeVideo' in event
assert 'VNRecognizeTextRequest' in event
assert 'VNClassifyImageRequest' in event and 'sp_ai_luminance' in event
assert 'recordAction:observation:' in event and 'resetDecision' in event
assert 'captured < input->_mobileAIManualUntil' in event
assert 'executed = self.action' in event
assert 'SPAIHarness' in (root / "apps/client/SPAIGraph.swift").read_text()
assert 'harness.validate' in (root / "apps/client/spgameai.swift").read_text()
if sys.platform == "darwin" and len(sys.argv) == 2:
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        binary = str(Path(tmp) / "game-ai-tests")
        subprocess.run(["xcrun", "swiftc", str(root / "apps/client/SPAIGraph.swift"),
                        str(Path(__file__).with_name("test_ai_graph.swift")), "-o", binary], check=True)
        subprocess.run([binary], check=True)
assert '120 * NSEC_PER_SEC' not in event
assert 'AI OFF' in event and 'AI ON' in event
assert 'sp_mobile_phone_zone(x, y, interface)' in event
assert 'Restore floating joystick (Play)' in event
assert 'if (!_mobileAI.starting) [_mobileAI stop];' in event
assert 'UISceneDidEnterBackgroundNotification' in event
assert 'AI NO VID' in event and 'AI NO TEXT' in event and 'AI THINK' in event
assert 'AI MODEL!' in event and 'AI CAP!' in event
assert 'sp_mobile_ai_release_key' in event and 'sp_mobile_ai_hold_axis:' in event
assert '[_mobileStick driveAI:axis]' in event and 'Test AI movement (forward)' in event
assert 'AI input: Tactara F12 rotation' in event and 'sp_mobile_emit_rotation();' in event
assert 'VIS SLOW' in event
assert 'NSProcessInfo.processInfo.systemUptime - captured <= 8.0' in event
assert 'input->_mobileAIManualUntil' in event
assert '[parts[0] isEqualToString:@"INTERACT"]' in event
assert 'SystemLanguageModel.default.isAvailable' in (root / "apps/client/spgameai.swift").read_text()
assert 'spgameai.swift -o' in (root / "apps/client/build-launcher.sh").read_text()
assert 'sp_game_ai_register();' in (root / "apps/client/launcher.m").read_text()
assert '-framework Vision -framework ReplayKit -framework CoreMedia' in (root / "shims/generated/build.sh").read_text()
assert 'SP_MOBILE_RIGHT_PRESS_SECONDS 0.45' in event
assert 'sp_mobile_click(getenv("SP_PHONE_UI_RECTS") ? elapsed : 0,' in event
assert 'sp_mouse_button(click, YES, position);' in event and 'sp_mouse_button(click, NO, position);' in event
assert '_mobileInterfacePending = NO;' in event
assert 'elapsed:_mobileInterface.timestamp - _mobileInterfaceAt' in event
assert 'elapsed:_mobileLeft.timestamp - _mobileLeftAt' in event
assert 'elapsed:_mobileRight.timestamp - _mobileRightAt' in event
assert 'sp_mouse_button(0, YES, sp_from_uikit(_mobileInterfaceStart));' in event
assert '@interface SPMobileJumpButton' in event
assert 'event->modifierFlags = 0;' in event
assert 'sp_mobile_send_jump' in event
assert 'sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70F], 0x6F, NO);' in event
assert '_mobileRotation.hidden = !wolkaraHUD || CGRectIsEmpty(game) || _softField.isFirstResponder' in event
assert '_mobileRotationPan.cancelsTouchesInView = YES;' in event
assert 'sp_mobile_drag_rotation:' in event and 'sp_wolkara_rotation_position' in event
assert 'sp_mobile_clamp_rotation:' in event
assert 'Show / hide F12 button' in event and 'Reset F12 position' in event
assert 'BOOL compact = wolkaraHUD && ![prefs boolForKey:@"sp_wolkara_extra_controls"];' in event
assert '_softEscape.hidden = compact;' in event
assert '_mobileUI.hidden = _mobileEdit.hidden = compact;' in event
assert '_mobileSpeed.hidden = _mobileReset.hidden = compact || !_mobileEditing;' in event
assert '_mobileJump.hidden = compact && ![prefs boolForKey:@"sp_wolkara_show_jump"];' in event
assert '_softToggle.menu = [self sp_mobile_compact_menu];' in event
assert '_softToggle.showsMenuAsPrimaryAction = NO;' in event
assert 'CGRectGetMidX(game) - 22' in event
assert 'Show / hide Jump button' in event and 'Show / hide extra controls' in event
assert '[input sp_mobile_jump:YES];' in event and '[input sp_mobile_jump:NO];' in event
assert '_mobileRotation.bounds = CGRectMake(0, 0, 44, 44);' in event
assert '_mobileRotation.layer.cornerRadius = 22;' in event
assert 'sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70E], 0x67, NO);' in event
assert event.count('sp_soft_emit([NSString stringWithFormat:@"%C", (unichar)0xF70F], 0x6F, NO);') == 1
bars = (root / "addon/SPTouchBars/SPTouchBars.lua").read_text()
assert 'phoneLayout.enabled(db.phoneArc, SPPhoneTouchRects)' in bars
assert 'sp_mobile_touch_zone' in event, "Missing floating touch routing"
assert 'SPMobileCameraPad' not in event and '@"LOOK"' not in event
assert 'sp_mobile_release_look' in event and 'SPRightMouseDragged' in event
assert 'SPSoftKeyboardField' in event and 'sp_press_soft_escape:' in event
assert 'isEqual:@"enGB"] ? @"enUS"' in cdn
assert 'sp_install_hekili_if_absent' in cdn
assert 'SPMobileCombat' in cdn and 'SPMobileCombat' in kit
wolkara = root / "addon/WolkaraRoue"
reference = root / ".wolkara/addons/WolkaraRoue"
for source in reference.iterdir():
    if not source.is_file() or source.name == "WolkaraRoue.toc":
        continue
    if source.name == "Core.lua":
        expected = source.read_text().replace(
            "    local ok, problem = xpcall(fn, Trace, ...)",
            '    local args, count = { ... }, select("#", ...)\n'
            "    local ok, problem = xpcall(function() return fn(unpack(args, 1, count)) end, Trace)",
        )
        assert (wolkara / source.name).read_text(encoding="utf-8") == translate(expected)
    elif source.name == "Hud.lua":
        assert (wolkara / source.name).read_text(encoding="utf-8") == translate(protect_hud(source.read_text(encoding="utf-8")))
    elif source.name == "Actions.lua":
        assert (wolkara / source.name).read_text(encoding="utf-8") == actions(translate(protect_cooldowns(source.read_text(encoding="utf-8"))))
    elif source.name in ("Picker.lua", "Turn.lua"):
        fn = picker if source.name == "Picker.lua" else turn
        assert (wolkara / source.name).read_text(encoding="utf-8") == fn(translate(source.read_text(encoding="utf-8")))
    elif source.name == "Chat.lua":
        assert (wolkara / source.name).read_text(encoding="utf-8") == translate(source.read_text(encoding="utf-8")).replace("F12", "F11")
        assert 'local OPEN_KEY = "F11"' in (wolkara / source.name).read_text()
    elif source.suffix == ".lua":
        assert (wolkara / source.name).read_text(encoding="utf-8") == translate(source.read_text(encoding="utf-8"))
    else:
        assert (wolkara / source.name).read_bytes() == source.read_bytes(), source.name
assert "ui = { scale = 170 }" in (wolkara / "Core.lua").read_text()
assert "hideBars = true" in (wolkara / "Core.lua").read_text()
for filename, labels in {
    "Shortcuts.lua": ('"Bags"', '"Spells"', '"Map"'),
    "Objectives.lua": ('"Quests (%d)  %s"', '"Ready to turn in"'),
    "Chat.lua": ('"Chat"', '"System"', '"Hide"'),
    "Settings.lua": ('"Mobile UI"', '"Reset Positions"'),
}.items():
    content = (wolkara / filename).read_text(encoding="utf-8")
    assert all(label in content for label in labels), filename
toc = (wolkara / "WolkaraRoue.toc").read_text()
assert toc.index("Core.lua") < toc.index("WolkaraSetup.lua") < toc.index("Free.lua")
assert "## OptionalDeps: SPTouchBars, Tactara" in toc
assert "sp_install_tactara_if_absent" in cdn
assert "settings.count > 0 and settings.turn == true" in (wolkara / "Turn.lua").read_text()
assert (wolkara / "WolkaraSetup.lua").read_bytes() == (Path(__file__).resolve().parents[1] / "WolkaraSetup.lua").read_bytes()
tactara = root / "addon/Tactara"
assert (tactara / "Tactara.toc").is_file() and (tactara / "LICENSE").is_file()
for f in (root / ".tactara/Tactara").rglob("*"):
    if f.is_file():
        assert (tactara / f.relative_to(root / ".tactara/Tactara")).read_bytes() == f.read_bytes()
action_source = (wolkara / "Actions.lua").read_text()
assert 'button:SetAttribute("clickbutton", target)' in action_source
assert 'button:SetAttribute("clickbutton", nil)' in action_source
assert all(name in action_source for name in ("TactaraMainButton", "TactaraAoEButton", "TactaraInterruptButton"))
for old in ("SPTouchBars", "SPMobileCombat"):
    metadata = (root / f"addon/SlashplayedLegacyHUD/{old}.toc").read_text().splitlines()
    assert any(line.startswith("## SavedVariablesPerCharacter:") for line in metadata)
    assert all(line.startswith("## ") for line in metadata)
assert '[names addObject:@"WolkaraRoue"]' in cdn
assert "addon/WolkaraRoue" in kit

for toc in (root / "addon").glob("*/*.toc"):
    if toc.parent.name not in {"SPMobileCombat", "SPTouchBars", "WolkaraRoue"} and not toc.parent.name.startswith("Hekili"):
        continue
    for raw in toc.read_text(encoding="utf-8-sig").splitlines():
        entry = raw.strip().replace("\\", "/")
        if entry and not entry.startswith("#"):
            assert (toc.parent / entry).is_file(), f"{toc}: missing {entry}"

if len(sys.argv) > 2:
    with ZipFile(sys.argv[2]) as archive:
        assert archive.testzip() is None
        names = set(archive.namelist())
        assert archive.read("kit.json").strip() == b'{"version":"1.5.1"}'
        for platform in ("ios", "xros"):
            base = f"{platform}/Slashplayed.app/"
            assert plistlib.loads(archive.read(base + "Info.plist"))["CFBundleIdentifier"] == "@BUNDLE_ID@"
            assert {base + name for name in (
                "slashplayed", "PlugIns/SPJitHelper.appex/SPJitHelper",
                "licenses/SlashplayedEnhanced-MIT.txt", "licenses/Touchbars-MIT.txt",
                "addons/SPMobileCombat/SPMobileCombat.lua", "addons/SPMobileCombat/Menu.lua",
                "addons/SPMobileCombat/Windows.lua",
                "addons/SPTouchBars/SPTouchBars.tga",
                "addons/Hekili/LICENSE", "addons/Hekili/LICENSE-wowsims.txt",
            )} <= names
            if platform == "ios":
                for addon in ("WolkaraRoue", "SlashplayedLegacyHUD"):
                    for file in (root / "addon" / addon).iterdir():
                        assert archive.read(base + f"addons/{addon}/{file.name}") == file.read_bytes()
                for f in tactara.rglob("*"):
                    if f.is_file():
                        assert archive.read(base + "addons/Tactara/" + f.relative_to(tactara).as_posix()) == f.read_bytes()
                for name in ("LICENSE", "NOTICE.md"):
                    bundled = "WolkaraForever-MIT.txt" if name == "LICENSE" else "WolkaraForever-NOTICE.md"
                    assert archive.read(base + "licenses/" + bundled) == (root / ".wolkara" / name).read_bytes()
            else:
                assert base + "addons/WolkaraRoue/WolkaraRoue.toc" not in names
            for toc in (root / "addon").glob("Hekili*/*.toc"):
                assert base + "addons/" + toc.relative_to(root / "addon").as_posix() in names
        assert not any(re.search(r"(^|/)(WTF|Cache|Data)/", n, re.I) for n in names)

assert 'SPLayaRuntime.shared.decide' in (root / 'apps/client/spgameai.swift').read_text()
assert 'cpuAndNeuralEngine' in (root / 'apps/client/SPLayaRuntime.swift').read_text()
assert 'LAYA FILE' in event and 'AI INPUT' in event

assert 'SPP2PRuntime.swift' in (root / 'apps/client/build-launcher.sh').read_text()
assert 'sp_p2p_capture(cb, tex)' in (root / 'shims/appkit/sphover.m').read_text()
assert 'sp_p2p_enable(NO)' in event and 'tryP2P:' in event
assert 'recordMove:' in (root / 'apps/client/SPP2PRuntime.swift').read_text()

assert 'local function unavailable(code)' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'AI telemetry: state unavailable reason' in event

assert 'local function spReadHealthPercent(unit)' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'AI HP LOCK' in event and 'AI TGT LOCK' in event

assert 'local function spDisplayHealth(bar, current, capacity)' in (wolkara / "Hud.lua").read_text()
assert 'spDisplayHealth(frame.health, rawHealth, rawMaxHealth)' in (wolkara / "Hud.lua").read_text()
preview_source = event.split('- (void)previewP2P:',1)[1].split('- (void)pollDirect:',1)[0]
assert 'predictFrame:completion:' in preview_source
assert 'strong.action(' not in preview_source and 'recordMove:' not in preview_source
assert 'sp_ai_nav_allowed(decision' in event and 'F12 BIND' in event
assert '@"ATTACK"' not in preview_source and '@"CLICK"' not in preview_source
assert 'health unknown; combat disabled' in event and 'VIS FILE' in event
assert 'now - captured > 3.0' in preview_source and 'P2P INPUT' in event
assert 'STRAFE_LEFT' in event and 'STRAFE_RIGHT' in event
if sys.platform == "darwin" and len(sys.argv) == 2:
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        binary = str(Path(tmp) / "p2p-action-tests")
        subprocess.run(["xcrun", "swiftc", str(root / "apps/client/SPP2PRuntime.swift"),
                        str(Path(__file__).with_name("test_p2p_actions.swift")), "-o", binary], check=True)
        subprocess.run([binary], check=True)

assert 'local hp = spReadHealthPercent("player") or 255' in (root / "addon/SPHover/SPHover.lua").read_text()
assert 'sp_ai_health_known' in event and 'sp_ai_alive_hostile' in event
assert 'BOOL authorized = partial || _directRulesOnly' in event
assert 'partial ? @"HP?"' in event
