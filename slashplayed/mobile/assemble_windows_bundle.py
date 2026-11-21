import argparse
import hashlib
import shutil
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


BUNDLE = "slashplayed-companion-windows-x86_64"
PHONE_FILES = {"ios/Slashplayed.app/slashplayed",
               "ios/Slashplayed.app/Frameworks/libspAppKit.dylib", "kit.json"}


def assemble(windows, kit, guides, output):
    with ZipFile(kit) as phone:
        if not PHONE_FILES.issubset(phone.namelist()) or phone.testzip() is not None:
            raise ValueError("Invalid iPhone device kit")
    with ZipFile(windows) as source:
        files = {}
        for member in source.infolist():
            name = member.filename.replace(chr(92), "/")
            parts = name.rstrip("/").split("/")
            if parts[0] != BUNDLE or any(part in {"", ".", ".."} or ":" in part for part in parts):
                raise ValueError(f"Unexpected Windows archive entry: {name}")
            if name.endswith("/"):
                continue
            if len(parts) < 2 or name.casefold() in files:
                raise ValueError(f"Duplicate or invalid Windows file: {name}")
            files[name.casefold()] = (name, member)
        if not any(f"{BUNDLE}/{name}" in files for name in ("slashplayed-cli.exe", "slashplayed-companion.exe")):
            raise ValueError("Windows installer executable missing")
        with ZipFile(output, "w", ZIP_DEFLATED) as combined:
            for name, member in files.values():
                with source.open(member) as src, combined.open(name, "w") as dst:
                    shutil.copyfileobj(src, dst)
            for item in [kit, *guides]:
                combined.write(item, f"{BUNDLE}/{item.name}")
    with ZipFile(output) as combined:
        if combined.testzip() is not None:
            raise ValueError("Combined archive failed validation")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Join a Windows installer and a patched iPhone kit")
    parser.add_argument("windows", type=Path)
    parser.add_argument("kit", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("guides", type=Path, nargs="*")
    args = parser.parse_args()
    assemble(args.windows, args.kit, args.guides, args.output)
    with args.output.open("rb") as archive:
        checksum = hashlib.file_digest(archive, "sha256").hexdigest()
    args.output.with_name("SHA256SUMS").write_text(f"{checksum}  {args.output.name}\n", encoding="ascii")
