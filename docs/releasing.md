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
