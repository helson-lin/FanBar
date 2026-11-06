#!/bin/zsh
# Installs the SwiftFormat and SwiftLint versions pinned in scripts/lint-tools.env
# into .build/lint-tools/bin, verifying each download's sha256. The pre-commit
# hook prefers that directory over PATH; CI adds it to PATH.
set -euo pipefail
cd -P "$(git rev-parse --show-toplevel)"
source scripts/lint-tools.env

bin=.build/lint-tools/bin
mkdir -p "$bin"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() {
  local name=$1 url=$2 sha=$3
  curl -fsSL --retry 3 -o "$work/$name.zip" "$url"
  print "$sha  $work/$name.zip" | shasum -a 256 -c --quiet - \
    || { print -u2 "install-lint-tools: $name checksum mismatch"; exit 1; }
  unzip -oq "$work/$name.zip" -d "$work/$name"
}

fetch swiftformat \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" \
  "$SWIFTFORMAT_SHA256"
install -m 755 "$work/swiftformat/swiftformat" "$bin/swiftformat"

fetch swiftlint \
  "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
  "$SWIFTLINT_SHA256"
install -m 755 "$work/swiftlint/swiftlint" "$bin/swiftlint"

print "Installed swiftformat $("$bin/swiftformat" --version) and swiftlint $("$bin/swiftlint" version) in $bin."
