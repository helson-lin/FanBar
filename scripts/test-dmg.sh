#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

dmg_path="${1:-}"
if [[ -z "${dmg_path}" || ! -f "${dmg_path}" ]]; then
    print -u2 "Usage: scripts/test-dmg.sh <path-to-dmg>"
    exit 1
fi

mount_path="$(mktemp -d)"
cleanup() {
    hdiutil detach "${mount_path}" >/dev/null 2>&1 || true
    rmdir "${mount_path}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil verify "${dmg_path}"
codesign --verify --verbose=2 "${dmg_path}"
hdiutil attach -readonly -nobrowse -mountpoint "${mount_path}" "${dmg_path}" >/dev/null

app_path="${mount_path}/FanBar.app"
test -d "${app_path}"
test -L "${mount_path}/Applications"
test "$(readlink "${mount_path}/Applications")" = "/Applications"

codesign --verify --deep --strict --verbose=2 "${app_path}"
app_archs="$(lipo -archs "${app_path}/Contents/MacOS/FanBar")"
helper_archs="$(lipo -archs "${app_path}/Contents/Resources/FanBarHelper")"
expected_archs="${FANBAR_EXPECTED_ARCHS:-}"
if [[ -z "${expected_archs}" ]]; then
    [[ "${app_archs}" == "x86_64 arm64" || "${app_archs}" == "arm64 x86_64" ]]
    [[ "${helper_archs}" == "x86_64 arm64" || "${helper_archs}" == "arm64 x86_64" ]]
else
    [[ "${app_archs}" == "${expected_archs}" ]]
    [[ "${helper_archs}" == "${expected_archs}" ]]
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${app_path}/Contents/Info.plist")"
print "version=${version}"
print "app-architectures=${app_archs}"
print "helper-architectures=${helper_archs}"
"${app_path}/Contents/MacOS/FanBar" --telemetry-test
print "dmg-test=success"
