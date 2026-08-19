#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

# FANBAR_ARCHS accepts a space-separated list such as "arm64 x86_64".
build_arguments=(-c release)
# Some managed build environments already provide a stronger outer sandbox.
# Opting out of SwiftPM's nested sandbox avoids sandbox_apply failures there.
if [[ "${FANBAR_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    build_arguments+=(--disable-sandbox)
fi
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
mkdir -p "${bundle_path}/Contents/Frameworks"
mkdir -p "${bundle_path}/Contents/Resources"
mkdir -p "${bundle_path}/Contents/Library/LaunchDaemons"
cp "App/Info.plist" "${bundle_path}/Contents/Info.plist"
cp "${binary_path}/FanBar" "${bundle_path}/Contents/MacOS/FanBar"
cp "${binary_path}/FanBarHelper" "${bundle_path}/Contents/Resources/FanBarHelper"
ditto "${binary_path}/Sparkle.framework" \
    "${bundle_path}/Contents/Frameworks/Sparkle.framework"
# SwiftPM CLI products search beside the executable by default. Add the
# conventional app-bundle Frameworks location before signing the binary.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${bundle_path}/Contents/MacOS/FanBar"
cp "Assets/FanBar.icns" "${bundle_path}/Contents/Resources/FanBar.icns"
cp "App/local.fanbar.helper.plist" \
    "${bundle_path}/Contents/Library/LaunchDaemons/local.fanbar.helper.plist"
cp "THIRD_PARTY_NOTICES.md" "${bundle_path}/Contents/Resources/THIRD_PARTY_NOTICES.md"

# The root helper and main app must share a real Developer ID team.
sign_identity="${FANBAR_SIGN_IDENTITY:-Developer ID Application: JiangLin He (64S5F787T9)}"
sign_arguments=(--force)
# Hardened Runtime is required for Developer ID distribution. Ad-hoc builds
# omit it so local/CI binaries can load an ad-hoc Sparkle framework without a
# Team ID; release builds re-sign every component with the same Developer ID.
if [[ "${sign_identity}" != "-" ]]; then
    sign_arguments+=(--options runtime)
fi
# Development identities are intended for local testing and do not use the
# Developer ID timestamp service. Release builds retain their trusted timestamp.
if [[ "${sign_identity}" == Developer\ ID\ Application:* ]]; then
    sign_arguments+=(--timestamp)
fi

sparkle_framework="${bundle_path}/Contents/Frameworks/Sparkle.framework/Versions/B"
# Re-sign Sparkle's nested executables from the inside out while retaining its
# required XPC entitlements. The outer framework and app seals are applied last.
sparkle_signables=(
    "${sparkle_framework}/XPCServices/Downloader.xpc"
    "${sparkle_framework}/XPCServices/Installer.xpc"
    "${sparkle_framework}/Updater.app"
    "${sparkle_framework}/Autoupdate"
    "${bundle_path}/Contents/Frameworks/Sparkle.framework"
)
for signable in "${sparkle_signables[@]}"; do
    codesign "${sign_arguments[@]}" \
        --preserve-metadata=identifier,entitlements,flags \
        --sign "${sign_identity}" "${signable}"
done

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
