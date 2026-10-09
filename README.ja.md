<div align="center">

<img src="Assets/FanBarIcon-modern-1024.png" alt="FanBar logo" width="120" height="120">

# FanBar

> 温度を確認し、必要なときだけファンの冷却を管理できる、ネイティブな macOS メニューバーユーティリティ。

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md"><strong>日本語</strong></a>
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
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fhelson-lin%2FFanBar%2Fmain%2Fdocs%2Fbadges%2Fdmg-downloads.json" alt="DMG ダウンロード数" title="アップデートを含む、全リリースの DMG の累計ダウンロード数（毎日更新）。">
  </a><!--
  --><a href="https://github.com/helson-lin/FanBar/stargazers">
    <img src="https://img.shields.io/github/stars/helson-lin/FanBar?color=yellow" alt="stars">
  </a>
</p>

<p align="center">
  <a href="#-スクリーンショット">スクリーンショット</a> •
  <a href="#-主な機能">主な機能</a> •
  <a href="#️-ダウンロード">ダウンロード</a> •
  <a href="#-使い方">使い方</a> •
  <a href="#️-ビルドと実行">ビルド</a> •
  <a href="#️-アーキテクチャ">アーキテクチャ</a> •
  <a href="#-継続的インテグレーションとリリース">リリース</a> •
  <a href="#-問題の報告">問題の報告</a>
</p>

</div>

FanBar は macOS 11 Big Sur 以降に対応し、Apple Silicon Mac と、AppleSMC から読み取れるファンのデータを提供する Intel Mac で動作します。普段は macOS の自動管理で安全かつ静かに使え、署名済みの制御サービスを承認したときだけ手動制御が利用できます。

## 📸 スクリーンショット

英語のインターフェイスです。**設定 → 一般 → 表示言語** から、再起動せずに日本語、簡体字中国語、繁体字中国語に切り替えられます。

![FanBar のメニューバーポップオーバー（英語）](docs/screenshots/fanbar-menu-light-en.jpg)

設定は「冷却」タブから開きます。パネルの各プリセットには、編集できる温度→回転数のカーブがあります。

![FanBar の冷却設定（英語）](docs/screenshots/fanbar-settings-cooling-light-en.jpg)

「外観」では、メニューバーのアイコンと表示内容を選び、メニューバーを模したプレビューでその場で確認できます。

![FanBar のメニューバー表示設定（英語）](docs/screenshots/fanbar-settings-menubar-light-en.jpg)

「一般」では、ログイン項目、制御サービスの状態、高温通知、表示言語、Sparkle によるアップデートを設定できます。

![FanBar の一般設定（英語）](docs/screenshots/fanbar-settings-general-light-en.jpg)

## ✨ 主な機能

- **状態をひと目で確認** — メニューバーにアイコン、CPU 温度、ファンの平均回転数、またはその組み合わせを表示します。組み合わせは横並びのほか、2 段に重ねてメニューバーの幅を節約することもできます。
- **6 種類のメニューバーアイコン** — 渦巻き、リング、ボールド、プロペラ、ガード、アウトラインから選べます。どれもシステムのアイコンと見た目の大きさがそろうよう調整済みで、FanBar がファンを制御している間はアイコンの中心が塗りつぶされます。
- **デスクトップウィジェット** — macOS 14 以降では、FanBar をデスクトップに追加して、平均回転数、ファンごとの回転数、CPU 温度、制御モードを確認できます。WidgetKit の更新はシステムが決めるため、秒単位ではありません。
- **リアルタイムの可視化** — CPU/GPU の温度に加え、Mac が対応していれば SSD とバッテリーの温度も表示します。直近 10 分間のグラフと、実際の回転数に合わせた気流アニメーションも備えています。
- **複数の冷却モード** — macOS の自動制御に戻す、目標回転数を指定する、またはパネルプリセット（静音、バランス、高性能、最大）を選べます。
- **スマートな温度カーブ** — パネルの各プリセットに専用のカーブがあり、チップの温度に応じてファンの出力をなめらかに調整します。
- **温度ソースを選択可能** — カーブ制御に CPU、GPU、SSD のいずれかの温度を使えます。センサーを利用できない場合は、既存の安全なフォールバックが働きます。
- **高温通知** — CPU または GPU が 90°C に達したときに macOS の通知を受け取れます（オプトイン）。高温状態 1 回につき通知は 1 回で、温度が下がると再び通知できる状態に戻ります。
- **安全なフォールバック** — 目標回転数は各ファンが報告するハードウェアの範囲内に制限されます。終了時、接続の切断時、サービスの障害時には、macOS の自動制御に戻すよう試みます。
- **ネイティブな承認フロー** — 初回起動時に制御サービスが必要な理由を説明し、macOS の該当する設定画面を開きます。
- **4 つの言語** — English、简体中文、繁體中文、日本語に対応し、システムの言語に合わせることもできます。

## ⬇️ ダウンロード

公証済みの最新ビルドは [GitHub Releases](https://github.com/helson-lin/FanBar/releases/latest) にあります。

| チップ | ファイル |
|:--|:--|
| Apple Silicon | `FanBar-<version>-arm64.dmg` |
| Intel | `FanBar-<version>-x86_64.dmg` |
| Universal（Sparkle のアップデートで使用） | `FanBar-<version>.dmg` |

### Homebrew でインストール

[Homebrew](https://brew.sh) をインストール済みであれば、このリポジトリを tap として追加してインストールします。

```sh
brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git
brew install --cask helson-lin/fanbar/fanbar
```

Cask は、Apple Silicon と Intel の両方に対応した署名・公証済みのユニバーサル App を
`/Applications` にインストールします。FanBar を起動し、制御サービスを承認するとファンを
制御できるようになります。FanBar を手動でインストール済みの場合は、FanBar を終了し、既存の
`/Applications/FanBar.app` をゴミ箱に入れてから Homebrew でインストールしてください。

FanBar は Sparkle で自動的にアップデートできます。Homebrew で明示的にアップグレードするには:

```sh
brew update
brew upgrade --cask helson-lin/fanbar/fanbar
```

アンインストールするには、先に FanBar を終了してから次を実行します。

```sh
brew uninstall --cask helson-lin/fanbar/fanbar
```

`--zap` を付けると、保存された環境設定とキャッシュも削除されます。ファン制御サービスを
停止するため、Homebrew が管理者パスワードを求める場合があります。

### 動作環境

- macOS 11 Big Sur 以降
- AppleSMC からファンのデータを取得できる Mac
- ローカルでビルドする場合は Xcode 26 と Swift 6

> [!WARNING]
> AppleSMC は公開されていないハードウェアインターフェイスです。ファンの回転数を下げると温度が上がることがあり、高い回転数を続けると騒音、消費電力、機械的な摩耗が増えることがあります。トレードオフを理解したうえで手動制御を使い、普段は「自動」またはスマート冷却をおすすめします。

## 🚀 使い方

1. FanBar を起動し、メニューバーで現在の温度とファンの回転数を確認します。
2. ファンを制御するには、ファン制御を有効にし、macOS の承認の案内に従います。
3. ポップオーバーからパネルプリセットまたは固定回転数を選びます。「自動」を選べば、いつでも macOS に制御を戻せます。

固定回転数とパネルプリセットは、15 分、30 分、または 1 時間後に macOS の制御へ自動的に戻すことができます。

macOS 14 以降では、通知センターのウィジェット編集画面を開き、**FanBar** を追加します。ウィジェットにはメインの App が最後に公開したスナップショットが表示されます。更新のタイミングは WidgetKit が決めるため、秒単位のデータが必要な場合はメニューバーのポップオーバーを使ってください。

### 表示言語の変更

**設定 → 一般 → 表示言語** を開き、次から選びます。

- **System** — Mac の現在の言語に合わせます（簡体字中国語、繁体字中国語、日本語。それ以外は英語）
- **English**
- **简体中文**
- **繁體中文**
- **日本語**

この設定は、メニューバーのポップオーバー、設定ウインドウ、初回の案内、ステータスメッセージ、ヘルパーのエラー、デスクトップウィジェットに共通して適用されます。

## 🐛 問題の報告

報告する前に、[既存の Issue](https://github.com/helson-lin/FanBar/issues) を検索してください。そのうえで、不具合、機能の要望、使い方の質問に応じて [Issue フォーム](https://github.com/helson-lin/FanBar/issues/new/choose) を選んでください。不具合の報告には、FanBar のバージョン、macOS のバージョン、Mac のモデル、再現手順を含めてください。スクリーンショットやログからは個人情報を削除してください。

## 🛠️ ビルドと実行

リポジトリをクローンし、ローカル用の App バンドルをビルドします。

```sh
zsh scripts/generate-icons.sh
FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
open dist/FanBar.app
```

`FANBAR_SIGN_IDENTITY=-` はローカルでのテスト用にアドホック署名を使います。配布する場合は、有効な Developer ID Application の署名 ID に置き換えてください。

### ローカルで DMG を作成

```sh
FANBAR_SIGN_IDENTITY=- zsh scripts/build-dmg.sh
```

デフォルトの出力先は `dist/FanBar-<version>.dmg` です。特定のアーキテクチャ向けにビルドするには:

```sh
FANBAR_ARCHS=arm64 FANBAR_APP_OUTPUT=dist/FanBar-arm64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-arm64.dmg zsh scripts/build-dmg.sh dist/FanBar-arm64.app

FANBAR_ARCHS=x86_64 FANBAR_APP_OUTPUT=dist/FanBar-x86_64.app \
  FANBAR_SIGN_IDENTITY=- zsh scripts/package-app.sh
FANBAR_DMG_OUTPUT=dist/FanBar-x86_64.dmg zsh scripts/build-dmg.sh dist/FanBar-x86_64.app
```

DMG の署名、アーキテクチャ、インストール構成は次のコマンドで検証できます。

```sh
zsh scripts/test-dmg.sh dist/FanBar-0.4.3.dmg
```

## 🏗️ アーキテクチャ

FanBar は UI と特権が必要な書き込みを分離しています。

```text
FanBar.app → privileged XPC → FanBarHelper (root) → AppleSMC
```

ヘルパーは任意の SMC 書き込みを公開しません。対応するのは、ファンの読み取り、範囲内での目標値／プリセット／比率の設定、自動制御への復帰のみです。macOS 13 以降は `SMAppService` を使い、macOS 11–12 では互換性のある launchd 登録を使います。

## 📦 継続的インテグレーションとリリース

FanBar はオンラインアップデートに Sparkle 2 を使用しています。安定版のフィードは、最新の
GitHub Release にある `appcast.xml` です。すべてのアップデートは、Developer ID、公証、
FanBar 独自の EdDSA 署名の検証に合格する必要があります。

リリース用の Mac で、Apple の公証用認証情報を一度だけ保存します。

```sh
xcrun notarytool store-credentials FanBar-notary \
  --apple-id "あなたの Apple ID" \
  --team-id "64S5F787T9"
```

更新した `CFBundleShortVersionString` と、増やした `CFBundleVersion` を `main` にコミットしたら、
ローカルで公開します。

```sh
gh auth login -h github.com
FANBAR_NOTARY_PROFILE=FanBar-notary zsh scripts/release-local.sh
```

ローカルのリリースコマンドには、クリーンな `main` のチェックアウトが必要です。universal2 の
ビルド、`arm64` と `x86_64` の個別の DMG、署名、公証、DMG の検証、チェックサム、署名済みの
appcast、Git タグ、GitHub Release へのアップロードを行います。既存のリリースはデフォルトで
保持されます。`--replace-assets` は意図的にやり直す場合にのみ使ってください。

Sparkle の秘密鍵は、ログインキーチェーンの `FanBar` アカウントに保存されています。
インストール済みのクライアントが同じ公開鍵を信頼し続ける必要があるため、最初のリリース後は
再生成しないでください。CI でリリースする場合は、書き出した秘密鍵を GitHub Actions の
シークレット `SPARKLE_PRIVATE_KEY` にも登録する必要があります。

GitHub Actions は、プッシュとプルリクエストのたびに universal2 ビルドを検証します。
デフォルトはローカルでの公開です。タグをきっかけに CI で公開するには、リポジトリ変数
`FANBAR_PUBLISH_FROM_CI=true` を設定し、`SPARKLE_PRIVATE_KEY` などのリリース用シークレットを
構成します。ローカルのリリースコマンドを使っている間は、CI での公開を有効にしないでください。

CI での公開が有効な場合は、App のバージョンに一致するタグをプッシュします。

```sh
git tag -a v0.4.3 -m "FanBar 0.4.3"
git push origin v0.4.3
```

### Homebrew cask の更新

安定版を（ローカルまたは CI で）公開したら、ユニバーサル DMG をダウンロードしてハッシュを
計算し、生成された cask の変更を PR として提出します。

```sh
python3 scripts/update-homebrew-cask.py          # 最新の安定版
# または: python3 scripts/update-homebrew-cask.py v0.4.14
```

このスクリプトには Python 3 と、認証済みの `gh` CLI が必要です。ドラフト、プレリリース、
ユニバーサル DMG がないリリースは受け付けません。`Casks/fanbar.rb` を `main` にマージすると、
`brew update` で新しいバージョンを入手できるようになります。Homebrew の CI ワークフローは、
cask のスタイル、ダウンロードのチェックサム、インストール、削除を検査します。

## ⭐ Star の推移

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=helson-lin/FanBar&type=Date)](https://star-history.com/#helson-lin/FanBar&Date)

</div>

## 🙏 謝辞とライセンス

Copyright © 2024–2026 Jarin He. FanBar のソースコードは [GNU General Public License v3.0](LICENSE) のもとで提供されています。

GPL-3.0 に従う限り、FanBar を使用、改変、再配布できます（商用利用を含む）。著作権表示とライセンス表示を残し、改変版を配布する場合はそのソースコードを同じライセンスで公開してください。

**名称とアイコンは対象外です。**「FanBar」という名称と FanBar のアイコン／ロゴは GPL-3.0 の対象ではありません。改変版を配布する場合は、公式の FanBar と混同されないよう、名称を変更しアイコンを差し替えてください。

Apple Silicon の制御手順は、MIT ライセンスの [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan) を参考にしています。サードパーティの帰属表示の全文は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

不具合を報告し、FanBar の改善に協力してくださった皆さんに感謝します。

<table>
  <tr>
    <td align="center">
      <img src="docs/contributors/qingcang.png" width="64" height="64" alt="倾藏さんのアバター"><br>
      <sub><b>倾藏</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/yisasayisa.png" width="64" height="64" alt="一撒撒一撒さんのアバター"><br>
      <sub><b>一撒撒一撒</b></sub>
    </td>
    <td align="center">
      <img src="docs/contributors/taolela.png" width="64" height="64" alt="Taolelaさんのアバター"><br>
      <sub><b>Taolela</b></sub>
    </td>
  </tr>
</table>
