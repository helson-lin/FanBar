#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

draft=0
replace_assets=0
for argument in "$@"; do
    case "${argument}" in
        --draft) draft=1 ;;
        --replace-assets) replace_assets=1 ;;
        -h|--help)
            print "Usage: scripts/release-local.sh [--draft] [--replace-assets]"
            exit 0
            ;;
        *)
            print -u2 "Unknown argument: ${argument}"
            exit 2
            ;;
    esac
done

required_commands=(codesign ditto gh git grep hdiutil lipo shasum swift xcrun)
for command_name in "${required_commands[@]}"; do
    command -v "${command_name}" >/dev/null || {
        print -u2 "Missing required command: ${command_name}"
        exit 1
    }
done

# Releases must describe one committed state. This gate prevents an uploaded
# binary from differing from the tag that users and Sparkle use to identify it.
if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "The working tree is not clean. Commit or stash changes before releasing."
    exit 1
fi

release_branch="${FANBAR_RELEASE_BRANCH:-main}"
current_branch="$(git branch --show-current)"
if [[ "${current_branch}" != "${release_branch}" ]]; then
    print -u2 "Release from ${release_branch}; current branch is ${current_branch}."
    exit 1
fi

gh auth status -h github.com >/dev/null

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' App/Info.plist)"
tag="v${version}"
repository="${FANBAR_GITHUB_REPOSITORY:-helson-lin/FanBar}"
sparkle_account="${FANBAR_SPARKLE_KEY_ACCOUNT:-FanBar}"
sparkle_root="${project_root}/.build/artifacts/sparkle/Sparkle"
generate_appcast="${sparkle_root}/bin/generate_appcast"

[[ "${build}" == <-> ]] || {
    print -u2 "CFBundleVersion must be an increasing integer; found ${build}."
    exit 1
}

ci_publish="$(gh variable get FANBAR_PUBLISH_FROM_CI \
    --repo "${repository}" \
    --json value \
    --jq .value 2>/dev/null || true)"
if [[ "${ci_publish:l}" == "true" ]]; then
    print -u2 "FANBAR_PUBLISH_FROM_CI=true; disable it before publishing locally to avoid two publishers."
    exit 1
fi

git fetch --tags origin
head_commit="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    tag_commit="$(git rev-list -n 1 "${tag}")"
    [[ "${tag_commit}" == "${head_commit}" ]] || {
        print -u2 "Tag ${tag} already points to ${tag_commit}, not HEAD ${head_commit}."
        exit 1
    }
fi

if gh release view "${tag}" --repo "${repository}" >/dev/null 2>&1 \
    && (( ! replace_assets )); then
    print -u2 "Release ${tag} already exists. Use --replace-assets only for a deliberate retry."
    exit 1
fi

swift package resolve --disable-sandbox
[[ -x "${generate_appcast}" ]] || {
    print -u2 "Sparkle generate_appcast was not resolved at ${generate_appcast}."
    exit 1
}
sparkle_public_key="$(
    "${sparkle_root}/bin/generate_keys" --account "${sparkle_account}" -p
)"
configured_public_key="$(
    /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' App/Info.plist
)"
[[ "${sparkle_public_key}" == "${configured_public_key}" ]] || {
    print -u2 "The ${sparkle_account} Sparkle key does not match App/Info.plist."
    exit 1
}

write_checksum() {
    local archive_path="$1"
    local archive_name="${archive_path:t}"
    (cd "${archive_path:h}" && shasum -a 256 "${archive_name}" > "${archive_name}.sha256")
}

package_signed_dmg() {
    local architecture="${1:-}"
    local app_output dmg_output
    if [[ -z "${architecture}" ]]; then
        export FANBAR_ARCHS="arm64 x86_64"
        unset FANBAR_APP_OUTPUT FANBAR_DMG_OUTPUT
        app_output="${project_root}/dist/FanBar.app"
        dmg_output="${project_root}/dist/FanBar-${version}.dmg"
        zsh scripts/package-app.sh
        zsh scripts/build-dmg.sh
        zsh scripts/notarize-dmg.sh "${dmg_output}"
        zsh scripts/test-dmg.sh "${dmg_output}"
    else
        app_output="${project_root}/dist/FanBar-${architecture}.app"
        dmg_output="${project_root}/dist/FanBar-${version}-${architecture}.dmg"
        FANBAR_ARCHS="${architecture}" \
            FANBAR_APP_OUTPUT="${app_output}" \
            zsh scripts/package-app.sh
        FANBAR_DMG_OUTPUT="${dmg_output}" \
            zsh scripts/build-dmg.sh "${app_output}"
        zsh scripts/notarize-dmg.sh "${dmg_output}"
        FANBAR_EXPECTED_ARCHS="${architecture}" \
            zsh scripts/test-dmg.sh "${dmg_output}"
    fi
    write_checksum "${dmg_output}"
    packaged_dmg="${dmg_output}"
}

package_signed_dmg
dmg_path="${packaged_dmg}"
checksum_path="${dmg_path}.sha256"
package_signed_dmg arm64
arm64_dmg="${packaged_dmg}"
package_signed_dmg x86_64
x86_dmg="${packaged_dmg}"

updates_root="$(mktemp -d)"
cleanup() { rm -rf "${updates_root}" }
trap cleanup EXIT
ditto "${dmg_path}" "${updates_root}/${dmg_path:t}"

download_prefix="https://github.com/${repository}/releases/download/${tag}/"
"${generate_appcast}" \
    --account "${sparkle_account}" \
    --download-url-prefix "${download_prefix}" \
    --link "https://github.com/${repository}" \
    --maximum-deltas 0 \
    "${updates_root}"

appcast_path="${project_root}/dist/appcast.xml"
cp "${updates_root}/appcast.xml" "${appcast_path}"
grep -q "sparkle:edSignature=" "${appcast_path}" || {
    print -u2 "Generated appcast is missing its EdDSA signature."
    exit 1
}

if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    git tag -a "${tag}" -m "FanBar ${version}"
fi
git push origin "${tag}"

release_files=(
    "${dmg_path}"
    "${checksum_path}"
    "${arm64_dmg}"
    "${arm64_dmg}.sha256"
    "${x86_dmg}"
    "${x86_dmg}.sha256"
    "${appcast_path}"
)
notes_file="${project_root}/docs/releases/v${version}.md"
if gh release view "${tag}" --repo "${repository}" >/dev/null 2>&1; then
    gh release upload "${tag}" "${release_files[@]}" \
        --repo "${repository}" \
        --clobber
    if [[ -f "${notes_file}" ]]; then
        gh release edit "${tag}" --repo "${repository}" --notes-file "${notes_file}"
    fi
else
    create_arguments=(
        "${tag}"
        "${release_files[@]}"
        --repo "${repository}"
        --verify-tag
        --title "FanBar ${version}"
    )
    if [[ -f "${notes_file}" ]]; then
        create_arguments+=(--notes-file "${notes_file}")
    else
        create_arguments+=(--generate-notes)
    fi
    if (( draft )); then create_arguments+=(--draft); fi
    gh release create "${create_arguments[@]}"
fi

print "Published FanBar ${version} (build ${build}) to ${repository}."
print "Appcast: https://github.com/${repository}/releases/latest/download/appcast.xml"
