# Code quality gates

`.github/workflows/quality.yml` runs on every pull request and on `main`. The
rule is **gate new code, freeze old debt**: nothing here forces legacy files up
to a target, but anything a PR adds has to pass.

| Gate | Fails when | Run locally |
| --- | --- | --- |
| SwiftLint | a violation not in `.swiftlint-baseline.json` appears (warnings count, `--strict`) | `swiftlint lint --strict --baseline .swiftlint-baseline.json` |
| SwiftFormat | any file drifts from `.swiftformat` | `swiftformat --lint .` (fix: `swiftformat .`) |
| Build | the compiler emits any Swift or C warning | `swift build -Xswiftc -warnings-as-errors -Xcc -Werror` |
| Unused code | a declaration in `Sources/` is mentioned only where it is declared (references from `Tests/` do not count; framework entry points and test hooks are listed in `scripts/unused-code-allowlist.txt`) | `python3 scripts/find-unused-code.py` |
| Tests | any test fails | `swift test --enable-code-coverage` |
| Diff coverage | < 60% of executable lines added in `Sources/` are covered (only when the PR adds ≥ 5 such lines) | `python3 scripts/coverage-report.py --base origin/main --min-diff 60` |
| Stylelint (`compatibility-service.yml`) | compatibility-site CSS breaks `services/compatibility/.stylelintrc.json` | `npm run lint:css` in `services/compatibility` |

Tools: `zsh scripts/install-lint-tools.sh` installs the SwiftFormat and SwiftLint
versions CI uses (pinned in `scripts/lint-tools.env`) into `.build/lint-tools/bin`. The pre-commit hook refuses a
commit until SwiftFormat, SwiftLint (staged Swift), Stylelint (staged
compatibility-site CSS), the unused-code scan and `swift test` pass. Enable it
once per clone:

```sh
zsh scripts/install-git-hooks.sh
```

The scan and the tests run whenever the commit touches something the Swift
build can see (the same rule as `scripts/ci-swift-relevant.sh`). They check the
working tree, so the hook stops while Swift changes under `Sources/` or
`Tests/` are left unstaged; stage them or `git stash push --keep-index
--include-untracked` first.

## Legacy debt

- `.swiftlint-baseline.json` holds the violations that existed when the gate was
  introduced. After fixing some, shrink it with
  `swiftlint lint --write-baseline .swiftlint-baseline.json`. Never regenerate it
  to hide a new violation.
- Size rules (`file_length`, `type_body_length`, `function_body_length`,
  `cyclomatic_complexity`) report the current count in their message, so a
  baseline entry stops matching as soon as the file is edited. Those cases are
  marked inline with `swiftlint:disable` instead (`FanController`,
  `FanCurveEditorView`, `FanMenu`, a few long functions). Search for
  `swiftlint:disable` to find them; remove the marker when the code is split.

## Coverage snapshot

Total line coverage of `Sources/` is about **32% in CI** (October 2026). The CI
number is the one to track: it is reproducible and doesn't depend on hardware.

A real Mac reports about 33% for the same tests. The menu height test and
`FanControllerReadingTests` use `FakeFanReadingSource`, so the menu renders the
same way on GitHub's macOS runners (VMs without SMC fans). Other tests that
create a `FanController` still read the real SMC when it exists. The remaining
gap is in a few files whose paths depend on the environment:

- `SMCClient` (about 22% in CI vs 85% locally) decodes live SMC keys, which
  only exist on real hardware.
- `FanRotorView` animates from live RPM readings.
- `TemperatureFanCurve` and `FanBarLocalization` take different branches
  depending on the machine's state and system language, so either side can be
  higher.

Compare coverage numbers from the same environment only.

Curve math, widget snapshot and helper logic are well covered everywhere.
SwiftUI/AppKit view files are near 0%.

`FanBarHelperTests` runs the privileged helper against `FakeSMC`, an in-memory
key table that models per-fan mode keys with the `Ftst` unlock, the older Intel
`FS! ` bitmask and fpe2 values. It covers input validation, clamping to each
fan's limits, rollback after a partial write, and handing control back to macOS
on disconnect, shutdown and driver release. Only `AppleSMCKeyStore` (the IOKit
calls) and the XPC/code-signing plumbing stay untested.

The lcov file is uploaded as the `coverage-lcov` artifact of each run, so it
can feed Codecov or SonarCloud later without changing the test step.
