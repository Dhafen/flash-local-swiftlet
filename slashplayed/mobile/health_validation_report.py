"""Summarize visible health checks against stable public telemetry."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path


VALIDATION = re.compile(
    r"AI health validation: (paired|unreadable|changing|unknown|unbracketed) "
    r"visual=(\d{1,3}) public=(\d{1,3})(?!\d)"
)


def summarize(lines):
    counts = Counter()
    ranges = Counter()
    false_ready = 0
    missed_low = 0
    absolute_error = 0
    maximum_overestimate = None
    for line in lines:
        match = VALIDATION.search(line)
        if not match:
            continue
        status, visual, public = match.groups()
        visual, public = int(visual), int(public)
        if (status == "paired" and visual <= 100 and public <= 100) or (
            status == "unreadable" and visual == 255 and public <= 100
        ):
            ranges["low" if public < 35 else "normal" if public >= 50 else "recovery"] += 1
        elif status in {"paired", "unreadable"}:
            counts["invalid"] += 1
            continue
        counts[status] += 1
        if status != "paired":
            continue
        error = visual - public
        absolute_error += abs(error)
        overestimate = max(0, error)
        maximum_overestimate = max(maximum_overestimate or 0, overestimate)
        false_ready += public < 50 <= visual
        missed_low += public < 35 <= visual
    return {
        "observations": dict(counts),
        "reference_coverage": dict(ranges),
        "false_ready_pairs": false_ready if counts["paired"] else None,
        "missed_low_pairs": missed_low if counts["paired"] else None,
        "maximum_overestimate_pp": maximum_overestimate,
        "mean_absolute_error_pp": round(absolute_error / counts["paired"], 2) if counts["paired"] else None,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    with args.log.open(encoding="utf-8", errors="replace") as stream:
        print(json.dumps(summarize(stream), indent=2))
