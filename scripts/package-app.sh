#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

# TODO(maintainer): A Developer ID build that embeds the widget's App Group
# entitlement (com.apple.security.application-groups) normally needs an
# embedded provisioning profile (see WidgetExtension/FanBarWidget.entitlements
# and App/FanBar.entitlements). This script does not fetch or embed one --
# wire that up before shipping a Developer ID build that relies on the widget
# reading shared data.

# FanBar embeds a privileged launch daemon. The helper authenticates clients
# through their code-signing Team ID, so an ad-hoc package can never operate
# correctly: it may register in Login Items, but launchd/XPC will reject or
# fail to resolve the helper. Fail before doing the expensive build instead of
# producing an apparently installable but unusable app -- UNLESS the caller
# explicitly opts in with FANBAR_ALLOW_ADHOC=1, which CI uses to build a
# verification-only package that never operates the privileged helper.
sign_identity="${FANBAR_SIGN_IDENTITY:-Developer ID Application: JiangLin He (64S5F787T9)}"
if [[ "${sign_identity}" == "-" ]]; then
    if [[ "${FANBAR_ALLOW_ADHOC:-0}" != "1" ]]; then
        print -u2 "FanBar requires a real code-signing identity; ad-hoc signing (-) is unsupported because the privileged helper requires a Team ID. Set FANBAR_ALLOW_ADHOC=1 to build a verification-only ad-hoc package."
        exit 2
    fi
    print -u2 "WARNING: building an ad-hoc signed (FANBAR_ALLOW_ADHOC=1) package. The privileged helper cannot be authenticated by launchd/XPC in this build; it is for build verification only and must not be distributed to users."
fi

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

widget_build_arguments=(
    -project "WidgetExtension/FanBarWidgetExtension.xcodeproj"
    -scheme FanBarWidget
    -configuration Release
    # A scheme build resolves an active run destination and narrows the build
    # to that destination's architecture, which silently overrides ARCHS below
    # and yields a native-only appex inside an otherwise universal app. The
    # generic destination builds every architecture ARCHS asks for.
    -destination 'generic/platform=macOS'
    -derivedDataPath "${project_root}/.build/widget-xcode"
    CODE_SIGNING_ALLOWED=NO
)
if [[ -n "${FANBAR_ARCHS:-}" ]]; then
    widget_build_arguments+=(ARCHS="${FANBAR_ARCHS}")
fi
xcodebuild "${widget_build_arguments[@]}" build
widget_appex_path="${project_root}/.build/widget-xcode/Build/Products/Release/FanBarWidget.appex"

# Assemble in a temporary location so a failed build cannot leave a stale app.
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT
bundle_path="${temporary_root}/FanBar.app"
mkdir -p "${bundle_path}/Contents/MacOS"
mkdir -p "${bundle_path}/Contents/Frameworks"
mkdir -p "${bundle_path}/Contents/Resources"
mkdir -p "${bundle_path}/Contents/Library/LaunchDaemons"
mkdir -p "${bundle_path}/Contents/Library/LaunchServices"
mkdir -p "${bundle_path}/Contents/PlugIns"
cp "App/Info.plist" "${bundle_path}/Contents/Info.plist"
cp "${binary_path}/FanBar" "${bundle_path}/Contents/MacOS/FanBar"
cp "${binary_path}/FanBarHelper" \
    "${bundle_path}/Contents/Library/LaunchServices/local.fanbar.helper"
# Copy the entire built appex (Mach-O, Info.plist, compiled *.lproj widget
# gallery strings, and any other resources), not just its executable, so
# nothing xcodebuild produced is silently dropped.
ditto "${widget_appex_path}" \
    "${bundle_path}/Contents/PlugIns/FanBarWidget.appex"
# The build's own code signature cannot survive re-signing below; remove it
# explicitly rather than letting `codesign --force` paper over a stale seal.
rm -rf "${bundle_path}/Contents/PlugIns/FanBarWidget.appex/Contents/_CodeSignature"
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
cp "ThirdParty/Sparkle-LICENSE.txt" \
    "${bundle_path}/Contents/Resources/Sparkle-LICENSE.txt"

# The widget appex ships whatever version xcodebuild last stamped it with,
# which drifts from the app's version over time. Force it to match the app's
# Info.plist so the two can never disagree.
widget_info_plist="${bundle_path}/Contents/PlugIns/FanBarWidget.appex/Contents/Info.plist"
app_short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "App/Info.plist")"
app_build_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "App/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${app_short_version}" "${widget_info_plist}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${app_build_version}" "${widget_info_plist}"

# The root helper and main app must share a real Developer ID team.
sign_arguments=(--force)
# Hardened Runtime is required for Developer ID distribution, but an ad-hoc
# identity (FANBAR_ALLOW_ADHOC=1 verification builds) cannot load Sparkle
# under the hardened runtime, so it is only applied for real identities.
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
    --sign "${sign_identity}" \
    "${bundle_path}/Contents/Library/LaunchServices/local.fanbar.helper"
# Signing the appex bundle also signs its main executable with these
# entitlements, so the executable does not need a separate pass.
codesign "${sign_arguments[@]}" \
    --entitlements "WidgetExtension/FanBarWidget.entitlements" \
    --sign "${sign_identity}" \
    "${bundle_path}/Contents/PlugIns/FanBarWidget.appex"
codesign "${sign_arguments[@]}" \
    --entitlements "App/FanBar.entitlements" \
    --sign "${sign_identity}" "${bundle_path}"
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
