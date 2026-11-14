import plistlib
import re
import sys
from pathlib import Path
from zipfile import ZipFile

root = Path(sys.argv[1])
event = (root / "shims/appkit/spevent.m").read_text()
cdn = (root / "apps/client/spcdn.m").read_text()
kit = (root / "scripts/release/device-kit.sh").read_text()
assert 'SP_PHONE_UI_RECTS' in (root / 'apps/client/launcher.m').read_text()
assert 'sp_mobile_end_interface' in event
assert '@interface SPMobileJumpButton' in event
assert 'event->modifierFlags = 0;' in event
assert 'sp_mobile_send_jump' in event
bars = (root / "addon/SPTouchBars/SPTouchBars.lua").read_text()
assert 'phoneLayout.enabled(db.phoneArc, SPPhoneTouchRects)' in bars
assert 'sp_mobile_touch_zone' in event, "Missing floating touch routing"
assert 'SPMobileCameraPad' not in event and '@"LOOK"' not in event
assert 'sp_mobile_release_look' in event and 'SPRightMouseDragged' in event
assert 'SPSoftKeyboardField' in event and 'sp_press_soft_escape:' in event
assert 'isEqual:@"enGB"] ? @"enUS"' in cdn
assert 'sp_install_hekili_if_absent' in cdn
assert 'SPMobileCombat' in cdn and 'SPMobileCombat' in kit
for toc in (root / "addon").glob("*/*.toc"):
    if toc.parent.name not in {"SPMobileCombat", "SPTouchBars"} and not toc.parent.name.startswith("Hekili"):
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
            for toc in (root / "addon").glob("Hekili*/*.toc"):
                assert base + "addons/" + toc.relative_to(root / "addon").as_posix() in names
        assert not any(re.search(r"(^|/)(WTF|Cache|Data)/", n, re.I) for n in names)
