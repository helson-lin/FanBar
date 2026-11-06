<div align="center">

<img src="Assets/FanBar-readme-banner-light.png" alt="FanBar — 免費開源的原生 macOS 風扇控制工具" width="100%">

# FanBar

> 原生 macOS 選單列風扇控制工具：隨時查看溫度，需要時再精細管理散熱策略。

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md"><strong>繁體中文</strong></a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.fr.md">Français</a>
</p>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases/latest">
    <img src="https://img.shields.io/github/v/release/helson-lin/FanBar?color=brightgreen" alt="release">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/github/downloads/helson-lin/FanBar/total?color=blue" alt="downloads">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/releases">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fhelson-lin%2FFanBar%2Fbadges%2Fdmg-downloads.json" alt="DMG 下載次數" title="所有版本 DMG 的累計下載次數，包含更新下載，每日更新。">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/stargazers">
    <img src="https://img.shields.io/github/stars/helson-lin/FanBar?color=yellow" alt="stars">
  </a>
</p>

<p align="center">
  <a href="#-截圖">截圖</a> •
  <a href="#-亮點">亮點</a> •
  <a href="#️-下載">下載</a> •
  <a href="#-使用方式">使用方式</a> •
  <a href="#️-建置與執行">建置</a> •
  <a href="#️-架構">架構</a> •
  <a href="#-持續整合與發佈">發佈</a> •
  <a href="#-回報問題">回報問題</a>
</p>

</div>

FanBar 支援 macOS 11 Big Sur 及更新版本，適用於 Apple Silicon 與仍提供可讀取 AppleSMC 風扇資料的 Intel Mac。日常使用維持由 macOS 自動管理，只有在使用者核准已簽署的控制服務後，才會開放手動調整轉速。

## 📸 截圖

以下為淺色與深色外觀下的繁體中文介面。可在 **設定 → 一般 → 介面語言** 中切換為英文、簡體中文、日文、俄文或法文，無需重新啟動。

<table>
  <tr>
    <th>淺色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-light-zh-TW.png" alt="FanBar 繁體中文選單列面板 (淺色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dark-zh-TW.png" alt="FanBar 繁體中文選單列面板 (深色)" width="100%"></td>
  </tr>
</table>

在有兩個風扇的 Mac 上，面板會並排顯示每個風扇各自的轉速、狀態與範圍。下圖來自一台使用「均衡」預設的 MacBook Pro（M2 Max）。

<table>
  <tr>
    <th>淺色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-light-zh-TW.png" alt="FanBar 繁體中文選單列面板，雙風扇 MacBook Pro (淺色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-menu-dual-fan-dark-zh-TW.png" alt="FanBar 繁體中文選單列面板，雙風扇 MacBook Pro (深色)" width="100%"></td>
  </tr>
</table>

「散熱」頁面為每個面板預設提供獨立的溫度→轉速曲線，可直接拖移控制點編輯。

<table>
  <tr>
    <th>淺色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-cooling-light-zh-TW.png" alt="FanBar 繁體中文散熱設定 (淺色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-cooling-dark-zh-TW.png" alt="FanBar 繁體中文散熱設定 (深色)" width="100%"></td>
  </tr>
</table>

「外觀」頁面可選擇選單列圖像與顯示內容，並透過模擬選單列即時預覽。

<table>
  <tr>
    <th>淺色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-appearance-light-zh-TW.png" alt="FanBar 繁體中文外觀設定 (淺色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-appearance-dark-zh-TW.png" alt="FanBar 繁體中文外觀設定 (深色)" width="100%"></td>
  </tr>
</table>

「一般」頁面包含本機相容性檢查、控制服務狀態、自動恢復、通知、語言、登入啟動、更新，以及命令行與 Raycast 設定。「日誌」頁面可將溫度與風扇轉速記錄為 CSV。較長的設定頁面可向下捲動。

<table>
  <tr>
    <th>淺色</th>
    <th>深色</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/fanbar-settings-general-light-zh-TW.png" alt="FanBar 繁體中文一般設定 (淺色)" width="100%"></td>
    <td><img src="docs/screenshots/fanbar-settings-general-dark-zh-TW.png" alt="FanBar 繁體中文一般設定 (深色)" width="100%"></td>
  </tr>
</table>

## ✨ 亮點

- **狀態一目了然**：選單列可顯示圖像、CPU 溫度、平均風扇 RPM 或組合資訊；組合資訊可並排顯示，也可上下排列以節省選單列寬度。
- **六款選單列圖像**：漩渦、環形、粗體、螺旋槳、護罩、線條任選，皆與系統圖像做過光學對齊；由 FanBar 控制風扇時，圖像中心會變為實心。風扇運轉時圖像隨之旋轉，停轉後緩緩靜止；可在 **設定 → 外觀** 中關閉，讓圖像保持靜止並節省少量 CPU。
- **即時視覺化**：每個風扇先顯示轉速與轉速區間，轉速條從 0 到最大值。資源區精簡顯示 CPU、GPU、記憶體與磁碟使用量，依程度顯示綠、橙、紅，磁碟依剩餘空間判斷。可查看 CPU/GPU 溫度；裝置支援時同時顯示 SSD 與電池溫度，並提供近十分鐘的趨勢圖。
- **桌面小工具**：macOS 14 及更新版本可將 FanBar 風扇小工具加入桌面，查看平均 RPM、各風扇轉速、CPU 溫度與控制模式；小工具由系統排程更新，不保證每秒即時。
- **多種散熱方式**：恢復自動控制、設定目標 RPM，或使用靜音、均衡、效能、極速面板預設。
- **智慧溫控曲線**：每個面板預設都有獨立曲線，依晶片溫度平滑調整轉速，可在設定中分別編輯。
- **溫度來源可選**：溫控曲線可使用 CPU、GPU 或硬碟（SSD）溫度作為控制來源；裝置未提供對應感測器時會維持安全回復。
- **高溫通知**：可在設定中開啟 CPU/GPU 高溫通知，達到設定溫度（60–105°C，預設 90°C）時傳送 macOS 通知；同一次高溫只提醒一次，降溫後會重新提醒。可選擇提示音，即使關閉了通知聲音或開啟了專注模式也會播放。過熱時面板會提供一鍵切換到最大散熱。
- **命令行與 Raycast**：`fanbar` 命令行工具可在終端機或指令碼中查看狀態與溫度、切換預設、設定固定轉速，或將風扇交還給 macOS，並支援 `--json` 輸出，方便自動化。在 **設定 → 一般 → 命令行與自動化** 中一鍵安裝，同一處也能設定 Raycast 指令碼命令。
- **CSV 日誌**：每 2–60 秒將 CPU、GPU、SSD、電池溫度、風扇轉速與控制模式寫入 `~/Library/Application Support/FanBar/Logs` 下的 CSV 檔案，可選擇在啟動時、每天午夜或從不建立新檔案。
- **安全回復**：轉速始終限制在硬體回報的範圍內；結束、連線中斷或服務異常時，會盡力恢復系統自動控制。
- **原生授權流程**：首次使用時會說明控制服務的用途，並自動開啟正確的 macOS 設定頁面。
- **六種介面語言**：English、简体中文、繁體中文、日本語、Русский、Français，也可跟隨系統語言。

## ⬇️ 下載

最新已公證版本請見 [GitHub Releases](https://github.com/helson-lin/FanBar/releases/latest)：

| 晶片 | 檔案 |
|:--|:--|
| Apple Silicon | `FanBar-<version>-arm64.dmg` |
| Intel | `FanBar-<version>-x86_64.dmg` |
| Universal（Sparkle 線上更新使用） | `FanBar-<version>.dmg` |

### 透過 Homebrew 安裝

安裝 [Homebrew](https://brew.sh) 後，將本儲存庫加入為 tap 並安裝：

```sh
brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git
brew install --cask helson-lin/fanbar/fanbar
```

Cask 會將已簽署並公證的通用版 App 安裝到 `/Applications`，同時支援 Apple Silicon
與 Intel。啟動 FanBar 後，依提示核准控制服務即可調整風扇。若先前已手動安裝，
請先結束 FanBar，並將現有的 `/Applications/FanBar.app` 移到垃圾桶，再透過 Homebrew 安裝。

FanBar 仍可透過 Sparkle 自動更新；也可以明確使用 Homebrew 升級：

```sh
brew update
brew upgrade --cask helson-lin/fanbar/fanbar
```

解除安裝前請先結束 FanBar，然後執行：

```sh
brew uninstall --cask helson-lin/fanbar/fanbar
```

加上 `--zap` 可同時移除偏好設定與快取。移除風扇控制服務時，Homebrew 可能會要求輸入管理者密碼。

### 系統需求

- macOS 11 Big Sur 或更新版本
- 一台可透過 AppleSMC 讀取風扇資料的 Mac
- 若要自行建置：Xcode 26 與 Swift 6

> [!WARNING]
> SMC 是 Apple 未公開支援的硬體介面。降低轉速可能導致過熱；持續高轉速可能增加噪音、耗電與機械磨損。請只在了解風險的前提下啟用手動控制，並優先使用「自動」或「智慧溫控」。

## 🚀 使用方式

1. 啟動 FanBar 後，從選單列查看目前的溫度與風扇轉速。
2. 需要手動控制時，選擇「啟用風扇控制」，並依系統提示完成授權。
3. 從選單列選擇面板預設或固定轉速；完成後可隨時恢復「自動」模式。

固定轉速與面板預設可在 15 分鐘、30 分鐘或 1 小時後自動恢復由 macOS 管理，避免忘記關閉手動控制。

在 macOS 14 及更新版本中，開啟通知中心的小工具編輯器，搜尋並加入 **FanBar**。小工具顯示主程式最近發佈的風扇快照；WidgetKit 的更新頻率由 macOS 決定，因此需要每秒即時資料時，請使用選單列面板。

### 命令行與 Raycast

在 **設定 → 一般 → 命令行與自動化 → 命令行工具** 中點「安裝…」，會將 `/usr/local/bin/fanbar` 連結到 App 內的工具，隨 FanBar 一起更新。

```sh
fanbar status                  # 模式、預設、風扇、溫度
fanbar preset set performance
fanbar mode fixed 3000 --hold  # 保持到你手動變更
fanbar mode auto               # 將風扇交還給 macOS
```

不加 `--hold` 時，會依設定中的自動恢復時間交還 macOS 控制。加上 `--json` 可輸出機器可讀結果。FanBar 未執行時，命令會在背景開啟它；切換模式需要已核准風扇控制服務。

Raycast：在同一區塊點「在 Raycast 中設定…」，然後在 Raycast 中新增一次指令碼目錄（設定 → Extensions → **+** → Add Script Directory）。之後就能在 Raycast 中切換預設、設定固定轉速、交還自動控制，並在根搜尋中直接看到 CPU、GPU、SSD 溫度。

完整說明請見 [docs/cli.md](docs/cli.md)（英文）。

### 切換介面語言

開啟 **設定 → 一般 → 介面語言**，可選擇：

- **System**：跟隨 Mac 目前的語言（簡體中文、繁體中文、日文、俄文、法文，其他語言顯示英文）
- **English**：英文介面
- **简体中文**：簡體中文介面
- **繁體中文**：繁體中文介面（台灣用語）
- **日本語**：日文介面
- **Русский**：俄文介面
- **Français**：法文介面

語言設定會同步套用到選單列面板、設定視窗、首次使用引導、狀態訊息、控制服務錯誤提示與桌面小工具。

## 🤝 社群

[貢獻指南](CONTRIBUTING.md) · [行為準則](CODE_OF_CONDUCT.md) · [使用支援](SUPPORT.md) · [安全政策](SECURITY.md)

疑似安全漏洞請依安全政策私下回報；一般問題、功能建議與使用諮詢請使用下方的公開 Issue 表單。

## 🐛 回報問題

提交前請先搜尋[現有 Issue](https://github.com/helson-lin/FanBar/issues)，再透過 [Issue 表單](https://github.com/helson-lin/FanBar/issues/new/choose)選擇問題回報、功能建議或使用問題。回報錯誤時請提供 FanBar 版本、macOS 版本、Mac 機型與重現步驟；上傳截圖或記錄檔前請移除個人資訊。

## 🛠️ 建置與執行

複製儲存庫後，執行以下指令建置僅供本機測試的 App 套件：

```sh
zsh scripts/generate-icons.sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=-` 產生的 ad-hoc 套件僅供建置驗證，特權 Helper 無法通過驗證。測試風扇控制或發佈時請使用真實簽署身分；開發準備與驗證方式請見[貢獻指南](CONTRIBUTING.md)。

### 建立本機 DMG

```sh
FANBAR_ALLOW_ADHOC=1 FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

預設產物為 `dist/FanBar-<version>.dmg`。架構建置、簽署與 DMG 驗證方式請參考 [English README](README.md) 中的 Build and run 小節。

## 🏗️ 架構

FanBar 將介面與需要特權的寫入操作分開：

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

Helper 不提供任意 SMC 寫入介面，只支援查詢、固定／預設／依比例設定，以及恢復自動控制。macOS 13 以上使用 `SMAppService` 管理服務；macOS 11–12 使用相容的 launchd 註冊流程。

## 📦 持續整合與發佈

FanBar 使用 Sparkle 2 檢查與安裝線上更新。穩定版更新來源為 GitHub Release 中的
`appcast.xml`；更新套件必須同時通過 Developer ID、公證與 FanBar 專用的 EdDSA
簽署驗證。

在本機首次設定 Apple 公證憑證：

```sh
xcrun notarytool store-credentials FanBar-notary \
  --apple-id "你的 Apple ID" \
  --team-id "64S5F787T9"
```

將 `CFBundleShortVersionString` 與遞增後的 `CFBundleVersion` 提交到 `main` 後，執行：

```sh
gh auth login -h github.com
FANBAR_NOTARY_PROFILE=FanBar-notary zsh scripts/release-local.sh
```

本機發佈指令碼要求工作區乾淨且位於 `main`，會依序完成 universal2 建置、獨立的
`arm64` / `x86_64` DMG、簽署、公證、DMG 驗證、總和檢查碼、已簽署的 Appcast、Git
標籤與 GitHub Release 上傳。既有的 Release 預設不會被覆寫；僅在明確重試時使用
`--replace-assets`。

Sparkle 私密金鑰儲存在登入鑰匙圈的 `FanBar` 帳號中。首次發佈後請勿重新產生此金鑰，
否則已安裝的版本將無法驗證後續更新。CI 發佈還需將匯出的私密金鑰儲存為
`SPARKLE_PRIVATE_KEY` GitHub Actions secret。

GitHub Actions 也會在推送與 Pull Request 時驗證 universal2 建置。本機發佈是
預設方式；若要改由標籤觸發 CI 發佈，需要設定儲存庫變數
`FANBAR_PUBLISH_FROM_CI=true`，並設定 `SPARKLE_PRIVATE_KEY` 等 Release secrets。
請勿同時啟用 CI 發佈並執行本機發佈指令碼。

啟用 CI 發佈模式後，推送與 App 版本相符的標籤：

```sh
git tag -a v0.6.3 -m "FanBar 0.6.3"
git push origin v0.6.3
```

### 更新 Homebrew Cask

CI 發佈穩定版後，`macos-release.yml` 的 `homebrew` job 會把 Cask 固定到該版本，並自動開出
`chore/homebrew-cask-<version>` PR，檢查通過後合併即可。本機發佈，或需要固定到其他 tag 時，
執行以下指令，再自行將 Cask 變更提交為 PR：

```sh
python3 scripts/update-homebrew-cask.py          # 最新穩定版
# 或：python3 scripts/update-homebrew-cask.py v0.6.3
```

指令碼需要 Python 3 與已登入的 `gh` CLI，會拒絕草稿、預先發行版本及缺少通用 DMG 的版本。
將 `Casks/fanbar.rb` 合併到 `main` 後，使用者即可透過 `brew update` 取得新版。
Homebrew CI 會檢查 Cask 格式、下載總和檢查碼、安裝與解除安裝。

## ⭐ Star 趨勢

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=helson-lin/FanBar&type=Date)](https://star-history.com/#helson-lin/FanBar&Date)

</div>

## 🙏 致謝與授權

Copyright © 2024–2026 Jarin He。FanBar 原始碼採用 [GNU 通用公共授權條款 v3.0（GPL-3.0）](LICENSE) 授權。

你可以使用、修改與再散布 FanBar（包含商業用途），但須遵守 GPL-3.0：保留版權與授權聲明，並以相同授權條款公開所散布修改版本的原始碼。

**名稱與圖像不在授權範圍內。**「FanBar」名稱及 FanBar 圖像／Logo 不屬於 GPL-3.0 的授權範圍。散布修改版本時必須更改名稱並替換圖像，以免與官方 FanBar 混淆。

Apple Silicon 的控制序列參考了採用 MIT 授權的 [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan)。完整的第三方歸屬請見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

感謝以下朋友回報錯誤，協助 FanBar 變得更好：

<table>
  <tr>
    <td align="center">
      <img src="docs/contributors/qingcang.png" width="64" height="64" alt="倾藏的頭像"><br>
      <sub><b>倾藏</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/yisasayisa.png" width="64" height="64" alt="一撒撒一撒的頭像"><br>
      <sub><b>一撒撒一撒</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/taolela.png" width="64" height="64" alt="Taolela 的頭像"><br>
      <sub><b>Taolela</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/estelle00.png" width="64" height="64" alt="Estelle00 的頭像"><br>
      <sub><b>Estelle00</b></sub>
    </td>
  </tr>
</table>
