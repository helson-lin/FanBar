#!/usr/bin/env python3
"""Refresh the DMG-only Shields endpoint from every GitHub release asset."""

import argparse
import json
from pathlib import Path
import subprocess


def dmg_download_count(pages):
    return sum(
        asset["download_count"]
        for page in pages
        for release in page
        for asset in release["assets"]
        if asset["name"].lower().endswith(".dmg")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="helson-lin/FanBar")
    parser.add_argument("--output", type=Path, default=Path("docs/badges/dmg-downloads.json"))
    args = parser.parse_args()

    response = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", f"repos/{args.repo}/releases?per_page=100"],
        check=True,
        capture_output=True,
        text=True,
    )
    downloads = dmg_download_count(json.loads(response.stdout))
    badge = {
        "schemaVersion": 1,
        "label": "DMG downloads",
        "message": f"{downloads:,}",
        "color": "blue",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(badge, indent=2) + "\n", encoding="utf-8")
    print(f"DMG downloads: {downloads:,}")


if __name__ == "__main__":
    main()
