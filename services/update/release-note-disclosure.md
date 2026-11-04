<!-- Draft opening paragraph for the beta release notes that ships the update-feed switch.
     Not for docs/releases/ (release scripts read that folder). Paste into the release notes by hand. -->

**English**

FanBar now checks for updates through `update.getfanbar.com`, which forwards to the same GitHub appcast as before and counts update checks anonymously. By default it counts only how many checks each app version makes per day. FanBar asks once whether you want to share anonymous usage statistics (off by default); if you agree, once a week it also sends your install week, Mac model, macOS major version, chip architecture, and your country as seen by Cloudflare. No IP address, device ID, serial number, or app names are stored, and groups smaller than 5 are never published. You can change this any time in Settings under automatic updates, and turning off automatic update checks stops the automatic counting. Details: [PRIVACY.md](https://github.com/helson-lin/FanBar/blob/main/services/update/PRIVACY.en.md).

**简体中文**

FanBar 现在通过 `update.getfanbar.com` 检查更新。它会跳转到和以前相同的 GitHub appcast，并对更新检查做匿名计数。默认只统计每个应用版本每天的检查次数。FanBar 会询问一次是否共享匿名使用统计（默认关闭）；同意后，每周还会附带安装批次（周）、Mac 机型、macOS 主版本、芯片架构，以及 Cloudflare 判断的国家。不保存 IP 地址、设备 ID、序列号或应用名称，样本小于 5 的分组不会公开。你可以随时在设置的自动更新下方更改，关闭自动检查更新则不再自动计数。详情见 [PRIVACY.md](https://github.com/helson-lin/FanBar/blob/main/services/update/PRIVACY.md)。
