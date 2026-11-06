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
- Run `zsh scripts/install-lint-tools.sh` too: the hook refuses to run with a
  SwiftFormat or SwiftLint version other than the one CI pins in
  `scripts/lint-tools.env`.
- Never commit with `--no-verify`, and never unset `core.hooksPath`.
- If the hook cannot run (SwiftLint or SwiftFormat missing, Sparkle cannot be
  resolved, the build fails), fix the environment. Do not work around it, and do
  not submit code you could not build and test. If a check truly cannot run
  here, say so in the PR.
- The hook tests the working tree, so stage every Swift change under `Sources/`
  and `Tests/` before committing.

## Claude Code enforces these rules

`.claude/settings.json` runs `.claude/hooks/agent_guard.py` before every shell
command and file edit in Claude Code. It **denies** skipping or redirecting the
git hook, growing the lint baseline or the unused-code allowlist, new
`swiftlint:disable` markers, hand edits to generated contracts, and branch
protection changes. It **asks the maintainer** before pushing to `main`,
pushing release tags, merging, releasing, deploying the service, posting on
GitHub, or editing workflows, git hooks and the guard itself. Other agents do
not run it, so the rules above still apply to them. Test the guard with
`python3 -m unittest discover -s .claude/hooks`.

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

## Repository map

| Path | What it is |
| --- | --- |
| `Sources/FanBar` | Menu-bar app (SwiftUI + AppKit): `FanController`, `FanMenu`, settings, onboarding, compatibility, CLI server, Sparkle updates |
| `Sources/FanBarShared` | Code shared by app, helper, CLI and widget: XPC protocol, presets, localization and its catalogs |
| `Sources/FanBarUI` | UI shared by the app and the widget |
| `Sources/FanBarHelper` | Root helper reached over privileged XPC; the only thing that writes to the SMC |
| `Sources/AppleSMC` | C/ObjC IOKit bridge (excluded from SwiftLint/SwiftFormat) |
| `Sources/FanBarCLI` | `fanbar` command-line tool shipped in `FanBar.app/Contents/Helpers`; see [docs/cli.md](docs/cli.md) |
| `Sources/FanBarWidget`, `WidgetExtension` | Widget; the appex is built by `xcodebuild` from `WidgetExtension/FanBarWidgetExtension.xcodeproj` (XcodeGen spec in `project.yml`) and needs macOS 14 |
| `Sources/FanBarDiagnostics` | Standalone diagnostics tool for when the app will not open; never registers the helper, touches fans or uses the network |
| `Tests/FanBarTests`, `Tests/FanBarHelperTests` | XCTest |
| `App` | `Info.plist` (version numbers), entitlements, launchd helper plist |
| `contracts` | JSON schema and constants shared by the app and the compatibility service |
| `services/compatibility` | Compatibility report service (Cloudflare Worker + React console, Node 24) |
| `integrations/raycast`, `integrations/raycast-extension` | Raycast script commands and Store extension, both built on `fanbar` |
| `docs` | Quality gates, releasing, diagnostics, CLI, regression reviews, screenshots, bilingual release notes in `docs/releases/`; `docs/design/` holds local drafts and is git-ignored |
| `plans` | Self-contained implementation plans with a status table in `plans/README.md` |

Architecture: `FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC`. macOS 13+ registers the helper with `SMAppService`; macOS 11–12 use a launchd path. The helper accepts only XPC clients signed with its own team ID and the `local.fanbar.app` identifier, so an ad-hoc or unsigned build can never control fans. Package with the Xcode that `DEVELOPER_DIR` pins in `.github/workflows/macos-release.yml`; a newer SDK raises the deployment target and breaks macOS 11.

## Impact analysis

Before writing code, answer these and put the answers in the PR description:

1. **Control and safety** — Does it touch the helper, SMC access, curves, presets, sleep handling or the control path? Then which guarantees (hardware bounds, hand-back to Automatic, client authentication) could it affect, and which tests pin them?
2. **Compatibility** — Does it change `FanBarHelperProtocol`, `contracts/`, the `fanbar` commands or output, stored `UserDefaults` keys, or file formats (CSV logs, compatibility receipts)? Then how do an older helper, the deployed service, Raycast and existing user settings behave?
3. **Platforms** — Does it behave differently on macOS 11–13, Apple Silicon vs Intel, one vs two fans, or a Mac with no readable fan data?
4. **Surfaces** — Which of these show it: menu panel, settings, onboarding, menu bar item, widget, notifications, CLI, diagnostics, READMEs? Each one is part of the change.
5. **Languages** — Which strings are new or changed, in all seven languages?
6. **Out of scope** — What did you deliberately not change, and what could not be verified (hardware fan behavior, signed helper, a specific macOS version)?

The PR description then lists the user-visible problem, the resulting behavior, the impact answers, the tests added, the checks run, and anything not verified, with before/after screenshots for UI changes.

## Things that must change together

- **App ↔ helper XPC.** After an update the old root daemon can keep running, so the app may talk to an older helper. Never change the signature of an existing `FanBarHelperProtocol` method. A new method must tolerate a helper that never replies (the timeout path in `HelperClient`), and a new write must keep its reply timeout above `FanControlTiming.writeReplyTimeout`.
- **Service contracts.** `contracts/service-constants.json` and the copies of `contracts/mac-model-names.json` (in `Sources/FanBar/Resources/` and `services/compatibility/web/src/lib/`) are generated. Change the constants in `services/compatibility/src/policy.ts`, run `npm run schema` in `services/compatibility`, then update `Sources/FanBarShared/ServiceContract.swift`. `npm run check` and `ServiceContractTests` fail on drift; a server-only change makes the app reject every upload.
- **CLI.** `fanbar` commands and output are used by `integrations/raycast*` and documented in `docs/cli.md` and the READMEs. Update them together.
- **Versions.** `CFBundleShortVersionString` and `CFBundleVersion` in `App/Info.plist` are the single source; the helper reads the enclosing app's build at launch. Bump them only for a release.

## Product rules

- **Be honest about state.** Distinguish a read failure, a legitimate zero and missing data; never fill a gap with zero or another device's reading. A displayed name and its value must come from the same source (see [docs/regression-review.md](docs/regression-review.md)).
- **Supported platforms are part of the product.** macOS 11 and later, Apple Silicon and Intel.
- **Seven interface languages:** System, English, 简体中文, 繁體中文, 日本語, Русский, Français. Switching applies live, without a restart.
- **No accounts, ads or telemetry by default.** Compatibility and diagnostic uploads are opt-in; respect `services/compatibility/PRIVACY.md`.
- **Name and icon are not GPL.** Do not reuse the FanBar name or icon in derived assets.

## Swift pitfalls

- Gate newer APIs with `#available` and keep the macOS 11 branch working. A newer SF Symbol renders as nothing on older systems, so add it to `FanBarSymbols` with a fallback and a test per OS branch.
- Load bundled resources through `FanBarResources`, never `Bundle.module`, which traps when the bundle is missing (single-architecture packaged builds, issue #86).
- Pass in what varies (OS version, clock, readings, `UserDefaults`), as `FanBarSymbols` and `FakeFanReadingSource` do, so the logic can be tested.
- `FanController`, `FanMenu` and `FanCurveEditorView` are already over the size limits. Put new behavior in a new file or type.
- User-facing text goes through `fanBarText("中文", "English")` / `fanBarFormat(...)`, Simplified Chinese first.

## Tests

Every behavior change gets a regression test that fails without the change. Pick the test by what you changed:

| Change | Test it with | Must cover |
| --- | --- | --- |
| Helper, SMC driver, fan writes | `Tests/FanBarHelperTests` against `FakeSMC` | input validation, clamping to each fan's min/max, rollback after a partial write, hand-back on disconnect, shutdown, sleep and failure |
| Fan/sensor reading, refresh loop | `FakeFanReadingSource` (see `FanControllerReadingTests`) | read failure, a legitimate 0, missing data, recovery; one sample per refresh |
| Curves, presets, temperature source | plain unit tests (`FanCurve*Tests`, `CustomCoolingPresetTests`, `CPUSensorSelectionTests`) | threshold boundaries, fallback when a sensor is missing, the text shown next to the value |
| Panel and settings logic | extract the decision from the view and test it (`PanelDiskOverviewTests`, `PanelThermalTests`) | every state in `.impeccable.md`: normal, high, very high, single fan, no fan data, overheat, helper not approved, mode switch failed |
| CLI | `CLICommandHandlerTests`, `CLIServerTests` | parsing, output format, errors |
| OS-dependent behavior | pass the OS version in (`FanBarSymbolsTests`) | each macOS branch, including 11 |
| User-facing text | `*CatalogTests`, `TraditionalChineseConverterTests` | every new English key in each catalog |
| Service contract | `ServiceContractTests`; `npm test` in `services/compatibility` | client constants equal `contracts/service-constants.json` |

- Tests must pass on GitHub's macOS VMs, which have no SMC fans. Never drive real fans from tests, and pin Reduce Motion, system language, `UserDefaults` and other host state.
- Name tests after the behavior they pin (`testStartupDiskFullWarningSurvivesLargeExternalVolume`), not the method they call.
- `CompatibilityServiceIntegrationTests` skips unless `FANBAR_COMPATIBILITY_TEST_SERVICE_URL` points at a local Worker; run it when you change the upload path.
- For the compatibility service, run `npm ci && npm run check && npm test && npm run dry-run` in `services/compatibility`.

## Coverage

- The gate counts only executable lines a PR adds to `Sources/`, and applies once there are at least 5. Check with the last two commands in the block above.
- SwiftUI/AppKit view bodies are near 0% and are not expected to be covered. If a change is mostly view code and misses the gate, move the logic (formatting, thresholds, state selection) into a testable type instead of writing hollow tests.
- Compare total coverage only between runs on the same environment. CI (about 32%) is the reference; a real Mac reads live SMC keys and takes other branches.
- Never lower the threshold or exclude files to pass. Details: [docs/code-quality.md](docs/code-quality.md).

## UI motion

- Respect Reduce Motion, Reduce Transparency and VoiceOver labels. The 2-second refresh changes values and colors only; it never moves elements or animates readings.
- Do not animate the popover's height: `FanMenu.updateContentHeight` resizes without interpolation because `NSPopover` resizing stutters. Rejected and pending motion ideas are in [plans/README.md](plans/README.md).
- Check light and dark appearance and at least one non-English language.

## Debugging fan and sensor problems

- Ask for an in-app diagnostic upload (Settings → Device Compatibility) or, when the app will not open, the output of `FanBar-Diagnostics.command`. See [docs/diagnostics.md](docs/diagnostics.md).
- A successful XPC reply does not mean the fan responded. Compare the target, the read-back value, the hand-back result and the helper events.
- Check which helper build is running (`getBuildVersion`) before trusting a log; a daemon from before an update reports its old build.
- After fixing a data or display regression, record root cause, fix and the pinning tests in [docs/regression-review.md](docs/regression-review.md).

## Releases and docs

- Releases (version bump, `scripts/release-local.sh`, Homebrew cask) are the maintainer's job; see [docs/releasing.md](docs/releasing.md).
- Release notes in `docs/releases/` are bilingual: headings read `### 新功能 / New Features`, and each bullet is a Chinese paragraph followed by its English translation. Sparkle shows only the fixes, security and features sections (`scripts/extract-update-notes.sh`), so keep install links in `### 安装 / Install`.
- Never commit certificates, provisioning profiles, notarization credentials, Sparkle keys or `.env` files, and never regenerate the Sparkle key.
