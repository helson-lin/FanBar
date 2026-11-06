#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title FanBar Automatic
# @raycast.mode silent
# @raycast.packageName FanBar

# Optional parameters:
# @raycast.icon 🌀
# @raycast.description Hand the fans back to macOS.

set -o pipefail

# Raycast does not load your shell profile, so look for the tool directly:
# $FANBAR_CLI, then the Settings link, Apple Silicon Homebrew, the app bundle.
fanbar=""
for candidate in "${FANBAR_CLI:-}" /usr/local/bin/fanbar /opt/homebrew/bin/fanbar \
    /Applications/FanBar.app/Contents/Helpers/fanbar; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
        fanbar="${candidate}"
        break
    fi
done
if [[ -z "${fanbar}" ]]; then
    echo "fanbar not found. Install it in FanBar Settings › General."
    exit 1
fi

"${fanbar}" mode auto 2>&1 | tail -n 1
