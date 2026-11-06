#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title FanBar Preset
# @raycast.mode silent
# @raycast.packageName FanBar

# Optional parameters:
# @raycast.icon 🌀
# @raycast.description Run a FanBar cooling preset's curve.
# @raycast.argument1 { "type": "dropdown", "placeholder": "Preset", "data": [{ "title": "Silent", "value": "silent" }, { "title": "Balanced", "value": "balanced" }, { "title": "Performance", "value": "performance" }, { "title": "Extreme", "value": "extreme" }] }
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

hold=()
[[ "${2:-}" == "hold" ]] && hold=(--hold)
# The last line (result or error) becomes Raycast's HUD.
"${fanbar}" preset set "$1" "${hold[@]}" 2>&1 | tail -n 1
