# FanBar Mac compatibility and test evidence

Last updated: October 11, 2026  
Canonical page: https://fanbar.jarin.me/compatibility

FanBar supports macOS 11 and later on Apple Silicon and Intel Macs that expose readable fan data through AppleSMC. Hardware sensors and fan behavior vary by model. This document separates public observations from maintainer verification.

## Evidence labels

- **Maintainer-verified:** the full checklist was run with an exact Mac model, macOS version, FanBar build, result, and date.
- **Community report:** a public GitHub issue records some behavior, but not the full checklist.
- **Retest needed:** an older report or known issue needs to be checked again on the current release.
- **Unlisted:** no sufficiently detailed public evidence is available. This does not mean unsupported.

## Maintainer-verified devices

None published yet. FanBar will not call a Mac model verified until a standardized result is recorded.

## Community-reported evidence

| Mac | System | What the source shows | Evidence limits | Date and source |
| --- | --- | --- | --- | --- |
| Mac mini, M6 | macOS 27; FanBar version not recorded | The reporter observed fan speed rising after switching from Automatic to Performance, Extreme, and Fixed modes. | Community report. The issue discusses a timed return to Automatic; it is not a full sensor-by-sensor test. | October 2, 2026 · [Issue #43](https://github.com/helson-lin/FanBar/issues/43) |
| MacBook Pro 16-inch, M2 Max | macOS 27; FanBar 0.5.0 | The issue confirms the app launches and runs long enough for CPU and memory use to be observed. | Community report. Manual RPM and curve control were not recorded; the performance report remains open. | October 9, 2026 · [Issue #63](https://github.com/helson-lin/FanBar/issues/63) |
| Apple Silicon Mac, identifier Mac15,8 | macOS 26.5; FanBar 0.4.3 | The report exercised the privileged helper and manual-control restore path. | Retest needed. This older version reported a shutdown restore crash. The issue is closed, but the current release needs a standardized retest. | August 20, 2026 · [Issue #6](https://github.com/helson-lin/FanBar/issues/6) |
| Mac mini (2014), Intel | macOS and FanBar version not recorded | The report confirms the app and its background/menu-bar integration were running on the device. | Community report. Temperature reading, RPM, fixed control, and curve control were not recorded. | October 7, 2026 · [Issue #50](https://github.com/helson-lin/FanBar/issues/50) |

## Standard verification checklist

1. App launches and remains stable.
2. CPU and GPU temperatures are readable.
3. SSD and battery temperatures are readable when the hardware exposes them.
4. Current, minimum, and maximum RPM are shown for every fan.
5. Fixed RPM changes fan output and stays inside the reported hardware range.
6. A temperature-based curve changes fan output as expected.
7. Automatic control is restored on quit, disconnect, timeout, and helper failure.
8. Sleep, wake, restart, and login-item behavior are stable.

Report a Mac at https://github.com/helson-lin/FanBar/issues/new/choose with the exact model, chip, macOS version, FanBar version, observed sensors, fan behavior, and test date.

## FAQ

### Does FanBar work on Apple Silicon?

Yes, on Apple Silicon Macs that expose readable fan data through AppleSMC. Hardware sensors and fan behavior vary by model, so check the evidence table for the exact Mac you use. A model not listed is unverified, not necessarily unsupported.

### Is FanBar free and open source?

Yes. FanBar is free under GPL-3.0, requires no account or subscription, and publishes the complete source code, including its privileged helper.

### Why does fan control need administrator permission?

Reading temperatures does not need manual fan control. Changing fan targets talks to AppleSMC through a signed privileged helper, so macOS asks for approval before that helper can run with the required access.

### What happens when FanBar quits?

FanBar attempts to restore macOS automatic fan control when the app quits, its helper connection is lost, a timed preset ends, or the helper reports a failure. Requested targets are also clamped to each fan's reported hardware range.
