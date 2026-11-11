#!/usr/bin/env bash
# Probe the update check service the way Sparkle reaches it, without following the
# redirect first, so a Worker fault is told apart from a GitHub fault.
#
#   scripts/probe-update-service.sh [base-url]
#
# Exit codes: 0 healthy, 1 Worker fault, 2 appcast on GitHub unreachable.
# The User-Agent does not look like "FanBar/<version> Sparkle/<version>", so the
# probe is never counted as an update check.
set -u

BASE="${1:-https://update.getfanbar.com}"
EXPECTED="${EXPECTED_APPCAST_URL:-https://github.com/helson-lin/FanBar/releases/latest/download/appcast.xml}"
MAX_SECONDS="${PROBE_MAX_SECONDS:-3}"
UA="FanBar-UpdateProbe/1 (uptime check)"

fail() { echo "::error title=Update service::$1"; echo "FAIL: $1"; exit "${2:-1}"; }

headers="$(mktemp)"
trap 'rm -f "$headers"' EXIT

read -r code total < <(curl -sS -o /dev/null -D "$headers" -A "$UA" --max-time 10 \
  -w '%{http_code} %{time_total}\n' "$BASE/appcast.xml" 2>/dev/null || echo "000 0")

[ "$code" = "302" ] || fail "GET $BASE/appcast.xml returned HTTP $code, expected 302"

location="$(tr -d '\r' < "$headers" | awk 'tolower($1)=="location:" {print $2}')"
[ "$location" = "$EXPECTED" ] || fail "Location is '$location', expected '$EXPECTED'"

tr -d '\r' < "$headers" | grep -qi '^cache-control:.*no-store' \
  || fail "Cache-Control: no-store is missing, so an old appcast could be cached"

awk -v t="$total" -v m="$MAX_SECONDS" 'BEGIN { exit !(t <= m) }' \
  || fail "The redirect took ${total}s, over the ${MAX_SECONDS}s limit"

target_code="$(curl -sS -o /dev/null -L -A "$UA" --max-time 15 -w '%{http_code}' "$EXPECTED" 2>/dev/null || echo 000)"
[ "$target_code" = "200" ] || fail "The Worker is fine but the appcast on GitHub returned HTTP $target_code" 2

echo "OK: 302 in ${total}s, appcast reachable"
