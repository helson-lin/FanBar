# FanBar

> A native macOS menu-bar utility for reading temperatures and managing fan cooling when you need it.

[English](README.md) · [简体中文](README.zh-CN.md)

FanBar supports macOS 11 Big Sur and later on Apple Silicon Macs and Intel Macs that expose readable AppleSMC fan data. It keeps everyday use safe and quiet with macOS automatic management, while making manual control available only after the signed control service is approved.

## Screenshots

The screenshots below show the Chinese interface. FanBar also includes English UI copy and can switch languages from **Settings → Language** without restarting.

![FanBar dark menu-bar popover](docs/screenshots/fanbar-menu-dark.jpg)

![FanBar settings](docs/screenshots/fanbar-settings-dark.jpg)

## Highlights

- **At-a-glance status** — Show the menu-bar icon, CPU temperature, average fan RPM, or both.
- **Live visualization** — Monitor CPU/GPU temperatures, a rolling ten-minute chart, and airflow motion that follows actual RPM.
- **Multiple cooling modes** — Restore macOS automatic control, set a target RPM, or choose Silent, Balanced, Performance, or Extreme presets.
- **Smart cooling** — Smoothly adjust fan output from 35% to 100% based on chip temperature, with a one-click off switch.
- **Safe fallback** — Targets are clamped to each fan's reported hardware range. On quit, disconnect, or service failure, FanBar attempts to restore macOS automatic control.
- **Native authorization flow** — First-run guidance explains why the control service is needed and opens the correct macOS settings page.
- **English and Simplified Chinese** — Choose System, English, or 简体中文 in FanBar Settings.

## Requirements

- macOS 11 Big Sur or later
- A Mac that exposes fan data through AppleSMC
- Xcode 26 and Swift 6 for local builds

> [!WARNING]
> AppleSMC is an undocumented hardware interface. Lowering fan speed can increase temperature; sustained high speed can increase noise, power use, and mechanical wear. Use manual control only when you understand the trade-offs, and prefer Automatic or Smart cooling for normal use.

## Usage

1. Launch FanBar and read the current temperature and fan speeds from the menu bar.
2. To control fans, choose **Enable fan control** and follow the macOS authorization prompt.
3. Choose a cooling preset, fixed RPM, or Smart cooling from the popover. Use **Automatic** at any time to return control to macOS.

Fixed RPM, presets, and Smart cooling can restore macOS control after 15 minutes, 30 minutes, or one hour.

### Change the interface language

Open **Settings → Language** and choose:

- **System** — follow the Mac's current language (Chinese or English)
- **English**
- **简体中文**

The setting is shared by the menu-bar popover, settings window, onboarding flow, status messages, and helper errors.

## Build and run

Clone the repository, then build a local app bundle:

```sh
zsh scripts/generate-icons.sh
FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_SIGN_IDENTITY=-` uses an ad-hoc signature for local testing. For distribution, replace it with a valid Developer ID Application identity.

### Create a local DMG

```sh
FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

The default output is `dist/FanBar-<version>.dmg`. To build a specific architecture:

```sh
FANBAR_ARCHS=arm64 FANBAR_APP_OUTPUT=dist/FanBar-arm64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-arm64.dmg zsh scripts/build-dmg.sh dist/FanBar-arm64.app

FANBAR_ARCHS=x86_64 FANBAR_APP_OUTPUT=dist/FanBar-x86_64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-x86_64.dmg zsh scripts/build-dmg.sh dist/FanBar-x86_64.app
```

Verify a DMG's signature, architecture, and installation structure with:

```sh
zsh scripts/test-dmg.sh dist/FanBar-0.4.0.dmg
```

## Architecture

FanBar separates the UI from privileged writes:

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

The helper does not expose arbitrary SMC writes. It only supports reading fans, setting a bounded target/preset/fraction, and restoring automatic control. macOS 13 and later use `SMAppService`; macOS 11–12 use a compatible launchd registration path.

## Continuous integration and releases

GitHub Actions validates the universal2 build on pushes and pull requests. Pushing a tag that matches the app version (for example `v0.4.0`) creates a GitHub Release.

```sh
git tag -a v0.4.0 -m "FanBar 0.4.0"
git push origin v0.4.0
```

## Acknowledgements and license

The Apple Silicon control sequence references the MIT-licensed [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for complete third-party attribution.
