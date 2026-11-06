# `fanbar` command-line tool

`fanbar` lets terminals and scripts switch FanBar modes and read its status.
It ships inside the app at `FanBar.app/Contents/Helpers/fanbar`.

```sh
fanbar status                     # mode, preset, fans, temperatures
fanbar temps                      # CPU / GPU / SSD only
fanbar preset list                # * marks the selected preset
fanbar preset set performance     # built-in key, custom name, or token
fanbar preset set "Late Night"
fanbar mode curve                 # run the selected preset's curve
fanbar mode fixed 3200            # every fan at 3,200 RPM
fanbar mode auto                  # hand the fans back to macOS
```

## Options

| Option | Effect |
|---|---|
| `--hold` | For `preset set`, `mode curve` and `mode fixed`: keep the mode until it is changed again. Without it, macOS control comes back after the **Restore automatic control** timer in Settings, like a switch from the menu panel. |
| `--json` | Print the app's reply as JSON (`ok`, `message`, `status`, `presets`). |
| `--no-launch` | Fail with exit code 3 instead of starting FanBar when it is not running. |

`fanbar` tries the app's socket first and only then asks Launch Services
whether FanBar runs, because over SSH, from cron or from a background launchd
job Launch Services may not list the app at all. When FanBar is not running,
`fanbar` starts it in the background (`open -g`) and waits up to 20 seconds for
it to accept the command. An app that started moments ago (a login item, for
example) gets the rest of those 20 seconds instead of 2.

Every reply names the app copy that answered. When that is not the copy the
tool ships in (an old FanBar in Downloads, a test build), `fanbar` prints a
warning on stderr, so `--json` output stays parseable.

Exit codes: `0` success · `1` FanBar refused or failed the command ·
`2` usage error · `3` FanBar could not be reached.

Built-in presets always answer to their English keys (`silent`, `balanced`,
`performance`, `extreme`) whatever the interface language, so scripts keep
working after a language change. CLI messages are English for the same reason.
Failures reported by the app itself (for example a control service that has not
been approved) keep the app's wording.

## Installing on `PATH`

- **Settings:** open **Settings › General › Command Line & Automation › Command-line tool** and
  click **Install…**. This links `/usr/local/bin/fanbar` to the tool inside
  the app. FanBar first tries without privileges, because Intel Homebrew
  leaves `/usr/local/bin` writable by the user. If that fails, macOS asks once
  for an administrator password. The same row offers **Uninstall…**, and
  **Update Link…** when the link points to another copy of FanBar. FanBar
  never replaces a `fanbar` it did not create. The row asks you to move FanBar
  to Applications first when it runs from a read-only disk image or a
  translocated copy (an Applications folder on a writable external disk is fine),
  and it is hidden in builds without the tool (`swift run`).
  The row also reads the PATH of your login shell (`$SHELL -i -l -c env`, once
  per app run) and warns when another `fanbar` earlier on it would run instead,
  or when `/usr/local/bin` is not on it at all.
- **By hand:**

  ```sh
  sudo mkdir -p /usr/local/bin
  sudo ln -sf /Applications/FanBar.app/Contents/Helpers/fanbar /usr/local/bin/fanbar
  ```

- **Homebrew:** `brew install --cask helson-lin/fanbar/fanbar` links `fanbar`
  into Homebrew's `bin` (`/opt/homebrew/bin` on Apple Silicon,
  `/usr/local/bin` on Intel) through the cask's `binary` line. On Intel, a link
  installed earlier from Settings occupies the same path; uninstall it there
  first, or let Homebrew keep it with `--force`.

Every method links into the app rather than copying the tool, so Sparkle
updates the CLI together with the app.

## Raycast

Two integrations call `fanbar` from Raycast:

- **Extension** ([`integrations/raycast-extension`](../integrations/raycast-extension)):
  Switch Preset (custom presets included), Fan Status, Fixed RPM, Automatic,
  and a menu bar command with the CPU temperature. It is meant for the Raycast
  Store and will be submitted once a FanBar release ships the CLI. Until then,
  load it with `npm install && npm run dev` in that folder. See its
  [README](../integrations/raycast-extension/README.md).
- **Script Commands** ([`integrations/raycast`](../integrations/raycast)): no
  Node needed, but Raycast needs one manual Add Script Directory step and the
  preset dropdown lists only the built-in presets.

### Script Commands

[`integrations/raycast`](../integrations/raycast) holds these Script Commands:

| Script | Raycast command | What it does |
|---|---|---|
| `fanbar-preset.sh` | FanBar Preset | Pick silent, balanced, performance or extreme from a dropdown; optionally hold it until changed |
| `fanbar-fixed.sh` | FanBar Fixed RPM | Hold every fan at the RPM you type; optionally until changed |
| `fanbar-auto.sh` | FanBar Automatic | Hand the fans back to macOS |
| `fanbar-temperatures.sh` | FanBar Temperatures | `CPU 59° · GPU 52° · SSD 41°` in Raycast's root search, refreshed every minute |

**From FanBar (easiest):** in **Settings › General › Command Line & Automation › Raycast**, click
**Set Up in Raycast…**. FanBar copies the scripts to
`~/Library/Application Support/FanBar/Raycast`, puts that path on the clipboard
and opens Raycast. Then, once, in Raycast Settings › Extensions click **+** ›
**Add Script Directory**, press ⌘⇧G and paste. Raycast offers no way for
another app to add a script directory, so this one step stays manual. After
that, FanBar refreshes the folder from the app at every launch, so updates to
the scripts arrive with app updates. The row offers **Get Raycast…** when
Raycast is not installed, and is hidden in builds without the scripts.

**By hand:** add `integrations/raycast` (or a copy of it) the same way.

Assign hotkeys or aliases to the commands like any other. The extension above
replaces this setup with a one-click install once it is in the Raycast Store.

- Raycast does not load your shell profile, so the scripts do not rely on PATH.
  They use `$FANBAR_CLI` if set, then `/usr/local/bin/fanbar` (Settings),
  `/opt/homebrew/bin/fanbar` (Homebrew on Apple Silicon), and finally the tool
  inside `/Applications/FanBar.app`.
- The preset, fixed and automatic commands show the result or the error as
  Raycast's HUD, and exit non-zero on failure. Like the CLI, they start FanBar
  if it is not running.
- The temperatures command passes `--no-launch`, so its background refresh never
  reopens a FanBar you quit. It shows "FanBar is not running" instead.
- Custom presets are not in the dropdown, because Raycast's choices are fixed in
  the script. Copy `fanbar-preset.sh` to a new file in the same folder, such as
  `my-presets.sh`, then give it its own `@raycast.title` and list your presets
  as `data` entries, using the names `fanbar preset list` prints. Keep your
  changes in a file of your own: FanBar's launch-time refresh never touches
  files it did not write.
- That refresh also leaves alone any FanBar script you edited. It compares
  each file with what it last wrote (recorded in `.fanbar-scripts.json` in the
  same folder), and keeps edited files as they are, including when a newer
  FanBar retires a script. To get FanBar's version back, delete your copy and
  relaunch FanBar or click **Set Up in Raycast…**.

## Design

```
fanbar ──JSON over ~/Library/Application Support/FanBar/cli.sock──▶ FanBar.app ──XPC──▶ root helper
```

- **The tool never talks to the root helper.** The helper only trusts the
  signed app, restores macOS control when its last client disconnects, and has
  no notion of curves. A CLI that connected to it directly would lose control
  the moment it exited.
- **One request per connection.** Each side writes one newline-terminated JSON
  message, capped at 64 KB (`FanBarCLIContract` in `FanBarShared`). Requests
  carry a protocol version, and the app refuses a version it does not speak.
- **Socket path.** `sockaddr_un` holds about 104 bytes. When the
  Application Support path does not fit (long user names, relocated homes),
  both sides use `local.fanbar.cli.sock` in the per-user temporary directory
  (`confstr(_CS_DARWIN_USER_TEMP_DIR)`, mode `0700`) instead.
- **Timeouts.** The app spends at most `commandTimeout` on a request (the
  helper's worst-case write for eight fans, shared by both waits), and the CLI
  waits `replyTimeout`, 15 seconds longer. A slow switch is therefore never
  reported as a lost connection while it is still being applied.
- **Access control.** The socket's directory is created `0700` and the socket
  `0600`. Every connection's peer must also be the app's own user
  (`getpeereid`), so the CLI can do nothing that user could not already do from
  the menu panel.
- **Same code path as the panel.** `CLICommandHandler` calls the controller's
  own entry points (`setCoolingPreset`, `setCustomFixedRPM`, …), waits for the
  switch to finish, and only then reports success. `--hold` sets the session's
  restore duration to *Never*. Without it, the session returns to the Settings
  default.
- **Naming.** The executable cannot sit at `Contents/MacOS/fanbar`, because it
  would be the same file as `Contents/MacOS/FanBar` on a case-insensitive
  volume. For the same reason the SwiftPM product is `FanBarCLI`.
