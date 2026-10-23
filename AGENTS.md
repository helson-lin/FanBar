# Agent rules for FanBar

These rules apply to every coding agent and automated contributor working in
this repository. [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/code-quality.md](docs/code-quality.md) hold the details; this file holds
what must not be skipped.

## Merging is gated

`main` is protected and enforced for admins. A pull request cannot merge until
these GitHub Actions checks pass:

- `SwiftLint + SwiftFormat`
- `Build (0 warnings) + tests + coverage` (build with warnings as errors, every
  test, and at least 60% coverage of the lines a PR adds to `Sources/`)

Documentation-only changes skip both, which counts as a pass.

- Never change branch protection, required checks or workflows to get a change
  merged.
- Never grow `.swiftlint-baseline.json` or `scripts/unused-code-allowlist.txt`
  to hide a new finding, and never add a `swiftlint:disable` marker to new code.

## Commits go through the hook

- In a fresh clone, run `zsh scripts/install-git-hooks.sh` before the first
  commit. Check with `git config --get core.hooksPath`, which must print
  `.githooks`.
- Never commit with `--no-verify`, and never unset `core.hooksPath`.
- If the hook cannot run (SwiftLint or SwiftFormat missing, Sparkle cannot be
  resolved, the build fails), fix the environment. Do not work around it, and do
  not submit code you could not build and test. If a check truly cannot run
  here, say so in the PR.
- The hook tests the working tree, so stage every Swift change under `Sources/`
  and `Tests/` before committing.

## What usually fails CI

- **Translations.** Every `fanBarText` / `fanBarFormat` call needs a matching
  English key in `FrenchCatalog`, `JapaneseCatalog` and `RussianCatalog`
  (`Sources/FanBarShared`). The catalog tests scan every call site. Traditional
  Chinese is converted from the Simplified string automatically.
- **Complexity.** `cyclomatic_complexity` is capped at 10. When a branch pushes
  a function over, extract a helper function or a small type.
- **Diff coverage.** `FanController` and SwiftUI views are hard to test. Put new
  decision logic in a pure type or a static function, and test that.
- **Warnings.** The build treats Swift and C warnings as errors, including
  Swift 6 concurrency diagnostics.

Before pushing, run the same checks as CI:

```sh
swiftlint lint --strict --baseline .swiftlint-baseline.json
swiftformat --lint .
swift build -Xswiftc -warnings-as-errors -Xcc -Werror
python3 scripts/find-unused-code.py
swift test --enable-code-coverage
python3 scripts/coverage-report.py --base origin/main --min-diff 60
```

## Fan control safety

- Changes to `Sources/FanBarHelper`, `Sources/AppleSMC` or the curve loop must
  keep input validation, hardware RPM bounds and the hand-back to macOS
  automatic control (on disconnect, shutdown, sleep and failed writes).
- Do not hold fans in manual mode across system sleep. Sleep handling belongs in
  the root helper, which can delay sleep until the hand-back is done.
- Test control logic against `FakeSMC` or other fakes. An accepted SMC write is
  not proof the fans moved: report hardware results only with the Mac model,
  macOS and app versions, and what was observed.

## Acting outside the repository

Get the maintainer's explicit approval before posting to issues or pull
requests, pushing to a contributor's branch, merging, releasing, or changing
repository settings.

## UI work

Design context lives in [.impeccable.md](.impeccable.md): users, brand,
aesthetic direction, design principles, menu panel decisions, and the panel
critique checklist. Read it before any UI design, redesign or critique.
