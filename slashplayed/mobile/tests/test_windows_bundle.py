import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

from assemble_windows_bundle import assemble


class WindowsBundleTests(unittest.TestCase):
    def test_combines_windows_paths_with_verified_phone_kit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            windows, output = root / "windows.zip", root / "combined.zip"
            kit = root / "slashplayed-wolkara-device-kit.zip"
            folder = "slashplayed-companion-windows-x86_64"
            with ZipFile(windows, "w") as archive:
                archive.writestr(folder + "\\slashplayed-cli.exe", b"MZ")
                archive.writestr(folder + "\\licenses\\LICENSE.txt", b"notice")
            with ZipFile(kit, "w") as archive:
                archive.writestr("ios/Slashplayed.app/slashplayed", b"ios")
                archive.writestr("ios/Slashplayed.app/Frameworks/libspAppKit.dylib", b"shim")
                archive.writestr("kit.json", "{}")
            guide = root / "Installera.md"
            guide.write_text("Guide", encoding="utf-8")
            assemble(windows, kit, [guide], output)
            with ZipFile(output) as archive:
                self.assertEqual(archive.testzip(), None)
                self.assertEqual(archive.read(f"{folder}/slashplayed-cli.exe"), b"MZ")
                self.assertEqual(archive.read(f"{folder}/licenses/LICENSE.txt"), b"notice")
                self.assertEqual(archive.read(f"{folder}/{kit.name}"), kit.read_bytes())


if __name__ == "__main__":
    unittest.main()
