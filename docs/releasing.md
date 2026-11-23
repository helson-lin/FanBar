# FanBar 发布配置

GitHub Actions 在普通提交和 Pull Request 上构建一个 ad-hoc 签名的 universal2
测试 DMG；推送 `v*` 标签时，额外执行 Developer ID 签名、Apple 公证、凭证装订，
并创建 GitHub Release。

## Repository secrets

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 中配置：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书及私钥导出的 `.p12`，完整内容进行 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码，可生成一段独立随机值 |
| `APPLE_ID` | Apple Developer 账户邮箱 |
| `APPLE_APP_PASSWORD` | 在 Apple ID 账户页面创建的 App 专用密码 |
| `APPLE_TEAM_ID` | `64S5F787T9` |

可选 Repository variable：

| Variable | 默认值 |
| --- | --- |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: JiangLin He (64S5F787T9)` |

推荐使用“钥匙串访问”导出 Developer ID Application 证书及其私钥，然后执行：

```sh
base64 < DeveloperID.p12 | pbcopy
```

将剪贴板内容保存为 `MACOS_CERTIFICATE_P12`。不要把 `.p12`、密码或 App 专用密码
提交到仓库。

如果已经安装 GitHub CLI，也可以在仓库目录执行：

```sh
base64 < DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set KEYCHAIN_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_PASSWORD
gh secret set APPLE_TEAM_ID
```

## 创建发布

在打标签之前，把该版本的中英双语说明写到
`docs/releases/vX.Y.Z.md`（与 `CFBundleShortVersionString` 一致）。本地发布
脚本和 CI 会优先用这份文件作为 GitHub Release 正文；没有文件时才回退到
`gh` 自动生成的英文提交列表。

标签必须与 `App/Info.plist` 的版本完全一致。例如版本为 `0.3.0`：

```sh
git tag -a v0.3.0 -m "FanBar 0.3.0"
git push origin v0.3.0
```

成功后 Release 会包含：

- `FanBar-0.3.0.dmg`
- `FanBar-0.3.0.dmg.sha256`

公证失败时应先查看 `notarytool` 在 Actions 日志中返回的具体问题，不要发布
未公证的 CI 测试产物。

## Sparkle 多语言更新说明

除 GitHub Release 的中英说明外，为每个版本准备以下 HTML 片段，放在
`docs/releases/vX.Y.Z/`：`en.html`、`zh-Hans.html`、`zh-Hant.html`、
`ja.html`、`ru.html`、`fr.html`、`ko.html`。每个文件只包含该语言的更新内容，
例如 `<h3>Fixes</h3><ul><li>...</li></ul>`；不要放安装链接。使用 HTML 可以兼容
macOS 11。所有语言均为必填，缺失或空文件会使发布失败。

本地发布与 CI 会在 Sparkle 生成并签署更新包后，将各语言说明嵌入 appcast。
Sparkle 根据 macOS 首选语言选择说明，不一定跟随 FanBar 设置中的语言。更新包的
EdDSA 签名保持不变；若以后启用 `SURequireSignedFeed`，必须改为在签署 feed 前
加入说明，本脚本会拒绝修改已要求签名的 feed。
