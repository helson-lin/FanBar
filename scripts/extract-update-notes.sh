#!/bin/zsh
# Usage: extract-update-notes.sh <release-notes.md> <output.md>
#
# Sparkle shows the appcast item's release notes in its update window. The
# GitHub release notes also carry install links and a changelog link that mean
# nothing there, so keep only the sections that describe what changed:
# fixes, security, and features. Writes nothing when none are found.
set -euo pipefail

notes="$1"
output="$2"
[[ -f "${notes}" ]] || exit 0

awk '
    /^### / {
        keep = ($0 ~ /修复|安全|功能|Fixes|Security|Features/)
    }
    keep { print }
' "${notes}" > "${output}"

# Drop the file if it only contains whitespace so Sparkle shows no empty notes.
if ! grep -q '[^[:space:]]' "${output}"; then
    rm -f "${output}"
fi
