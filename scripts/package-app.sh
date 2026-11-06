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
# The packaging steps below add search paths to the executables with
# install_name_tool; reserve header space so that can never run out of room.
build_arguments=(-c release -Xlinker -headerpad_max_install_names)
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

# Single- and multi-architecture builds generate different Bundle.module
# accessors; the single-architecture one never searches Contents/Resources and
# traps on users' Macs (issue #86). Resources must go through FanBarResources.
if strings -a "${binary_path}/FanBar" | grep -qE "could not load resource bundle|unable to find bundle named"; then
    print -u2 "FanBar links SwiftPM's trapping Bundle.module accessor; use FanBarResources instead."
    exit 1
fi

# SwiftPM silently raises Package.swift's deployment target to the SDK's minimum
# (Xcode 27's SDK: macOS 12.0), producing binaries that cannot launch on the macOS
# version Info.plist promises. Every slice of every SwiftPM executable must match
# LSMinimumSystemVersion. The widget appex is exempt: WidgetKit needs macOS 14,
# and the app still launches where the widget cannot load.
minimum_system_version="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "App/Info.plist")"
for executable in FanBar FanBarCLI FanBarDiagnostics FanBarHelper; do
    deployment_targets=(${(f)"$(xcrun vtool -show-build "${binary_path}/${executable}" | awk '$1 == "minos" { print $2 }')"})
    if (( ${#deployment_targets} == 0 )); then
        print -u2 "Could not read the deployment target of ${executable}."
        exit 1
    fi
    for deployment_target in "${deployment_targets[@]}"; do
        if [[ "${deployment_target}" != "${minimum_system_version}" ]]; then
            print -u2 "${executable} targets macOS ${deployment_target}, but App/Info.plist declares LSMinimumSystemVersion ${minimum_system_version}. Build with the Xcode pinned by DEVELOPER_DIR in .github/workflows/macos-release.yml."
            exit 1
        fi
    done
done

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
cp "${binary_path}/FanBarDiagnostics" "${bundle_path}/Contents/MacOS/FanBarDiagnostics"
# The CLI cannot sit beside Contents/MacOS/FanBar: `fanbar` and `FanBar` are the
# same name on a case-insensitive volume. Homebrew links this path onto PATH.
mkdir -p "${bundle_path}/Contents/Helpers"
cp "${binary_path}/FanBarCLI" "${bundle_path}/Contents/Helpers/fanbar"
mkdir -p "${bundle_path}/Contents/Frameworks"
mkdir -p "${bundle_path}/Contents/Resources"
cp "scripts/export-diagnostics.command" "${bundle_path}/Contents/Resources/ExportDiagnostics.command"
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

# Swift concurrency ships with the OS only from macOS 12. Below that, executables
# weak-link @rpath/libswift_Concurrency.dylib: they launch, then crash at the first
# Task or await unless the back-deployment runtime travels inside the app. SwiftPM
# never embeds it, so copy the toolchain's runtime into Contents/Frameworks and add
# a search path to it for every executable that links it. /usr/lib/swift stays first
# in each search path, so macOS 12 and later keep using the system runtime.
autoload -Uz is-at-least
concurrency_runtime="$(xcrun --find swift)"
concurrency_runtime="${concurrency_runtime:h:h}/lib/swift-5.5/macosx/libswift_Concurrency.dylib"
embedded_concurrency_runtime="${bundle_path}/Contents/Frameworks/libswift_Concurrency.dylib"
for client in \
    "Contents/MacOS/FanBar" \
    "Contents/MacOS/FanBarDiagnostics" \
    "Contents/Helpers/fanbar" \
    "Contents/Library/LaunchServices/local.fanbar.helper"; do
    executable="${bundle_path}/${client}"
    # Any other back-deployed Swift runtime would be missing on older macOS in the
    # same way; stop rather than ship it unembedded.
    other_runtimes=(${(f)"$(otool -L "${executable}" | awk '$1 ~ /^@rpath\/libswift/ && $1 != "@rpath/libswift_Concurrency.dylib" { print $1 }')"})
    if (( ${#other_runtimes} > 0 )); then
        print -u2 "${client} links ${other_runtimes[*]}, which this script does not embed. Embed it the way libswift_Concurrency.dylib is embedded below."
        exit 1
    fi
    otool -L "${executable}" | grep -q "@rpath/libswift_Concurrency.dylib" || continue
    if [[ ! -f "${embedded_concurrency_runtime}" ]]; then
        if [[ ! -f "${concurrency_runtime}" ]]; then
            print -u2 "${client} needs the Swift concurrency back-deployment runtime, but ${concurrency_runtime} does not exist."
            exit 1
        fi
        # Each slice must load on the oldest supported macOS. Older slices record their
        # minimum in LC_VERSION_MIN_MACOSX; newer ones in LC_BUILD_VERSION (platform 1).
        for slice in ${(z)"$(lipo -archs "${concurrency_runtime}")"}; do
            slice_minimum="$(otool -arch "${slice}" -l "${concurrency_runtime}" | awk '
                /cmd LC_VERSION_MIN_MACOSX/ { legacy = 1; next }
                legacy && $1 == "version" { print $2; exit }
                $1 == "platform" { macos = ($2 == "1" || $2 == "MACOS") }
                macos && $1 == "minos" { print $2; exit }')"
            if [[ -z "${slice_minimum}" ]] || ! is-at-least "${slice_minimum}" "${minimum_system_version}"; then
                print -u2 "The ${slice} slice of ${concurrency_runtime} needs macOS ${slice_minimum:-unknown}, above LSMinimumSystemVersion ${minimum_system_version}."
                exit 1
            fi
        done
        cp "${concurrency_runtime}" "${embedded_concurrency_runtime}"
    fi
    for architecture in ${(z)"$(lipo -archs "${executable}")"}; do
        if ! lipo -archs "${embedded_concurrency_runtime}" | tr ' ' '\n' | grep -qx "${architecture}"; then
            print -u2 "The Swift concurrency runtime has no ${architecture} slice for ${client}."
            exit 1
        fi
    done
    # Contents/MacOS needs ../Frameworks; Contents/Library/LaunchServices needs ../../Frameworks.
    parent_directories=""
    for _ in ${(s:/:)${client:h}#Contents/}; do
        parent_directories+="../"
    done
    frameworks_search_path="@executable_path/${parent_directories}Frameworks"
    if ! otool -l "${executable}" | grep -qF "path ${frameworks_search_path} ("; then
        install_name_tool -add_rpath "${frameworks_search_path}" "${executable}"
    fi
done
# SwiftPM resources must travel with the executable; Bundle.module locates this
# bundle under the application's Resources directory.
ditto "${binary_path}/FanBar_FanBar.bundle" \
    "${bundle_path}/Contents/Resources/FanBar_FanBar.bundle"
cp "Assets/FanBar.icns" "${bundle_path}/Contents/Resources/FanBar.icns"
ditto "Assets/AppIcons" "${bundle_path}/Contents/Resources/AppIcons"
cp "App/local.fanbar.helper.plist" \
    "${bundle_path}/Contents/Library/LaunchDaemons/local.fanbar.helper.plist"
cp "THIRD_PARTY_NOTICES.md" "${bundle_path}/Contents/Resources/THIRD_PARTY_NOTICES.md"
# Raycast Script Commands, copied out by Settings › General › Raycast.
mkdir -p "${bundle_path}/Contents/Resources/Raycast"
cp integrations/raycast/*.sh "${bundle_path}/Contents/Resources/Raycast/"
chmod 755 "${bundle_path}/Contents/Resources/Raycast/"*.sh
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

# The embedded runtime must carry the same signature as the executables that load
# it, or library validation under the hardened runtime refuses it.
if [[ -f "${embedded_concurrency_runtime}" ]]; then
    codesign "${sign_arguments[@]}" --sign "${sign_identity}" "${embedded_concurrency_runtime}"
fi
codesign "${sign_arguments[@]}" --identifier "local.fanbar.diagnostics" \
    --sign "${sign_identity}" "${bundle_path}/Contents/MacOS/FanBarDiagnostics"
codesign "${sign_arguments[@]}" --identifier "local.fanbar.cli" \
    --sign "${sign_identity}" "${bundle_path}/Contents/Helpers/fanbar"
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

cp "scripts/export-diagnostics.command" "dist/FanBar-Diagnostics.command"
chmod +x "dist/FanBar-Diagnostics.command"
