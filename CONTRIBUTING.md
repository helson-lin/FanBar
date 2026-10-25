# Contributing to FanBar

Bug reports, documentation, translations, tests, and focused code changes are welcome. You can open issues in English, 简体中文, 繁體中文, or 日本語. Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Choose the right channel

- Search [existing issues](https://github.com/helson-lin/FanBar/issues) before opening a [bug report, feature request, or question](https://github.com/helson-lin/FanBar/issues/new/choose).
- For installation, permissions, and compatibility questions, start with [SUPPORT.md](SUPPORT.md).
- Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not disclose exploit details in public issues or pull requests.
- For a large feature or architecture change, describe the problem and proposed approach in an issue before implementing it. Small fixes and documentation corrections can go directly to a pull request.

## Development setup

Native development requires macOS, Xcode 26 or newer with its command-line tools selected, and Swift 6. Compatibility service development requires Node.js 24 or newer and npm.

```sh
git clone https://github.com/helson-lin/FanBar.git
cd FanBar
git switch -c my-change
swift build
zsh scripts/install-git-hooks.sh
```

The installer points `core.hooksPath` at `.githooks/`. Its pre-commit hook refuses a commit until SwiftFormat and SwiftLint pass on the staged Swift files, Stylelint passes on staged compatibility-site CSS, `scripts/find-unused-code.py` finds nothing unused in `Sources`, and `swift test` (unit, integration and SwiftUI layout/render tests) passes. The last two run when the commit touches anything the Swift build can see, and need every Swift change under `Sources` and `Tests` staged so the tests describe the commit. The test run takes a few minutes. CI runs the same unused-code scan and Stylelint check.

The main areas are `Sources/FanBar` (app), `Sources/FanBarShared` (shared models and localization), `Sources/FanBarUI` (shared UI), `Sources/FanBarHelper` and `Sources/AppleSMC` (privileged control), `Sources/FanBarWidget` and `WidgetExtension` (widget), and `services/compatibility` (report service). The service setup and local-only credentials are documented in its [README](services/compatibility/README.md).

### Running a packaged app

Use `scripts/package-app.sh` with a real signing identity for testing the privileged helper. The app and helper must share the signing team. Never commit certificates, provisioning profiles, credentials, or signing keys.

Package with the Xcode that `DEVELOPER_DIR` pins in `.github/workflows/macos-release.yml` (currently Xcode 26.0.1). Xcode 27's SDK raises SwiftPM's deployment target to macOS 12, which breaks macOS 11 support, so the script stops when any executable's minimum macOS differs from `LSMinimumSystemVersion`. Building and testing with a newer Xcode is fine.

An ad-hoc package is useful for build verification only; it cannot authenticate the privileged helper:

```sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
```

Generating icons with `scripts/generate-icons.sh` additionally requires ImageMagick (`magick`). Only regenerate icon assets when changing the artwork. You do not need signing credentials or hardware fan control to contribute documentation or run unit tests.

## Make a focused change

Keep changes limited to the reported problem, follow existing naming and component boundaries, and avoid unrelated formatting or generated files. Preserve accessibility, localization, supported macOS versions, and safe fallback behavior. Update relevant translations when changing user-facing copy.

Changes to the helper, SMC access, or fan curves must preserve authentication, input validation, hardware RPM bounds, and restoration of macOS automatic control. Use mocks for automated control tests; any hardware testing must be deliberate and recorded with the Mac model, macOS version, app version, and observed results. Distinguish accepted requests from verified physical fan behavior.

## Validate the affected area

For Swift changes, use the same checks as [CI](docs/code-quality.md):

```sh
brew install swiftlint swiftformat
swiftlint lint --strict --baseline .swiftlint-baseline.json
swiftformat --lint .
swift build -Xswiftc -warnings-as-errors -Xcc -Werror
python3 scripts/find-unused-code.py
swift test --enable-code-coverage
```

The unused-code scan reports any declaration in `Sources` that only its own declaration mentions; references from `Tests` do not count. Delete such code. A name the system or a test calls by convention (a delegate method, an `@main` type, a test hook) goes in `scripts/unused-code-allowlist.txt` with the reason.

Add a meaningful regression test when changing behavior. Do not expand the lint baseline to hide new violations. The [quality guide](docs/code-quality.md) explains coverage and the optional local service integration tests; describe any environment-dependent checks you could not run.

For compatibility service changes, run these in `services/compatibility` after completing its local setup:

```sh
npm ci
npm run check
npm run lint:css
npm test
npm run dry-run
```

For documentation or images, check links, image paths, language-specific content, and the rendered result. `git diff --check` should pass. A documentation-only change does not require running the entire native build.

## Submit a pull request

Open a pull request against `main`. Explain the user-visible problem, the resulting behavior, and the checks performed. Link an issue when one exists; include before/after screenshots for UI changes and identify any untested assumptions. Draft pull requests are welcome when you need feedback. Respond to review with focused follow-up commits.

Contributions are made under the repository's [GPL-3.0 license](LICENSE). Before a pull request can be merged, you need to accept the [Contributor License Agreement](CLA.md) once, by checking its box in the pull request template. You keep the copyright in your work; the agreement also lets the maintainer offer FanBar under other terms, such as a paid edition, while accepted contributions stay available under GPL-3.0. Preserve applicable third-party notices; do not add code or assets you cannot redistribute under their applicable terms.

## 中文提示

欢迎提交问题、翻译、文档和代码改进；四种界面语言都可以用于 Issue。请使用现有问题表单，较大改动先讨论，PR 中说明改动效果和验证方式。首次提交 PR 前，请阅读并同意 [贡献者许可协议（CLA）](CLA.md)，在 PR 模板中勾选即可；你保留贡献的版权，被合并的贡献会始终以 GPL-3.0 提供。安全漏洞请通过 [安全政策](SECURITY.md) 私下报告，社区行为问题请按 [行为准则](CODE_OF_CONDUCT.md) 联系维护者。ad-hoc 包仅用于构建验证，无法验证特权 Helper。克隆后请运行 `zsh scripts/install-git-hooks.sh` 启用提交钩子：提交前会依次检查 SwiftFormat、SwiftLint、Stylelint、未使用代码扫描和全部测试（含 UI 渲染测试），任何一项不通过都无法提交。
