#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${project_root}"

dmg_path="${1:-}"
if [[ -z "${dmg_path}" || ! -f "${dmg_path}" ]]; then
    print -u2 "Usage: scripts/notarize-dmg.sh <path-to-dmg>"
    exit 1
fi

# notarytool waits for Apple's automated review; stapling makes the ticket
# available even when Gatekeeper cannot reach Apple's servers.
if [[ -n "${FANBAR_NOTARY_PROFILE:-}" ]]; then
    # Recommended for local releases: credentials remain in Keychain instead
    # of being exported into the shell environment.
    xcrun notarytool submit "${dmg_path}" \
        --keychain-profile "${FANBAR_NOTARY_PROFILE}" \
        --wait
else
    required_variables=(APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID)
    for variable_name in "${required_variables[@]}"; do
        if [[ -z "${(P)variable_name:-}" ]]; then
            print -u2 "Missing ${variable_name}; alternatively set FANBAR_NOTARY_PROFILE."
            exit 1
        fi
    done
    xcrun notarytool submit "${dmg_path}" \
        --apple-id "${APPLE_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --team-id "${APPLE_TEAM_ID}" \
        --wait
fi
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"
print "Notarized ${dmg_path}"
