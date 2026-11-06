#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title FanBar Temperatures
# @raycast.mode inline
# @raycast.refreshTime 1m
# @raycast.packageName FanBar

# Optional parameters:
# @raycast.icon 🌡️
# @raycast.description CPU, GPU and SSD temperatures in Raycast's root search.

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

# --no-launch: a background refresh must not reopen a FanBar you quit.
if ! output="$("${fanbar}" temps --no-launch 2>/dev/null)"; then
    echo "FanBar is not running"
    exit 0
fi
# "CPU:     58.8 °C" lines become one inline line: "CPU 59° · GPU 52° · SSD 41°".
echo "${output}" | awk '/°C/ { sub(":", "", $1); printf "%s%s %d°", sep, $1, $2 + 0.5; sep = " · " } END { print "" }'
