#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

# FANBAR_ARCHS accepts a space-separated list such as "arm64 x86_64".
build_arguments=(-c release)
if [[ -n "${FANBAR_ARCHS:-}" ]]; then
    for architecture in ${(z)FANBAR_ARCHS}; do
        build_arguments+=(--arch "${architecture}")
    done
fi

swift build "${build_arguments[@]}"
binary_path="$(swift build "${build_arguments[@]}" --show-bin-path)"

# Assemble in a temporary location so a failed build cannot leave a stale app.
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT
bundle_path="${temporary_root}/FanBar.app"
mkdir -p "${bundle_path}/Contents/MacOS"
mkdir -p "${bundle_path}/Contents/Resources"
mkdir -p "${bundle_path}/Contents/Library/LaunchDaemons"
cp "App/Info.plist" "${bundle_path}/Contents/Info.plist"
cp "${binary_path}/FanBar" "${bundle_path}/Contents/MacOS/FanBar"
cp "${binary_path}/FanBarHelper" "${bundle_path}/Contents/Resources/FanBarHelper"
cp "Assets/FanBar.icns" "${bundle_path}/Contents/Resources/FanBar.icns"
cp "App/local.fanbar.helper.plist" \
    "${bundle_path}/Contents/Library/LaunchDaemons/local.fanbar.helper.plist"
cp "THIRD_PARTY_NOTICES.md" "${bundle_path}/Contents/Resources/THIRD_PARTY_NOTICES.md"

# The root helper and main app must share a real Developer ID team.
sign_identity="${FANBAR_SIGN_IDENTITY:-Developer ID Application: JiangLin He (64S5F787T9)}"
sign_arguments=(--force --options runtime)
if [[ "${sign_identity}" != "-" ]]; then
    # Apple notarization requires a trusted timestamp on Developer ID builds.
    sign_arguments+=(--timestamp)
fi

codesign "${sign_arguments[@]}" --identifier "local.fanbar.helper" \
    --sign "${sign_identity}" "${bundle_path}/Contents/Resources/FanBarHelper"
codesign "${sign_arguments[@]}" --sign "${sign_identity}" "${bundle_path}"
codesign --verify --deep --strict --verbose=2 "${bundle_path}"

mkdir -p "${project_root}/dist"
app_output_path="${FANBAR_APP_OUTPUT:-${project_root}/dist/FanBar.app}"
if [[ "${app_output_path}" != /* ]]; then
    app_output_path="${project_root}/${app_output_path}"
fi
mkdir -p "${app_output_path:h}"
rm -rf "${app_output_path}"
mv "${bundle_path}" "${app_output_path}"
print "Built ${app_output_path}"
