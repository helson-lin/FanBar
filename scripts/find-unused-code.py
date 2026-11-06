#!/usr/bin/env python3
"""Fail when Sources declares something nothing in Sources uses.

A type, function, property or enum case whose name appears only at its own
declaration (comments aside) is unused. References from Tests do not count:
code that only tests reach is dead in the shipped app. Names that the system
or a framework calls, and hooks that exist only for tests, are listed with a
reason in scripts/unused-code-allowlist.txt.

The check is name-based, so a dead declaration that shares its name with a
live one elsewhere is not reported. Anything it does report is unused.

Usage: scripts/find-unused-code.py [repository root]
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
SOURCES = os.path.join(ROOT, "Sources")
ALLOWLIST = os.path.join(ROOT, "scripts", "unused-code-allowlist.txt")

# Requirements of Swift and SwiftUI protocols, always called by the runtime.
PROTOCOL_MEMBERS = {
    "body", "init", "deinit", "description", "id", "hash", "encode", "decode",
    "makeBody", "makeNSView", "updateNSView", "makeCoordinator", "rawValue", "title",
}

DECLARATION = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|private|fileprivate|internal|open|static|final|override|nonisolated|"
    r"mutating|lazy|weak|class|@MainActor)\s+)*"
    r"(struct|class|enum|protocol|actor|typealias|func|var|let|case)\s+([A-Za-z_]\w*)",
    re.M,
)


def load_allowlist():
    names = set()
    with open(ALLOWLIST, encoding="utf-8") as handle:
        for line in handle:
            name = line.split("#", 1)[0].strip()
            if name:
                names.add(name)
    return names


def swift_files(directory):
    for folder, _, files in os.walk(directory):
        for name in sorted(files):
            if name.endswith(".swift"):
                yield os.path.join(folder, name)


def main():
    allowed = load_allowlist()
    texts = {path: open(path, encoding="utf-8").read() for path in swift_files(SOURCES)}
    corpus = re.sub(r"//[^\n]*", "", "\n".join(texts.values()))
    counts = {}
    unused = []
    for path, text in texts.items():
        lines = text.splitlines()
        for match in DECLARATION.finditer(text):
            name = match.group(2)
            if len(name) < 3 or name in PROTOCOL_MEMBERS or name in allowed:
                continue
            line_number = text.count("\n", 0, match.start()) + 1
            line = lines[line_number - 1]
            # Overrides and Objective-C entry points are called by their superclass or the runtime.
            if "override" in line or "@objc" in line or "@IBAction" in line:
                continue
            if name not in counts:
                counts[name] = len(re.findall(r"\b%s\b" % re.escape(name), corpus))
            if counts[name] <= 1:
                unused.append((os.path.relpath(path, ROOT), line_number, match.group(1), name))
    if unused:
        print("Unused code in Sources (referenced only where it is declared):", file=sys.stderr)
        for path, line, kind, name in sorted(unused):
            print(f"  {path}:{line}: {kind} {name}", file=sys.stderr)
        print(
            "Delete it, or, if the system or a test calls it by convention, add the name with a reason "
            "to scripts/unused-code-allowlist.txt.",
            file=sys.stderr,
        )
        return 1
    print("No unused code found in Sources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
