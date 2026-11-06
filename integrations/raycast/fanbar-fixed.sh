#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title FanBar Fixed RPM
# @raycast.mode silent
# @raycast.packageName FanBar

# Optional parameters:
# @raycast.icon 🌀
# @raycast.description Hold every fan at a fixed speed.
# @raycast.argument1 { "type": "text", "placeholder": "RPM, e.g. 3000" }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Until", "optional": true, "data": [{ "title": "Settings timer", "value": "timer" }, { "title": "Changed (hold)", "value": "hold" }] }

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

if [[ ! "$1" =~ ^[0-9]+$ ]]; then
    echo "Enter the speed as a whole number of RPM, e.g. 3000."
    exit 1
fi
hold=()
[[ "${2:-}" == "hold" ]] && hold=(--hold)
"${fanbar}" mode fixed "$1" "${hold[@]}" 2>&1 | tail -n 1
