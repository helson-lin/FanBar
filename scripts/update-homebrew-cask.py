#!/usr/bin/env python3
"""Pin the cask to a published stable release and hash its universal DMG."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?", help="Release tag (default: latest stable release)")
    args = parser.parse_args()
    repository = "helson-lin/FanBar"
    command = ["gh", "release", "view"]
    if args.tag:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
            parser.error("Expected a stable release tag such as v0.4.14")
        command.append(args.tag)
    command += ["--repo", repository, "--json", "tagName,isDraft,isPrerelease,assets"]
    release = json.loads(subprocess.check_output(command, text=True))
    tag = release["tagName"]
    if release["isDraft"] or release["isPrerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        parser.error("The cask must point to a published stable release")
    version = tag[1:]
    filename = f"FanBar-{version}.dmg"
    if not any(asset["name"] == filename for asset in release["assets"]):
        parser.error(f"Release {tag} has no universal DMG named {filename}")

    with tempfile.TemporaryDirectory(prefix="fanbar-homebrew-") as directory:
        subprocess.run(
            ["gh", "release", "download", tag, "--repo", repository,
             "--pattern", filename, "--dir", directory],
            check=True,
        )
        digest = hashlib.sha256(Path(directory, filename).read_bytes()).hexdigest()

    cask = Path(__file__).resolve().parents[1] / "Casks" / "fanbar.rb"
    source = cask.read_text()
    updated, versions = re.subn(r'^  version "[^"]+"$', f'  version "{version}"', source, flags=re.M)
    updated, checksums = re.subn(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{digest}"', updated, flags=re.M)
    if versions != 1 or checksums != 1:
        parser.error("Expected exactly one version and SHA-256 in Casks/fanbar.rb")
    cask.write_text(updated)
    print(f"Pinned FanBar {version}: {digest}")
    print("Review and commit Casks/fanbar.rb to main so brew update can pick it up.")


if __name__ == "__main__":
    main()
