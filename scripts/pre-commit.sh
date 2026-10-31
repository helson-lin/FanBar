#!/bin/zsh
# Refuses a commit unless style, lint, the unused-code scan and every test pass.
# Install once per clone with scripts/install-git-hooks.sh.
# Requires: brew install swiftlint swiftformat, plus npm ci in services/compatibility for CSS.
#
#   1. SwiftFormat and SwiftLint on staged Swift files (CI's rules: --strict, baseline).
#   2. Stylelint on staged CSS in the compatibility site.
#   3. scripts/find-unused-code.py: nothing in Sources may be left unused.
#   4. swift test: unit, integration and SwiftUI layout/render (UI) tests.
#
# Steps 3 and 4 run when the commit touches anything the Swift build can see, using the
# same rule as CI (scripts/ci-swift-relevant.sh). They test the working tree, so the hook
# refuses to run while Swift sources have changes that are not staged: otherwise a green
# run would describe files that are not in the commit.
set -euo pipefail

# The physical path: SwiftLint reports resolved paths, and its baseline only matches
# them when the working directory is resolved too (a clone under /tmp is /private/tmp).
cd -P "$(git rev-parse --show-toplevel)"

fail() {
  print -u2 "pre-commit: $1"
  exit 1
}

step() {
  print -u2 "pre-commit: $1"
}

staged=("${(@f)$(git diff --cached --name-only --diff-filter=ACMR)}")
staged=(${staged:#})
deleted=("${(@f)$(git diff --cached --name-only --diff-filter=D)}")
deleted=(${deleted:#})
(( ${#staged} + ${#deleted} )) || exit 0

swift_files=(${(M)staged:#*.swift})
css_files=(${(M)staged:#services/compatibility/web/*.css})

# Mirrors the ignore list in scripts/ci-swift-relevant.sh.
ignored='^(docs/|.*\.md$|LICENSE$|\.github/ISSUE_TEMPLATE/|services/compatibility/(web|test)/|\.github/workflows/(compatibility-service|download-badge|homebrew)\.yml$)'
swift_relevant=$(print -l -- "${staged[@]}" "${deleted[@]}" | grep -Ev "$ignored" || true)

if (( ${#swift_files} )); then
  # CI runs the versions pinned in scripts/lint-tools.env; a different local
  # version can pass here and fail there (or the reverse).
  source scripts/lint-tools.env
  [[ -d .build/lint-tools/bin ]] && path=("$PWD/.build/lint-tools/bin" $path)
  for tool in swiftlint swiftformat; do
    command -v "$tool" >/dev/null || fail "$tool is not installed (zsh scripts/install-lint-tools.sh)."
  done
  [[ "$(swiftformat --version)" == "$SWIFTFORMAT_VERSION" && "$(swiftlint version)" == "$SWIFTLINT_VERSION" ]] \
    || fail "SwiftFormat $(swiftformat --version) / SwiftLint $(swiftlint version) differ from CI's \
$SWIFTFORMAT_VERSION / $SWIFTLINT_VERSION; run 'zsh scripts/install-lint-tools.sh'."
  step "SwiftFormat"
  swiftformat --lint --quiet "${swift_files[@]}" \
    || fail "run 'swiftformat ${swift_files[*]}' and stage the result."
  step "SwiftLint"
  swiftlint lint --quiet --strict --baseline .swiftlint-baseline.json "${swift_files[@]}" \
    || fail "fix the SwiftLint violations above."
fi

if (( ${#css_files} )); then
  [[ -x services/compatibility/node_modules/.bin/stylelint ]] \
    || fail "Stylelint is missing; run 'npm ci' in services/compatibility."
  step "Stylelint"
  (cd services/compatibility && ./node_modules/.bin/stylelint "${css_files[@]#services/compatibility/}") \
    || fail "fix the Stylelint violations above (npm run lint:css -- --fix fixes most)."
fi

[[ -n "$swift_relevant" ]] || exit 0

unstaged=$(git diff --name-only -- 'Sources' 'Tests' 'Package.swift' 'Package.resolved')
untracked=$(git ls-files --others --exclude-standard -- 'Sources' 'Tests')
if [[ -n "$unstaged$untracked" ]]; then
  fail "these Swift sources are not staged, so the tests would not match the commit:
${unstaged}${unstaged:+${untracked:+
}}${untracked}
Stage them, or stash them with 'git stash push --keep-index --include-untracked'."
fi

step "unused code scan"
python3 scripts/find-unused-code.py >/dev/null || fail "remove the unused code listed above."

step "swift test (unit, integration and UI tests; takes a few minutes)"
log=$(mktemp -t fanbar-pre-commit)
if ! swift test >"$log" 2>&1; then
  grep -E "error:|failed|Fatal" "$log" | head -40 >&2 || true
  fail "tests failed; full log at $log"
fi
# XCTest's overall summary is the line with the most tests; swift-testing adds an empty one.
grep -E "Executed [0-9]+ tests, with" "$log" | sort -t' ' -k3 -n | tail -1 >&2 || true
rm -f "$log"
