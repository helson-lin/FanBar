#!/usr/bin/env python3
"""Embed translated HTML notes in a newly generated, archive-signed appcast."""
import argparse
from pathlib import Path
import plistlib
import sys
from xml.dom import minidom

LANGUAGES = ("en", "zh-Hans", "zh-Hant", "ja", "ru", "fr", "ko")


def localize(appcast: Path, notes_dir: Path, plist: Path) -> None:
    with plist.open("rb") as stream:
        if plistlib.load(stream).get("SURequireSignedFeed", False):
            raise ValueError("Signed feeds must not be modified after generate_appcast")
    notes = {}
    for language in LANGUAGES:
        path = notes_dir / f"{language}.html"
        content = path.read_text(encoding="utf-8").strip()
        if not content:
            raise ValueError(f"Empty release notes: {path}")
        notes[language] = content

    document = minidom.parse(str(appcast))
    items = document.getElementsByTagName("item")
    if len(items) != 1:
        raise ValueError("Expected exactly one update in the generated appcast")
    item = items[0]
    enclosures = item.getElementsByTagName("enclosure")
    if len(enclosures) != 1 or not enclosures[0].getAttribute("sparkle:edSignature"):
        raise ValueError("Expected one EdDSA-signed update archive")
    for child in list(item.childNodes):
        if child.nodeType == child.ELEMENT_NODE and child.tagName in ("description", "sparkle:releaseNotesLink"):
            item.removeChild(child)
            child.unlink()
    for language, content in notes.items():
        element = document.createElement("description")
        element.setAttribute("xml:lang", language)
        # Text nodes escape XML metacharacters; Sparkle reads their HTML string value.
        element.appendChild(document.createTextNode(content))
        item.appendChild(element)
    appcast.write_bytes(document.toxml(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appcast", type=Path)
    parser.add_argument("notes_dir", type=Path)
    parser.add_argument("plist", type=Path)
    args = parser.parse_args()
    try:
        localize(args.appcast, args.notes_dir, args.plist)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Cannot localize appcast: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
