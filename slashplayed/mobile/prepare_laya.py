#!/usr/bin/env python3
"""Prepare real Laya Core ML weights and pre-tokenized game-state templates.
Run on a build host; no Python, network, or tokenizer needed on the phone.
The original model's interface is documented at charioteer/laya-mobile.
"""
import argparse
import itertools
import json
from pathlib import Path
import shutil
import zipfile

REPO = "charioteer/laya-mobile"
REVISION = "d8b837f"
WEIGHTS = "coreml/laya-fp16-512.mlpackage.zip"

def make_choices(tokenizer):
    def encode(s):
        return tokenizer.encode(s.replace("[MASK]", " "), add_special_tokens=False).ids
    entries = {}
    for candidate, hp, combat, target_hp in itertools.product(
        ("ATTACK", "TARGET"), ("low", "medium", "high"), ("combat", "peace"),
        ("low", "medium", "high")
    ):
        key = ":".join((candidate, hp, combat, target_hp))
        head = encode("choice question: Which action should a video game character take given the observed game state?")
        opts = [
            [50284] + encode(" " + candidate + ": " + (
                "use the combat rotation on the selected hostile non-player enemy" if candidate == "ATTACK"
                else "select a nearby hostile target instead of a missing or non-hostile target"))[:48],
            [50284] + encode(" WAIT: do nothing or let the character recover if action is not appropriate")[:48],
        ]
        ids = [50281] + head[:max(8, 192 - sum(map(len, opts)))] + [50282]
        markers = []
        for opt in opts:
            markers.append(len(ids))
            ids.extend(opt)
        ids.append(50282)
        state = f"Player health {hp}; {'in combat' if combat == 'combat' else 'not in combat'}; " + (
            f"selected living hostile enemy; enemy health {target_hp}." if candidate == "ATTACK"
            else "no valid living hostile target selected."
        )
        ids += encode(state)[:512-len(ids)-1] + [50282]
        assert len(ids) <= 512 and all(ids[m] == 50284 for m in markers)
        entries[key] = {"ids": ids, "markers": markers}
    assert len(entries) == 36
    return {"schema": 1, "entries": entries}

def main():
    from huggingface_hub import hf_hub_download
    from tokenizers import Tokenizer
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output / "SPModels" / "Laya"
    output.mkdir(parents=True, exist_ok=True)
    tokenizer_path = hf_hub_download(REPO, "tokenizer.json", revision=REVISION)
    package_zip = hf_hub_download(REPO, WEIGHTS, revision=REVISION)
    (output / "choices.json").write_text(json.dumps(make_choices(Tokenizer.from_file(tokenizer_path)), separators=(",", ":")))
    # Extract just the documented mlpackage directory, refusing traversal and symlinks.
    with zipfile.ZipFile(package_zip) as ar:
        for entry in ar.infolist():
            parts = Path(entry.filename).parts
            if not parts or ".." in parts or Path(entry.filename).is_absolute() or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Unsafe model archive entry")
            positions = [i for i, part in enumerate(parts) if part == "laya-fp16-512.mlpackage"]
            if not positions:
                continue
            dest = output / "laya.mlpackage" / Path(*parts[positions[0]+1:])
            if entry.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                with ar.open(entry) as src, dest.open("wb") as target:
                    shutil.copyfileobj(src, target)
    if not (output / "laya.mlpackage/Manifest.json").is_file():
        raise RuntimeError("Model archive layout mismatch")
    (output / "SOURCE.txt").write_text(f"{REPO}@{REVISION}\n{WEIGHTS}\nApache-2.0\nhttps://www.apache.org/licenses/LICENSE-2.0\n")
    print(output)

if __name__ == "__main__":
    main()
