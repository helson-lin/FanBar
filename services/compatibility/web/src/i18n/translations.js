export const translations = {
  "上次未记录正常退出；需结合崩溃摘要判断，也可能是强制退出或关机。": {"en": "The previous run has no normal-exit marker. Check crash summaries; force quit or shutdown may also explain it.", "ja": "前回は正常終了が記録されていません。クラッシュ概要と照合してください。強制終了や電源断の可能性もあります。"},
  "曾处于等待系统授权状态，请对照后续状态变化。": {"en": "System approval was pending. Compare subsequent state transitions.", "ja": "システムの承認待ち状態がありました。以降の状態変化を確認してください。"},
  "存在控制服务超时，请按请求编号对照连接与控制事件。": {"en": "Control service timeouts occurred. Correlate connection and control events by request ID.", "ja": "制御サービスのタイムアウトがあります。要求番号で接続と制御イベントを照合してください。"},
  "未能读取 Helper 事件，不能据此认定 Helper 没有运行。": {"en": "Helper events could not be read. This does not prove the helper was not running.", "ja": "Helperのイベントを読み取れませんでした。Helperが動作していないとは断定できません。"},
  "无法访问崩溃日志目录，空列表不代表没有崩溃。": {"en": "The crash-log directory is inaccessible. An empty list does not establish that no crash occurred.", "ja": "クラッシュログのフォルダーにアクセスできません。空の一覧でもクラッシュがなかったとは限りません。"},
  "崩溃摘要": {"en": "Crash summaries", "ja": "クラッシュ概要"},
  "运行事件时间线": {"en": "Runtime event timeline", "ja": "動作イベントの時系列"},
  "时间": {"en": "Time", "ja": "時刻"},
  "组件 / 操作": {"en": "Component / action", "ja": "コンポーネント / 操作"},
  "结果 / 错误码": {"en": "Outcome / error code", "ja": "結果 / エラーコード"},
  "参数 / 耗时": {"en": "Value / duration", "ja": "値 / 所要時間"},
  "请求编号": {"en": "Request ID", "ja": "要求番号"},
  "运行诊断还包含最近 24 小时内有界保留的启动、授权、连接与控制事件，最近 10 分钟可读取的 Helper 事件，以及最近 7 天内最多 3 份崩溃摘要。只提取异常类型、终止代码和固定模块名与偏移，不上传完整崩溃文件、路径、原始错误描述或系统日志。": {"en": "Runtime diagnostics also include bounded launch, approval, connection, and control events from the last 24 hours; readable helper events from the last 10 minutes; and up to 3 crash summaries from the last 7 days. Only exception types, termination codes, and fixed module names and offsets are extracted. Complete crash files, paths, arbitrary error descriptions, and system logs are excluded.", "ja": "動作診断には直近24時間の制限付き起動・承認・接続・制御イベント、読み取り可能な直近10分のHelperイベント、直近7日で最大3件のクラッシュ概要も含みます。例外型、終了コード、固定モジュール名とオフセットのみ抽出し、完全なクラッシュファイル、パス、任意のエラー文、システムログは送信しません。"},

  "诊断还包含最近一分钟内最多 30 次采样、温度键的数据类型与最多 8 字节原始值、有限的温度键枚举及其截断状态、SSD 和电池备用来源的读取结果。日志上限为 256 KiB。": {"en":"Diagnostics also include up to 30 samples from the last minute, temperature-key data types and up to 8 raw bytes, bounded temperature-key enumeration with truncation state, and SSD and battery fallback results. The maximum log size is 256 KiB.","ja":"診断には直近1分の最大30サンプル、温度キーの型と最大8バイトの元の値、制限付き温度キー列挙と打ち切り状態、SSDとバッテリーの代替取得結果も含まれます。ログの上限は256 KiBです。"},
  "SMC 连接失败，请先排查设备访问或连接恢复。": {"en": "SMC connection failed. Investigate device access or connection recovery first.", "ja": "SMCへの接続に失敗しました。機器へのアクセスと接続の復帰を確認してください。"},
  "发现应用尚未识别的有效温度键，需要补充机型传感器映射。": {"en": "Valid temperature keys are not recognized by the app. Extend the model sensor mapping.", "ja": "アプリが未対応の有効な温度キーがあります。機種のセンサー対応表の追加が必要です。"},
  "存在无法解码的数据格式，请结合类型、长度和原始字节检查解码器。": {"en": "Some data formats cannot be decoded. Inspect type, length, and raw bytes.", "ja": "解読できないデータ形式があります。型、長さ、元のバイト列でデコーダーを確認してください。"},
  "部分读数被有效范围过滤，请检查原始值与单位。": {"en": "Some readings were filtered as out of range. Check raw values and units.", "ja": "一部の値が有効範囲外として除外されています。元の値と単位を確認してください。"},
  "键名清单完整，但部分未识别键没有附带读数探测。": {"en": "The key list is complete, but some unrecognized keys were not probed for readings.", "ja": "キー一覧は完全ですが、一部の未識別キーは読み取り検出の対象外です。"},
  "运行中的 Helper（build {running}）与应用内置版本（build {bundled}）不一致：旧守护进程仍在运行，需要重新注册或重启。": {"en": "The running Helper (build {running}) differs from the app's bundled build ({bundled}): an old daemon is still running and must be re-registered or restarted.", "ja": "実行中の Helper（build {running}）がアプリ同梱版（build {bundled}）と異なります。古いデーモンが動作中のため、再登録または再起動が必要です。"},
  "运行中的 Helper 未响应版本查询：可能是早于版本查询的旧 Helper，或已无响应。": {"en": "The running Helper did not answer the build query: it may predate the query, or it is unresponsive.", "ja": "実行中の Helper がバージョン照会に応答しません。照会に対応する前の古い Helper か、応答不能の可能性があります。"},
  "Helper 已启用但无法建立连接，请对照 XPC 事件与错误码。": {"en": "The Helper is enabled but could not be reached. Compare the XPC events and error code.", "ja": "Helper は有効ですが接続できません。XPC イベントとエラーコードを照合してください。"},
  "传感器枚举未完成，当前结果不能代表全部硬件键。": {"en": "Sensor enumeration was incomplete. These results do not cover every hardware key.", "ja": "センサーの列挙は未完了です。すべてのハードウェアキーを網羅していません。"},
  "诊断线索": {"en": "Diagnostic clues", "ja": "診断の手がかり"},
  "最近采样数": {"en": "Recent samples", "ja": "直近のサンプル数"},
  "探测条目": {"en": "Probe entries", "ja": "検出項目数"},
  "扫描键数": {"en": "Keys scanned", "ja": "走査したキー数"},
  "错误码": {"en": "Error code", "ja": "エラーコード"},
  "来源 / 键": {"en": "Source / key", "ja": "取得元 / キー"},
  "阶段 / 结果": {"en": "Stage / result", "ja": "段階 / 結果"},
  "读数 / 错误码": {"en": "Reading / error code", "ja": "読み取り値 / エラーコード"},
  "类型 / 长度 / 原始字节": {"en": "Type / size / raw bytes", "ja": "型 / 長さ / 元のバイト列"},
  "完整诊断数据": {"en": "Complete diagnostic data", "ja": "診断データ全体"},

  "查看详情": {"en":"View details","ja":"詳細を表示"},
  "刷新": {"en":"Refresh","ja":"更新"},
  "诊断日志": {"en": "Diagnostic logs", "ja": "診断ログ"},
  "诊断编号": {"en": "Diagnostic ID", "ja": "診断番号"},
  "日志仅管理员可见，保留 90 天，不参与兼容性统计。": {"en": "Logs are visible only to administrators, retained for 90 days, and excluded from compatibility statistics.", "ja": "ログは管理者のみ閲覧でき、90日間保存されます。互換性統計には含まれません。"},
  "最近 50 份诊断日志；更早的记录可通过诊断编号查询。": {"en": "Latest 50 diagnostic logs; look up older records by diagnostic ID.", "ja": "最新50件の診断ログです。過去の記録は診断番号で検索できます。"},
  "兼容性报告不接收序列号、硬件 UUID、用户名、主机名、文件路径、进程列表、温度历史或诊断日志。": {"en": "Compatibility reports exclude serial numbers, hardware UUIDs, usernames, hostnames, file paths, process lists, temperature history, and diagnostic logs.", "ja": "互換性レポートにはシリアル番号、ハードウェアUUID、ユーザー名、ホスト名、ファイルパス、プロセス一覧、温度履歴、診断ログを含めません。"},
  "诊断日志需单独预览并确认上传，包含设备版本、本次温度读数、传感器键、探测结果、错误码和控制服务状态。不收集系统日志、序列号、用户名、文件路径或进程列表。": {"en": "Diagnostic logs require a separate preview and confirmation. They include device versions, current temperatures, sensor keys, probe results, error codes, and control service state. System logs, serial numbers, usernames, file paths, and process lists are excluded.", "ja": "診断ログは別途プレビューと送信確認が必要です。機器のバージョン、現在の温度、センサーキー、検出結果、エラーコード、制御サービスの状態を含みます。システムログ、シリアル番号、ユーザー名、ファイルパス、プロセス一覧は収集しません。"},
  "日志仅管理员可见，不公开、不参与兼容性统计。在线保留 90 天，可在客户端诊断上传记录中撤回；历史恢复点最长还可能保留 30 天。每份诊断单独生成随机编号和撤回凭证，数据库仅保存凭证哈希。": {"en": "Logs are visible only to administrators and excluded from public records and statistics. They are retained online for 90 days and can be withdrawn in the app. Historical restore points may retain them for up to 30 more days. Each diagnostic has a random ID and withdrawal credential; only its hash is stored in the database.", "ja": "ログは管理者のみ閲覧でき、公開記録や統計には含まれません。オンラインで90日間保存され、アプリから撤回できます。復元ポイントには最大30日間追加で残る場合があります。診断ごとにランダムな番号と撤回用認証情報を生成し、データベースには認証情報のハッシュのみ保存します。"},

  "正常（无内置电池）": { "en": "Normal (no built-in battery)", "ja": "正常（内蔵バッテリーなし）" },
  "可选的手动调速、智能温控本机实测确认，由用户主动勾选；不替代自动检测或开发者验证。": {"en": "Optional user-selected hands-on confirmations for manual control and smart cooling; separate from automatic checks and developer verification.", "ja": "手動制御とスマート温度制御の任意の動作確認。ユーザーが選択するもので、自動確認や開発者の検証とは別です。"},
  "本机实测可用（用户确认）": {"en": "Works on this Mac (user confirmed)", "ja": "この Mac で動作確認済み（ユーザー確認）"},
  "自动检测：{status}": {"en": "Automatic check: {status}", "ja": "自動確認：{status}"},
  "用户确认在本机实际使用可用，不等同于开发者独立实测。": {"en": "Users confirmed it works in actual use on their Macs; this is separate from independent developer tests.", "ja": "ユーザーが自分の Mac で実際に動作を確認しています。開発者による独立検証とは別です。"},
  "用户确认本机实测可用：{count} 份报告": {"en": "User-confirmed working: {count} reports", "ja": "ユーザーの動作確認：{count} 件のレポート"},

  "CPU 温度": {
    "en": "CPU temperature",
    "ja": "CPU 温度"
  },
  "GPU 温度": {
    "en": "GPU temperature",
    "ja": "GPU 温度"
  },
  "SSD 温度": {
    "en": "SSD temperature",
    "ja": "SSD 温度"
  },
  "电池温度": {
    "en": "Battery temperature",
    "ja": "バッテリー温度"
  },
  "风扇转速": {
    "en": "Fan speed",
    "ja": "ファン回転数"
  },
  "风扇读取": {
    "en": "Fan readings",
    "ja": "ファンの読み取り"
  },
  "手动调速": {
    "en": "Manual fan control",
    "ja": "手動ファン制御"
  },
  "智能温控": {
    "en": "Smart cooling",
    "ja": "スマート冷却"
  },
  "已读取": {
    "en": "Read successfully",
    "ja": "読み取り成功"
  },
  "未检测到": {
    "en": "Not detected",
    "ja": "未検出"
  },
  "暂时不可用": {
    "en": "Temporarily unavailable",
    "ja": "一時的に利用不可"
  },
  "需要授权": {
    "en": "Authorization required",
    "ja": "承認が必要"
  },
  "尚未验证": {
    "en": "Not verified",
    "ja": "未検証"
  },
  "请求成功": {
    "en": "Request succeeded",
    "ja": "リクエスト成功"
  },
  "请求失败": {
    "en": "Request failed",
    "ja": "リクエスト失敗"
  },
  "实测可用": {
    "en": "Verified available",
    "ja": "実機で利用可能と確認"
  },
  "实测不支持": {
    "en": "Verified unsupported",
    "ja": "実機で非対応と確認"
  },
  "FanBar · 公开兼容性记录": {
    "en": "FanBar · Public compatibility records",
    "ja": "FanBar · 公開互換性記録"
  },
  "设备兼容性 · 公开记录": {
    "en": "Device compatibility · Public records",
    "ja": "デバイス互換性 · 公開記録"
  },
  "收集与处理规则": {
    "en": "Collection and processing policy",
    "ja": "収集・処理方針"
  },
  "撤回报告": {
    "en": "Withdraw a report",
    "ja": "レポートの撤回"
  },
  "查看源码 ↗": {
    "en": "View source ↗",
    "ja": "ソースコードを見る ↗"
  },
  "这台 Mac，能使用哪些功能？": {
    "en": "Which features work on this Mac?",
    "ja": "この Mac ではどの機能が使えますか？"
  },
  "查看经过审核的社区报告与开发者实测记录。温度读取、风扇读取和实际控制分别判断；没有记录不代表不支持。": {
    "en": "Explore reviewed community reports and independent developer tests. Temperature readings, fan readings and actual control are assessed separately. No record does not mean unsupported.",
    "ja": "審査済みのコミュニティレポートと開発者の実機検証を確認できます。温度、ファンの読み取り、実際の制御は個別に評価します。記録がないことは非対応を意味しません。"
  },
  "无需账号 · 可下载公开结果": {
    "en": "No account required · Download public results",
    "ja": "アカウント不要 · 公開結果をダウンロード可能"
  },
  "机型标识": {
    "en": "Model identifier",
    "ja": "モデル識別子"
  },
  "输入机型标识，例如 Mac14,13": {
    "en": "Enter a model identifier, e.g. Mac14,13",
    "ja": "モデル識別子を入力（例：Mac14,13）"
  },
  "查询": {
    "en": "Search",
    "ja": "検索"
  },
  "公开 JSON ↗": {
    "en": "Public JSON ↗",
    "ja": "公開 JSON ↗"
  },
  "正在加载公开记录…": {
    "en": "Loading public records…",
    "ja": "公開記録を読み込み中…"
  },
  "社区报告": {
    "en": "Community reports",
    "ja": "コミュニティレポート"
  },
  "用户主动提交并经审核的检测结果。统计为报告数量，不代表独立设备数量，也不会自动成为开发者验证。": {
    "en": "Results submitted voluntarily and reviewed. Counts represent reports, not unique devices, and do not automatically become developer verification.",
    "ja": "ユーザーが自発的に提出し、審査を受けた結果です。件数はレポート数であり、個別のデバイス数ではありません。開発者の検証に自動的に変わることもありません。"
  },
  "开发者验证": {
    "en": "Developer verification",
    "ja": "開発者の検証"
  },
  "对应机型、系统与软件版本的独立实测，附带验证日期和公开依据。控制请求成功不等于实际转速已验证。": {
    "en": "Independent tests for a specific model, OS and app version, with a date and public evidence. A successful control request does not verify actual fan speed.",
    "ja": "モデル、OS、アプリのバージョンごとの独立した実機検証です。日付と公開の根拠を添付します。制御リクエストの成功は実際の回転数の検証を意味しません。"
  },
  "隐私与撤回": {
    "en": "Privacy and withdrawal",
    "ja": "プライバシーと撤回"
  },
  "原始报告默认私有。选择公开的报告也需审核后才可查阅；可以使用本机保存的撤回凭证删除报告及其统计贡献。": {
    "en": "Raw reports are private by default. Reports you choose to publish are viewable only after review. Use the withdrawal credential saved on your device to remove the report and its contribution to statistics.",
    "ja": "元のレポートは初期設定で非公開です。公開を選択した場合も審査後に閲覧可能になります。端末に保存した撤回用の認証情報で、レポートと統計への寄与を削除できます。"
  },
  "报告在线保留 90 天，公开统计随有效报告变化。": {
    "en": "Reports remain online for 90 days. Public statistics reflect currently valid reports.",
    "ja": "レポートはオンラインで90日間保存されます。公開統計は有効なレポートに応じて変化します。"
  },
  "完整字段 Schema": {
    "en": "Complete field schema",
    "ja": "全フィールドのスキーマ"
  },
  "处理规则": {
    "en": "Processing policy",
    "ja": "処理方針"
  },
  "管理入口": {
    "en": "Administration",
    "ja": "管理画面"
  },
  "正在查询…": {
    "en": "Searching…",
    "ja": "検索中…"
  },
  "此组合暂无公开记录": {
    "en": "No public records for this combination",
    "ja": "この組み合わせの公開記録はありません"
  },
  "可先参考 FanBar 的本机检测结果；在应用中主动提交报告，帮助完善兼容性记录。": {
    "en": "Check FanBar’s local detection results first. You can voluntarily submit a report from the app to improve these records.",
    "ja": "まず FanBar のローカル検出結果をご確認ください。アプリから任意でレポートを提出し、記録の充実に協力できます。"
  },
  "更新 ": {
    "en": "Updated ",
    "ja": "更新日 "
  },
  "能力": {
    "en": "Capability",
    "ja": "機能"
  },
  "暂无报告": {
    "en": "No reports",
    "ja": "レポートなし"
  },
  "存在不同结果，请结合版本与本机检测判断。": {
    "en": "Results differ. Consider versions and local detection.",
    "ja": "結果に違いがあります。バージョンとローカル検出結果もご確認ください。"
  },
  "依据 · ": {
    "en": "Evidence · ",
    "ja": "根拠 · "
  },
  "尚未实测": {
    "en": "Not independently tested",
    "ja": "独立した実機検証なし"
  },
  "当前显示最近 20 个版本组合，输入机型标识缩小范围。": {
    "en": "Showing the latest 20 version combinations. Enter a model identifier to narrow the results.",
    "ja": "最新20件のバージョンの組み合わせを表示しています。モデル識別子で絞り込めます。"
  },
  "已显示当前有效记录。": {
    "en": "Showing currently valid records.",
    "ja": "現在有効な記録を表示しています。"
  },
  "暂时无法加载记录，请重试。": {
    "en": "Unable to load records. Please try again.",
    "ja": "記録を読み込めません。もう一度お試しください。"
  },
  "撤回报告 · FanBar": {
    "en": "Withdraw a report · FanBar",
    "ja": "レポートの撤回 · FanBar"
  },
  "设备兼容性 · 撤回报告": {
    "en": "Device compatibility · Withdrawal",
    "ja": "デバイス互換性 · 撤回"
  },
  "撤回你提交的报告": {
    "en": "Withdraw your report",
    "ja": "提出したレポートを撤回"
  },
  "也可以在 FanBar 的上报记录中撤回。删除后，报告不再被公开查询，也不再计入在线社区统计。": {
    "en": "You can also withdraw from FanBar’s submission history. After deletion, the report is no longer publicly accessible or included in online community statistics.",
    "ja": "FanBar の提出履歴からも撤回できます。削除後は公開検索の対象外となり、オンラインのコミュニティ統計にも含まれません。"
  },
  "报告编号": {
    "en": "Report ID",
    "ja": "レポート ID"
  },
  "撤回凭证": {
    "en": "Withdrawal credential",
    "ja": "撤回用の認証情報"
  },
  "凭证只通过加密请求发送，不写入网址或浏览器存储。请勿将凭证放进公开反馈。": {
    "en": "The credential is sent only through an encrypted request, never in a URL or browser storage. Do not include it in public feedback.",
    "ja": "認証情報は暗号化されたリクエストでのみ送信し、URLやブラウザーの保存領域には書き込みません。公開のフィードバックには含めないでください。"
  },
  "确认撤回报告": {
    "en": "Confirm withdrawal",
    "ja": "撤回を確定"
  },
  "在线删除不代表云平台历史恢复点立即清除，详见处理规则。": {
    "en": "Online deletion does not immediately erase cloud recovery points. See the processing policy.",
    "ja": "オンラインでの削除は、クラウドの過去の復元ポイントを即座に消去するものではありません。処理方針をご確認ください。"
  },
  "请检查报告编号和撤回凭证。": {
    "en": "Check the report ID and withdrawal credential.",
    "ja": "レポート ID と撤回用の認証情報をご確認ください。"
  },
  "报告已撤回，或已经过期。": {
    "en": "The report has been withdrawn or has expired.",
    "ja": "レポートは撤回済み、または期限切れです。"
  },
  "公开报告 · FanBar": {
    "en": "Public report · FanBar",
    "ja": "公開レポート · FanBar"
  },
  "用户选择公开的社区报告": {
    "en": "Community report published by consent",
    "ja": "ユーザーが公開を選択したコミュニティレポート"
  },
  "公开兼容性报告": {
    "en": "Public compatibility report",
    "ja": "公開互換性レポート"
  },
  "此报告由用户选择公开，并经审核。它不等同于开发者实测。": {
    "en": "The user chose to publish this reviewed report. It is not an independent developer test.",
    "ja": "ユーザーが公開を選択し、審査を受けたレポートです。開発者による独立した実機検証とは異なります。"
  },
  "无效的报告编号。": {
    "en": "Invalid report ID.",
    "ja": "レポート ID が無効です。"
  },
  "用户自愿公开 · 社区报告": {
    "en": "Published by consent · Community report",
    "ja": "任意で公開 · コミュニティレポート"
  },
  "公开兼容性页 ↗": {
    "en": "Public compatibility page ↗",
    "ja": "公開互換性ページ ↗"
  },
  "把报告变成可信的兼容性记录。": {
    "en": "Turn reports into trustworthy compatibility records.",
    "ja": "レポートを信頼できる互換性記録に。"
  },
  "审核通过只纳入社区统计。开发者验证需要独立实测与公开依据，不能由用户请求成功自动推导。": {
    "en": "Approval includes a report in community statistics only. Developer verification requires independent tests and public evidence; it cannot be inferred from a successful user request.",
    "ja": "承認はコミュニティ統計への追加のみを意味します。開発者の検証には独立した実機テストと公開の根拠が必要です。ユーザーのリクエスト成功から自動的に判断はできません。"
  },
  "原始报告默认私有": {
    "en": "Raw reports are private by default",
    "ja": "元のレポートは初期設定で非公開"
  },
  "审核状态": {
    "en": "Review status",
    "ja": "審査状況"
  },
  "待审核": {
    "en": "Pending review",
    "ja": "審査待ち"
  },
  "已纳入统计": {
    "en": "Included in statistics",
    "ja": "統計に追加済み"
  },
  "已排除": {
    "en": "Excluded",
    "ja": "除外済み"
  },
  "全部": {
    "en": "All",
    "ja": "すべて"
  },
  "按机型标识筛选": {
    "en": "Filter by model identifier",
    "ja": "モデル識別子で絞り込み"
  },
  "FanBar 版本": {
    "en": "FanBar version",
    "ja": "FanBar バージョン"
  },
  "上一页": {
    "en": "Previous",
    "ja": "前へ"
  },
  "下一页": {
    "en": "Next",
    "ja": "次へ"
  },
  "选择一份报告": {
    "en": "Select a report",
    "ja": "レポートを選択"
  },
  "查看具体字段，再决定是否纳入社区统计。": {
    "en": "Inspect its fields before including it in community statistics.",
    "ja": "具体的なフィールドを確認してから、コミュニティ統計に追加するか判断してください。"
  },
  "发布独立实测记录": {
    "en": "Publish an independent test",
    "ja": "独立した実機検証を公開"
  },
  "完成对应功能的实际测试后填写。此记录长期公开，附带来源；填写“手动调速可用”需要实际控制证据。": {
    "en": "Complete an actual test before submitting. This record remains public with its source. Marking manual control as available requires evidence of actual control.",
    "ja": "対象機能を実際にテストしてから記入してください。この記録は出典付きで継続的に公開されます。手動制御を利用可能とするには、実際の制御の根拠が必要です。"
  },
  "macOS 版本": {
    "en": "macOS version",
    "ja": "macOS バージョン"
  },
  "Helper 版本": {
    "en": "Helper version",
    "ja": "Helper バージョン"
  },
  "实测能力": {
    "en": "Tested capability",
    "ja": "検証した機能"
  },
  "测试结果": {
    "en": "Test result",
    "ja": "テスト結果"
  },
  "验证日期": {
    "en": "Verification date",
    "ja": "検証日"
  },
  "公开依据 URL": {
    "en": "Public evidence URL",
    "ja": "公開の根拠の URL"
  },
  "验证说明": {
    "en": "Verification notes",
    "ja": "検証の説明"
  },
  "发布实测记录": {
    "en": "Publish test record",
    "ja": "検証記録を公開"
  },
  "撤下错误的实测记录": {
    "en": "Remove an incorrect test record",
    "ja": "誤った検証記録を撤回"
  },
  "公开 JSON 中每条开发者验证含记录编号。撤下不会删除用户报告。": {
    "en": "Each developer verification in public JSON has a record ID. Removing it does not delete user reports.",
    "ja": "公開 JSON の開発者検証には記録 ID があります。撤回してもユーザーのレポートは削除されません。"
  },
  "验证记录编号": {
    "en": "Verification record ID",
    "ja": "検証記録 ID"
  },
  "撤下记录": {
    "en": "Remove record",
    "ja": "記録を撤回"
  },
  "正在读取报告…": {
    "en": "Loading reports…",
    "ja": "レポートを読み込み中…"
  },
  "用户选择公开": {
    "en": "User chose publication",
    "ja": "ユーザーが公開を選択"
  },
  "原始报告私有": {
    "en": "Raw report is private",
    "ja": "元のレポートは非公開"
  },
  "当前筛选没有报告。": {
    "en": "No reports match these filters.",
    "ja": "条件に一致するレポートはありません。"
  },
  "读取完成。凭证和内部哈希不会返回到管理页面。": {
    "en": "Loaded. Credentials and internal hashes are not returned to this dashboard.",
    "ja": "読み込み完了。認証情報と内部ハッシュは管理画面に返されません。"
  },
  "用户选择公开：审核通过后可通过报告编号查阅。": {
    "en": "Publication chosen: accessible by report ID after approval.",
    "ja": "公開を選択：承認後にレポート ID で閲覧できます。"
  },
  "原始报告私有：审核通过只贡献汇总统计。": {
    "en": "Private report: approval contributes only to aggregate statistics.",
    "ja": "非公開レポート：承認後も集計統計にのみ寄与します。"
  },
  "报告编号：": {
    "en": "Report ID: ",
    "ja": "レポート ID："
  },
  "已检查字段与证据": {
    "en": "Fields and evidence checked",
    "ja": "フィールドと根拠を確認済み"
  },
  "疑似重复报告": {
    "en": "Possible duplicate",
    "ja": "重複の疑い"
  },
  "无效报告": {
    "en": "Invalid report",
    "ja": "無効なレポート"
  },
  "需进一步调查": {
    "en": "Needs investigation",
    "ja": "追加調査が必要"
  },
  "纳入社区统计": {
    "en": "Include in community statistics",
    "ja": "コミュニティ統計に追加"
  },
  "排除报告": {
    "en": "Exclude report",
    "ja": "レポートを除外"
  },
  "恢复待审核": {
    "en": "Return to pending review",
    "ja": "審査待ちに戻す"
  },
  "最近审核记录": {
    "en": "Recent review history",
    "ja": "最近の審査履歴"
  },
  "已发布独立实测记录。": {
    "en": "Independent test published.",
    "ja": "独立した検証記録を公開しました。"
  },
  "请检查验证记录编号。": {
    "en": "Check the verification record ID.",
    "ja": "検証記録 ID をご確認ください。"
  },
  "实测记录已撤下。": {
    "en": "Test record removed.",
    "ja": "検証記録を撤回しました。"
  },
  "管理员访问尚未配置，服务已拒绝访问。": {
    "en": "Administrator access is not configured. Access was denied.",
    "ja": "管理者アクセスが未設定のため、アクセスを拒否しました。"
  },
  "请求过于频繁，请稍后重试。": {
    "en": "Too many requests. Try again later.",
    "ja": "リクエストが多すぎます。しばらくしてからお試しください。"
  },
  "报告不存在、已过期、尚未公开，或撤回凭证不正确。": {
    "en": "The report is missing, expired, not public, or the withdrawal credential is incorrect.",
    "ja": "レポートが存在しない、期限切れ、非公開、または撤回用の認証情報が正しくありません。"
  },
  "报告不符合字段或能力证据规则。": {
    "en": "The report does not meet the field or capability evidence rules.",
    "ja": "レポートがフィールドまたは機能の根拠に関する規則に適合していません。"
  },
  "服务尚未完成配置。": {
    "en": "The service is not configured yet.",
    "ja": "サービスはまだ設定されていません。"
  },
  "管理操作必须从当前服务页面发起。": {
    "en": "Administrator actions must originate from this service page.",
    "ja": "管理操作はこのサービスのページから実行してください。"
  },
  "请求失败，请稍后重试。": {
    "en": "Request failed. Try again later.",
    "ja": "リクエストに失敗しました。しばらくしてからお試しください。"
  },
  "收集与处理规则 · FanBar": {
    "en": "Collection and processing policy · FanBar",
    "ja": "収集・処理方針 · FanBar"
  },
  "公开的收集与处理规则": {
    "en": "Public collection and processing policy",
    "ja": "公開の収集・処理方針"
  },
  "完整字段": {
    "en": "All fields",
    "ja": "全フィールド"
  },
  "你能检查我们收集的每个字段。": {
    "en": "You can inspect every field we collect.",
    "ja": "収集するすべてのフィールドを確認できます。"
  },
  "本机检测不需要上报。只有你预览并确认提交时，报告才会发送到当前 FanBar 报告服务。服务由 FanBar 项目维护者运营，使用 Cloudflare Workers 与 D1。": {
    "en": "Local detection requires no submission. Reports are sent to this FanBar service only after you preview and confirm them. FanBar maintainers operate the service using Cloudflare Workers and D1.",
    "ja": "ローカル検出に提出は不要です。プレビューを確認し、提出を承認した場合にのみ、この FanBar サービスへ送信します。FanBar の保守担当者が Cloudflare Workers と D1 で運営しています。"
  },
  "上传哪些内容": {
    "en": "What is uploaded",
    "ja": "アップロードする内容"
  },
  "机型标识、处理器名称、macOS／FanBar／控制服务版本。": {
    "en": "Model identifier, processor name, macOS, FanBar and control-service versions.",
    "ja": "モデル識別子、プロセッサ名、macOS・FanBar・制御サービスのバージョン。"
  },
  "硬件接口报告的风扇数量（如可获取）、所选温度来源。": {
    "en": "Fan count reported by the hardware interface, if available, and selected temperature source.",
    "ja": "ハードウェアインターフェースが報告するファン数（取得可能な場合）と選択した温度ソース。"
  },
  "七项能力状态与标准原因码、每次报告随机生成的编号。": {
    "en": "Seven capability states with standard reason codes and a randomly generated ID for each report.",
    "ja": "7つの機能状態と標準の理由コード、レポートごとにランダム生成する ID。"
  },
  "你是否同意公开单份报告、确认的规则版本。服务器记录接收时间、到期时间和审核状态。": {
    "en": "Your consent to publish the individual report and the policy version you confirmed. The server records receipt time, expiry and review status.",
    "ja": "個別レポートの公開への同意と、確認した方針のバージョン。サーバーは受信日時、有効期限、審査状況を記録します。"
  },
  "不接收序列号、硬件 UUID、用户名、主机名、文件路径、进程列表、温度历史或诊断日志。": {
    "en": "We do not accept serial numbers, hardware UUIDs, usernames, hostnames, file paths, process lists, temperature history or diagnostic logs. ",
    "ja": "シリアル番号、ハードウェア UUID、ユーザー名、ホスト名、ファイルパス、プロセス一覧、温度履歴、診断ログは受け付けません。"
  },
  "查看严格字段 Schema": {
    "en": "View the strict field schema",
    "ja": "厳密なフィールドスキーマを見る"
  },
  "；额外字段、不完整能力列表和不一致的证据会被拒绝。": {
    "en": "; extra fields, incomplete capability lists and inconsistent evidence are rejected.",
    "ja": "。追加フィールド、不完全な機能一覧、矛盾した根拠は拒否します。"
  },
  "哪些数据公开": {
    "en": "What is public",
    "ja": "公開するデータ"
  },
  "报告默认私有，仅管理员可以查看。经审核的报告会贡献公开的机型与版本汇总，统计为报告数，不代表独立设备数。只有你明确选择公开的单份报告，在审核通过后才可以通过报告编号查阅。罕见机型与版本组合也可能具有辨识度，请在提交前评估。": {
    "en": "Reports are private by default and visible only to administrators. Reviewed reports contribute to public model and version aggregates. Counts represent reports, not unique devices. An individual report is accessible by ID only if you explicitly chose publication and it passed review. Rare model and version combinations may be identifying; consider this before submitting.",
    "ja": "レポートは初期設定で非公開で、管理者のみ閲覧できます。審査済みのレポートはモデルとバージョンの公開集計に寄与します。件数はレポート数であり、デバイス数ではありません。明示的に公開を選択し、審査を通過した個別レポートのみ ID で閲覧できます。珍しいモデルとバージョンの組み合わせは識別につながる可能性があるため、提出前にご検討ください。"
  },
  "如何判断兼容性": {
    "en": "How compatibility is assessed",
    "ja": "互換性の評価方法"
  },
  "没有读数或一次失败不等于不支持。控制服务就绪、请求成功和实际转速验证分别处理。社区报告不会自动成为“开发者验证”；开发者实测必须单独发布，附带日期、版本与公开依据。不同结果会保留，不用多数票掩盖差异。": {
    "en": "A missing reading or one failure does not mean unsupported. Control-service readiness, request success and actual fan-speed verification are treated separately. Community reports do not automatically become developer verification. Independent developer tests must be published separately with dates, versions and public evidence. Conflicting results are preserved rather than hidden by majority voting.",
    "ja": "読み取りがないことや一度の失敗は非対応を意味しません。制御サービスの準備状態、リクエスト成功、実際の回転数の検証を個別に扱います。コミュニティレポートが開発者の検証に自動的に変わることはありません。開発者の実機検証は日付、バージョン、公開の根拠を付けて別途公開します。異なる結果は残し、多数決で差異を隠しません。"
  },
  "网络元数据与安全": {
    "en": "Network metadata and security",
    "ja": "ネットワークメタデータとセキュリティ"
  },
  "Cloudflare 为传输和保护服务会处理网络地址等元数据。应用数据库不保存原始 IP；服务只将带密钥且每日变化的网络地址摘要送入短期限流计数器，不用于设备追踪。服务日志不记录报告内容、撤回凭证、请求 URL 或网络地址。Cloudflare 自身的基础设施处理不等于不存在。": {
    "en": "Cloudflare processes metadata such as network addresses to transport and protect the service. The app database does not store raw IP addresses. Only a keyed address digest that changes daily is used in short-lived rate-limit counters, not device tracking. Service logs do not record report contents, withdrawal credentials, request URLs or network addresses. Cloudflare’s own infrastructure processing still exists.",
    "ja": "Cloudflare は通信と保護のため、ネットワークアドレスなどのメタデータを処理します。アプリのデータベースに生の IP は保存しません。鍵付きで毎日変化するアドレスの要約値を短期の制限カウンターにのみ使い、デバイス追跡には使いません。サービスのログにはレポート内容、撤回用の認証情報、リクエスト URL、ネットワークアドレスを記録しません。Cloudflare 自体の基盤での処理は存在します。"
  },
  "管理员接口只能通过 Cloudflare Access 进入，服务端会验证 Access 身份；没有管理密钥。撤回凭证每份报告独立生成，通过请求头发送；数据库只存其 SHA-256 哈希。凭证不进入公开数据或网址。所有生产请求使用 HTTPS。": {
    "en": "Administrator APIs are reachable only through Cloudflare Access, and the service verifies the Access identity; there is no admin key. Each report has its own withdrawal credential, sent in a request header; the database stores only its SHA-256 hash. Credentials never appear in public data or URLs. All production requests use HTTPS.",
    "ja": "管理 API には Cloudflare Access 経由でのみアクセスでき、サービス側で Access の認証を検証します。管理キーはありません。撤回用の認証情報はレポートごとに生成し、ヘッダーで送信します。データベースには SHA-256 ハッシュのみ保存します。認証情報は公開データや URL に含めません。本番の通信はすべて HTTPS です。"
  },
  "保存多久，如何删除": {
    "en": "Retention and deletion",
    "ja": "保存期間と削除"
  },
  "报告在线保留 90 天，到期即停止公开查询与统计，物理数据由每日清理任务删除。你可以在 FanBar 的上报记录中撤回，也可以使用报告编号和撤回凭证在": {
    "en": "Reports remain online for 90 days. Expired reports stop appearing in public queries and statistics; daily cleanup removes the stored data. Withdraw from FanBar’s submission history, or use the report ID and credential on the ",
    "ja": "レポートはオンラインで90日間保存します。期限後は公開検索と統計から除外し、日次の処理でデータを削除します。FanBar の提出履歴から撤回するか、ID と認証情報を使って"
  },
  "撤回页面": {
    "en": "withdrawal page",
    "ja": "撤回ページ"
  },
  "删除。撤回会删除在线报告及相关审核记录，并移除社区统计贡献；独立实测记录不会随用户报告撤回而删除。为防止迟到的请求重新写入同一报告，报告编号与凭证的哈希删除标记会私有保留 90 天，不保留报告内容。": {
    "en": ". Withdrawal deletes the online report and its review history and removes its contribution to community statistics. Independent test records are not removed when a user report is withdrawn. To block delayed requests from recreating a withdrawn report, hashed report-ID and credential deletion markers remain private for 90 days, without report contents.",
    "ja": "から削除できます。撤回でオンラインのレポート、審査履歴、統計への寄与を削除します。独立した実機検証はユーザーレポートの撤回では削除しません。遅れたリクエストによる再登録を防ぐため、ID と認証情報のハッシュ削除マーカーのみを非公開で90日間保存し、レポート内容は保存しません。"
  },
  "在线删除不代表云平台历史恢复点立即清除。D1 历史恢复点按账户计划保留 7 天（免费）或 30 天（付费），因此历史数据最长还可能保留 30 天；不得把旧备份恢复后直接公开上线。公开数据下载或第三方副本无法由本服务追回。": {
    "en": "Online deletion does not immediately erase cloud recovery points. D1 recovery points last 7 days on the free plan or 30 days on a paid plan, so historical data may remain for up to 30 additional days. Old backups must not be restored directly into a public service. This service cannot recall downloaded public data or third-party copies.",
    "ja": "オンラインの削除でクラウドの過去の復元ポイントが即座に消えるわけではありません。D1 は無料プランで7日、有料プランで30日間の復元ポイントを保持するため、過去のデータは最長で追加の30日間残る可能性があります。古いバックアップを復元してそのまま公開することは禁止します。公開データのダウンロードや第三者のコピーは回収できません。"
  },
  "源码与变更": {
    "en": "Source and policy changes",
    "ja": "ソースコードと方針の変更"
  },
  "规则版本为 2026-10-21，新增控制失败证据。FanBar 0.7.0 及更早版本仍按 2026-10-13 规则提交，不包含这些字段。规则变化后，旧确认不能直接用于新提交。": {
    "en": "Policy version: 2026-10-21, which adds control failure evidence. FanBar 0.7.0 and earlier still submit under the 2026-10-13 rules, without these fields. After policy changes, previous consent cannot be used directly for new submissions. ",
    "ja": "方針のバージョンは2026-10-21で、制御失敗の証拠が追加されました。FanBar 0.7.0以前は引き続き2026-10-13の方針で提出し、これらの項目は含みません。変更後の新規提出に以前の同意をそのまま使うことはできません。"
  },
  "控制请求失败时附带固定失败码和有限的数值证据：SMC 键名、返回码、风扇序号、耗时、回读是否为手动模式、是否已恢复系统控制。不上传错误描述文本。": {
    "en": "When a control request fails: a fixed failure code and bounded numeric evidence (SMC key name, result code, fan number, duration, whether readback showed manual mode, and whether system control was restored). No error text is uploaded.",
    "ja": "制御リクエストが失敗した場合：固定の失敗コードと限定的な数値の証拠（SMCキー名、戻り値、ファン番号、所要時間、読み戻しが手動モードだったか、システム制御に戻ったか）。エラーの説明文はアップロードしません。"
  },
  "服务端源码": {
    "en": "Server source code",
    "ja": "サーバーのソースコード"
  },
  "与": {
    "en": " and ",
    "ja": "と"
  },
  "机器可读处理规则": {
    "en": "machine-readable policy",
    "ja": "機械可読の処理方針"
  },
  "公开；问题可在": {
    "en": " are public. Report issues in the ",
    "ja": "を公開しています。問題は"
  },
  "FanBar 仓库": {
    "en": "FanBar repository",
    "ja": "FanBar リポジトリ"
  },
  "反馈，请勿在公开反馈中填写撤回凭证。": {
    "en": ". Do not include withdrawal credentials in public feedback.",
    "ja": "でご報告ください。公開の報告に撤回用の認証情報を含めないでください。"
  },
  "reportCount": {
    "zh-CN": "{count} 份",
    "en": "{count} reports",
    "ja": "{count} 件"
  },
  "pageNumber": {
    "zh-CN": "第 {page} 页",
    "en": "Page {page}",
    "ja": "{page} ページ"
  },
  "浏览器只保存你选择的界面语言；不保存报告、访问密钥或撤回凭证。": {
    "en": "The browser saves only your chosen interface language, never reports, access keys or withdrawal credentials.",
    "ja": "ブラウザーには選択した表示言語のみ保存し、レポート、アクセスキー、撤回用の認証情報は保存しません。"
  },
  "审核报告": {
    "en": "Review reports",
    "ja": "レポートの審査"
  },
  "报告结果": {
    "en": "Reported result",
    "ja": "レポートの結果"
  },
  "原因码": {
    "en": "Reason code",
    "ja": "理由コード"
  },
  "原始字段": {
    "en": "Raw fields",
    "ja": "元のフィールド"
  },
  "审核理由": {
    "en": "Review reason",
    "ja": "審査理由"
  },
  "结果不一致": {
    "en": "Results differ",
    "ja": "結果が一致しない"
  },
  "可用": {
    "en": "Works",
    "ja": "利用可能"
  },
  "请求成功，待实测": {
    "en": "Request succeeded, awaiting test",
    "ja": "リクエスト成功・実機検証待ち"
  },
  "未读取": {
    "en": "Not read",
    "ja": "読み取りなし"
  },
  "暂无证据": {
    "en": "No evidence yet",
    "ja": "根拠なし"
  },
  "开发者实测": {
    "en": "Developer test",
    "ja": "開発者の実機検証"
  },
  "≥10 份报告": {
    "en": "≥10 reports",
    "ja": "10 件以上"
  },
  "1–9 份报告": {
    "en": "1–9 reports",
    "ja": "1〜9 件"
  },
  "点击表格中的任一格，查看结果分布与依据。": {
    "en": "Select any cell to see how reports break down and what supports the result.",
    "ja": "表のセルを選ぶと、結果の内訳と根拠を確認できます。"
  },
  "开发者实测 {count} 项": {
    "en": "{count} developer tests",
    "ja": "開発者の実機検証 {count} 件"
  },
  "报告结果一致，可以作为参考。": {
    "en": "Reports agree, so this result is a useful reference.",
    "ja": "レポートの結果は一致しており、参考にできます。"
  },
  "系统接受了控制请求，但还没有证据证明风扇转速确实改变。": {
    "en": "The system accepted the control request, but there is no evidence yet that the fan speed actually changed.",
    "ja": "システムは制御リクエストを受け付けましたが、ファン回転数が実際に変わった根拠はまだありません。"
  },
  "报告中没有成功读取或执行。这不等于已证实不支持。": {
    "en": "Reports did not read or perform this successfully. That does not prove it is unsupported.",
    "ja": "レポートでは読み取りや実行に成功していません。非対応が確認されたわけではありません。"
  },
  "目前没有报告，也没有开发者实测。": {
    "en": "There are no reports and no developer tests yet.",
    "ja": "レポートも開発者の実機検証もまだありません。"
  },
  "开发者实测确认在此版本组合下不可用。": {
    "en": "A developer test confirmed this does not work with this version combination.",
    "ja": "開発者の実機検証で、このバージョンの組み合わせでは利用できないことを確認しました。"
  },
  "关闭": {
    "en": "Close",
    "ja": "閉じる"
  },
  "开发者已在对应版本实机验证。": {
    "en": "A developer verified this on real hardware with these versions.",
    "ja": "開発者がこのバージョンの実機で検証しました。"
  },
  "报告数是份数，不是设备数。": {
    "en": "Counts are reports, not distinct devices.",
    "ja": "件数はレポート数で、デバイス数ではありません。"
  },
  "实测记录不完整，或验证日期晚于今天。": {
    "en": "The test record is incomplete, or the verification date is in the future.",
    "ja": "検証記録が不完全か、検証日が今日より後になっています。"
  },
  "证据等级 {level}/3": {
    "en": "Evidence level {level}/3",
    "ja": "根拠レベル {level}/3"
  },
  "接收于 {date}": {
    "en": "Received {date}",
    "ja": "{date} に受信"
  },
  "概览": {
    "en": "Overview",
    "ja": "概要"
  },
  "审核记录": {
    "en": "Review log",
    "ja": "審査記録"
  },
  "本报告": {
    "en": "This report",
    "ja": "このレポート"
  },
  "同版本已审核报告": {
    "en": "Reviewed reports, same versions",
    "ja": "同じバージョンの審査済みレポート"
  },
  "对比": {
    "en": "Comparison",
    "ja": "比較"
  },
  "不一致": {
    "en": "Differs",
    "ja": "不一致"
  },
  "一致": {
    "en": "Matches",
    "ja": "一致"
  },
  "同一版本组合还没有其他已审核报告，无法对比。": {
    "en": "No other reviewed reports exist for this version combination yet, so there is nothing to compare.",
    "ja": "このバージョンの組み合わせには、比較できる審査済みレポートがまだありません。"
  },
  "结果冲突本身不是排除理由。字段正常就应纳入，公开页会如实显示“结果不一致”。": {
    "en": "A conflicting result is not a reason to reject. If the fields are valid, include the report; the public page will show “Results differ”.",
    "ja": "結果の食い違いだけでは除外の理由になりません。フィールドが正しければ取り込み、公開ページには「結果が一致しない」と表示されます。"
  },
  "与以下报告内容相同，且相隔不到 10 分钟提交：": {
    "en": "Identical content submitted less than 10 minutes apart:",
    "ja": "同じ内容が 10 分以内に送信されたレポート："
  },
  "结果冲突": {
    "en": "Conflicting result",
    "ja": "結果の食い違い"
  },
  "疑似重复": {
    "en": "Possible duplicate",
    "ja": "重複の疑い"
  },
  "新机型": {
    "en": "New model",
    "ja": "新しい機種"
  },
  "独立实测": {
    "en": "Independent test",
    "ja": "独立した実機検証"
  },
  "更正错误记录": {
    "en": "Correction",
    "ja": "誤った記録の訂正"
  },
  "不到 1 小时": {
    "en": "Under 1 hour",
    "ja": "1 時間未満"
  },
  "{count} 小时": {
    "en": "{count} h",
    "ja": "{count} 時間"
  },
  "{count} 天": {
    "en": "{count} days",
    "ja": "{count} 日"
  },
  "与已审核报告不一致：{items}": {
    "en": "Differs from reviewed reports: {items}",
    "ja": "審査済みレポートと異なる項目：{items}"
  },
  "去审核": {
    "en": "Review",
    "ja": "審査する"
  },
  "与 {count} 份内容相同的报告相隔不到 10 分钟提交": {
    "en": "Submitted less than 10 minutes from {count} identical reports",
    "ja": "同じ内容のレポート {count} 件と 10 分以内に送信"
  },
  "该机型还没有已审核的报告或实测记录。": {
    "en": "This model has no reviewed reports or developer tests yet.",
    "ja": "この機種には審査済みレポートも実機検証もまだありません。"
  },
  "待开发者实测": {
    "en": "Awaiting developer test",
    "ja": "開発者の実機検証待ち"
  },
  "“请求成功” {count} 份": {
    "en": "{count} “request succeeded” reports",
    "ja": "「リクエスト成功」{count} 件"
  },
  "安排实测": {
    "en": "Plan a test",
    "ja": "実機検証を予定"
  },
  "最久已等待 {time}": {
    "en": "Oldest waiting {time}",
    "ja": "最長待ち時間 {time}"
  },
  "队列已清空": {
    "en": "Queue is clear",
    "ja": "キューは空です"
  },
  "本周收到": {
    "en": "Received this week",
    "ja": "今週の受信"
  },
  "上周 {count} 份": {
    "en": "{count} last week",
    "ja": "先週 {count} 件"
  },
  "本周纳入 / 排除": {
    "en": "Included / rejected this week",
    "ja": "今週の取り込み / 除外"
  },
  "只统计审核决定，不含撤回的报告": {
    "en": "Review decisions only; withdrawn reports are not counted",
    "ja": "審査の決定のみ。撤回されたレポートは含みません"
  },
  "满足条件、尚未实测的组合": {
    "en": "Combinations that qualify and are not yet tested",
    "ja": "条件を満たし、まだ実機検証されていない組み合わせ"
  },
  "需要关注": {
    "en": "Needs attention",
    "ja": "要確認"
  },
  "基于最早的 {count} 份待审核报告": {
    "en": "Based on the oldest {count} pending reports",
    "ja": "最も古い保留中レポート {count} 件に基づく"
  },
  "暂无需要关注的事项。": {
    "en": "Nothing needs attention.",
    "ja": "確認が必要な項目はありません。"
  },
  "每日新报告": {
    "en": "New reports per day",
    "ja": "日別の新着レポート"
  },
  "过去 14 天每日新报告": {
    "en": "New reports per day over the last 14 days",
    "ja": "過去 14 日間の日別新着レポート"
  },
  "今天": {
    "en": "Today",
    "ja": "今日"
  },
  "最近操作": {
    "en": "Recent activity",
    "ja": "最近の操作"
  },
  "暂无审核记录。": {
    "en": "No review records yet.",
    "ja": "審査記録はまだありません。"
  },
  "累计 ≥{count} 份已审核的“请求成功”报告、尚无实测记录的控制能力": {
    "en": "Control capabilities with at least {count} reviewed “request succeeded” reports and no developer test",
    "ja": "審査済みの「リクエスト成功」レポートが {count} 件以上あり、実機検証がまだない制御機能"
  },
  "暂无需要安排实测的组合。": {
    "en": "No combinations need a developer test.",
    "ja": "実機検証が必要な組み合わせはありません。"
  },
  "机型": {
    "en": "Model",
    "ja": "機種"
  },
  "版本组合": {
    "en": "Versions",
    "ja": "バージョンの組み合わせ"
  },
  "最近报告": {
    "en": "Latest report",
    "ja": "最新のレポート"
  },
  "填写实测": {
    "en": "Record test",
    "ja": "検証結果を入力"
  },
  "已发布的实测记录": {
    "en": "Published developer tests",
    "ja": "公開済みの実機検証"
  },
  "撤下不会删除用户报告。": {
    "en": "Removing a test does not delete user reports.",
    "ja": "取り下げてもユーザーのレポートは削除されません。"
  },
  "还没有发布实测记录。": {
    "en": "No developer tests published yet.",
    "ja": "公開済みの実機検証はまだありません。"
  },
  "确认撤下": {
    "en": "Confirm removal",
    "ja": "取り下げを確定"
  },
  "记录每个审核和实测决定。审核记录保留 90 天；用户撤回报告时，相关审核记录一并删除。": {
    "en": "Every review and test decision is recorded. Records are kept for 90 days; when a user withdraws a report, its review records are deleted too.",
    "ja": "すべての審査と実機検証の決定を記録します。記録は 90 日間保存し、ユーザーがレポートを撤回すると関連する審査記録も削除されます。"
  },
  "记录类型": {
    "en": "Record type",
    "ja": "記録の種類"
  },
  "报告审核": {
    "en": "Report reviews",
    "ja": "レポート審査"
  },
  "操作者": {
    "en": "Actor",
    "ja": "操作者"
  },
  "操作": {
    "en": "Action",
    "ja": "操作"
  },
  "对象": {
    "en": "Subject",
    "ja": "対象"
  },
  "已删除或已过期": {
    "en": "Deleted or expired",
    "ja": "削除済みまたは期限切れ"
  },
  "管理后台": {
    "en": "Admin",
    "ja": "管理画面"
  },
  "管理后台 · FanBar": {
    "en": "Admin · FanBar",
    "ja": "管理画面 · FanBar"
  },
  "管理密钥（旧记录）": {
    "en": "Administrator key (legacy)",
    "ja": "管理キー（旧記録）"
  },
  "本地开发": {
    "en": "Local development",
    "ja": "ローカル開発"
  },
  "兼容性报告": {
    "en": "Compatibility reports",
    "ja": "互換性レポート"
  },
  "更新统计": {
    "en": "Update statistics",
    "ja": "アップデート統計"
  },
  "未登录": {
    "en": "Not signed in",
    "ja": "未ログイン"
  },
  "本地开发，未经过 Access": {
    "en": "Local development, not through Access",
    "ja": "ローカル開発（Access を経由していません）"
  },
  "已通过 Cloudflare Access 登录": {
    "en": "Signed in through Cloudflare Access",
    "ja": "Cloudflare Access でログイン済み"
  },
  "没有有效的 Access 会话": {
    "en": "No valid Access session",
    "ja": "有効な Access セッションがありません"
  },
  "会话到期": {
    "en": "Session expires",
    "ja": "セッションの有効期限"
  },
  "审核记录署名": {
    "en": "Reviews signed as",
    "ja": "審査記録の署名"
  },
  "退出登录": {
    "en": "Sign out",
    "ja": "ログアウト"
  },
  "本地开发模式": {
    "en": "Local development mode",
    "ja": "ローカル開発モード"
  },
  "未经过 Cloudflare Access，所有操作署名为 local-development。只在 localhost 且 ENVIRONMENT=development 时生效。": {
    "en": "Cloudflare Access is bypassed and every action is signed as local-development. This only applies on localhost with ENVIRONMENT=development.",
    "ja": "Cloudflare Access を経由せず、すべての操作は local-development として署名されます。localhost かつ ENVIRONMENT=development の場合のみ有効です。"
  },
  "登录已过期": {
    "en": "Your session has expired",
    "ja": "ログインの有効期限が切れました"
  },
  "Cloudflare Access 会话已到期，后台数据不再显示。重新登录后会回到当前页面。": {
    "en": "The Cloudflare Access session has expired, so admin data is hidden. Sign in again to return to this page.",
    "ja": "Cloudflare Access のセッションが期限切れのため、管理データを表示できません。再ログインするとこのページに戻ります。"
  },
  "重新登录": {
    "en": "Sign in again",
    "ja": "再ログイン"
  },
  "后台尚未配置 Cloudflare Access": {
    "en": "Cloudflare Access is not configured for the admin",
    "ja": "管理画面に Cloudflare Access が設定されていません"
  },
  "所有管理接口都返回 403。不会退回到密钥登录。": {
    "en": "Every admin endpoint returns 403. There is no fallback to key sign-in.",
    "ja": "すべての管理 API は 403 を返します。キーによるログインには戻りません。"
  },
  "需要维护者完成配置": {
    "en": "The maintainer needs to finish setup",
    "ja": "メンテナーによる設定が必要です"
  },
  "在 Zero Trust 新建自托管应用，路径为 /admin* 和 /api/admin/*": {
    "en": "In Zero Trust, create a self-hosted application for /admin* and /api/admin/*",
    "ja": "Zero Trust で /admin* と /api/admin/* を対象にセルフホストアプリケーションを作成します"
  },
  "策略只允许维护者邮箱": {
    "en": "Allow only the maintainer's email in the policy",
    "ja": "ポリシーではメンテナーのメールアドレスのみ許可します"
  },
  "在 Worker 设置 ACCESS_TEAM_DOMAIN 和 ACCESS_AUD 后重新部署": {
    "en": "Set ACCESS_TEAM_DOMAIN and ACCESS_AUD on the Worker, then redeploy",
    "ja": "Worker に ACCESS_TEAM_DOMAIN と ACCESS_AUD を設定して再デプロイします"
  },
  "查看部署说明": {
    "en": "Read the deployment notes",
    "ja": "デプロイ手順を見る"
  },
  "新": {
    "en": "New",
    "ja": "新規"
  },
  "来自 update.getfanbar.com 的更新检查计数。这里显示完整数据，包括公开页隐藏的少于 5 的分组。": {
    "en": "Update check counts from update.getfanbar.com. This view shows complete data, including groups under 5 that the public page hides.",
    "ja": "update.getfanbar.com のアップデート確認回数です。公開ページでは非表示になる 5 未満のグループも含め、すべてのデータを表示します。"
  },
  "仅管理员可见": {
    "en": "Admins only",
    "ja": "管理者のみ表示"
  },
  "时间范围": {
    "en": "Time range",
    "ja": "期間"
  },
  "最近 {count} 天": {
    "en": "Last {count} days",
    "ja": "過去 {count} 日間"
  },
  "较前 {count} 天": {
    "en": "vs previous {count} days",
    "ja": "前の {count} 日間比"
  },
  "还没有更新检查": {
    "en": "No update checks yet",
    "ja": "アップデート確認はまだありません"
  },
  "第一次检查之后，这里会按天显示计数。": {
    "en": "Daily counts appear here after the first check.",
    "ja": "最初の確認以降、日ごとの回数がここに表示されます。"
  },
  "今天（UTC）": {
    "en": "Today (UTC)",
    "ja": "今日（UTC）"
  },
  "截至 {time} UTC": {
    "en": "As of {time} UTC",
    "ja": "{time} UTC 時点"
  },
  "开启统计": {
    "en": "Opted in",
    "ja": "統計に参加"
  },
  "本周 {optedIn} / {checks} 次检查带设备信息": {
    "en": "{optedIn} of {checks} checks this week included device details",
    "ja": "今週 {checks} 回中 {optedIn} 回にデバイス情報あり"
  },
  "其他": {
    "en": "Other",
    "ja": "その他"
  },
  "每日更新检查": {
    "en": "Daily update checks",
    "ja": "日ごとのアップデート確認"
  },
  "版本分布": {
    "en": "Versions",
    "ja": "バージョン別"
  },
  "版本": {
    "en": "Version",
    "ja": "バージョン"
  },
  "检查": {
    "en": "Checks",
    "ja": "確認回数"
  },
  "占比": {
    "en": "Share",
    "ja": "割合"
  },
  "不在发布列表": {
    "en": "Not a release",
    "ja": "リリース一覧にない"
  },
  "最新": {
    "en": "Latest",
    "ja": "最新"
  },
  "服务状态": {
    "en": "Service status",
    "ja": "サービスの状態"
  },
  "每日任务": {
    "en": "Daily task",
    "ja": "日次タスク"
  },
  "今天已运行": {
    "en": "Ran today",
    "ja": "今日実行済み"
  },
  "上次运行于 {day}": {
    "en": "Last ran on {day}",
    "ja": "最終実行日 {day}"
  },
  "尚未运行": {
    "en": "Has not run yet",
    "ja": "まだ実行されていません"
  },
  "由当天第一次检查触发": {
    "en": "Triggered by the day's first check",
    "ja": "その日最初の確認で実行"
  },
  "已发布版本": {
    "en": "Releases",
    "ja": "リリース済み"
  },
  "发布列表为空": {
    "en": "No releases listed",
    "ja": "リリース一覧は空です"
  },
  "计为 other": {
    "en": "Counted as other",
    "ja": "other として集計"
  },
  "本周 {count} 次": {
    "en": "{count} this week",
    "ja": "今週 {count} 回"
  },
  "版本号不在发布列表（测试版或伪造请求）": {
    "en": "Version not in the release list (test build or forged request)",
    "ja": "リリース一覧にないバージョン（テスト版または偽装リクエスト）"
  },
  "公开统计": {
    "en": "Public stats",
    "ja": "公開統計"
  },
  "边缘缓存 1 小时 · 隐藏少于 {count} 的分组": {
    "en": "Edge-cached for 1 hour · hides groups under {count}",
    "ja": "エッジで 1 時間キャッシュ · {count} 未満のグループは非表示"
  },
  "计数限流": {
    "en": "Count rate limit",
    "ja": "集計の回数制限"
  },
  "每个地址每分钟 10 次": {
    "en": "10 per address per minute",
    "ja": "アドレスごとに毎分 10 回"
  },
  "超出只跳过计数，仍然跳转": {
    "en": "Beyond that the check is not counted, but still redirects",
    "ja": "超過分は集計されませんが、リダイレクトは行われます"
  },
  "Mac 型号": {
    "en": "Mac model",
    "ja": "Mac モデル"
  },
  "芯片": {
    "en": "Chip",
    "ja": "チップ"
  },
  "国家 / 地区": {
    "en": "Country / region",
    "ja": "国 / 地域"
  },
  "开始统计的周": {
    "en": "Week opted in",
    "ja": "参加開始週"
  },
  "未收录的新机型": {
    "en": "New model not yet listed",
    "ja": "未収録の新モデル"
  },
  "Apple 芯片 · arm64": {
    "en": "Apple silicon · arm64",
    "ja": "Apple シリコン · arm64"
  },
  "早期版本（无记录）": {
    "en": "Earlier versions (no record)",
    "ja": "以前のバージョン（記録なし）"
  },
  "开启统计的设备": {
    "en": "Opted-in devices",
    "ja": "統計に参加しているデバイス"
  },
  "只来自开启统计的用户；各维度分开计数，不能交叉": {
    "en": "Opted-in users only. Each dimension is counted separately and cannot be cross-referenced.",
    "ja": "統計に参加したユーザーのみ。各項目は個別に集計され、組み合わせることはできません。"
  },
  "统计周": {
    "en": "Week",
    "ja": "集計週"
  },
  "{week}（本周）": {
    "en": "{week} (this week)",
    "ja": "{week}（今週）"
  },
  "这一周没有数据": {
    "en": "No data for this week",
    "ja": "この週のデータはありません"
  },
  "未公开": {
    "en": "Not public",
    "ja": "非公開"
  },
  "开启统计的检查": {
    "en": "Opted-in checks",
    "ja": "統計参加の確認回数"
  },
  "近 {count} 周": {
    "en": "Last {count} weeks",
    "ja": "過去 {count} 週"
  },
  "Cloudflare Access 会话已到期，请重新登录。": {
    "en": "Your Cloudflare Access session has expired. Sign in again.",
    "ja": "Cloudflare Access のセッションが期限切れです。再ログインしてください。"
  },
  "更新服务暂时无法读取，兼容性后台不受影响。请稍后刷新。": {
    "en": "The update service cannot be read right now. The compatibility admin is unaffected. Refresh later.",
    "ja": "アップデートサービスを読み取れません。互換性の管理画面には影響ありません。しばらくしてから更新してください。"
  },
  "时间范围只能是 7、30 或 90 天。": {
    "en": "The time range must be 7, 30 or 90 days.",
    "ja": "期間は 7、30、90 日のいずれかです。"
  }
};
