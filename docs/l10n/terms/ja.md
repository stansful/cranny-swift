# Cranny — Japanese (日本語, ja) terminology sheet

Register and typography (follow macOS 27 Japanese):

- Sentences (footnotes, errors, permission reasons, VoiceOver announcements) in polite です／ます; buttons, menu items,
  toggles, pickers and headers are short noun phrases or verb dictionary forms (開く, 追加, 削除, 〜を表示).
- Tutorial bubbles and coach marks are short instructions without です／ます («ノッチをクリック»). A bubble that is
  followed by a key cap ends in «次のキーを押す» so the key cap reads naturally after it.
- Card descriptions on the Welcome window use ます (ノッチをクリックして開きます).
- VoiceOver hints describe the result in ます form (カメラをオフにします).
- No spaces between Japanese and Latin text or digits (Crannyを開く, 4セル, macOS 14.2以降); spaces stay between two
  Latin words or a Latin word and a number (Cranny %@, 名称未設定 %lld as in Finder/TextEdit).
- Quotes “…” (never 「」, the validator rejects them) around names that could be misread: app names in running text
  (“ミュージック”, “ショートカット”), System Settings panes and settings (“プライバシーとセキュリティ”,
  “カラー以外で区別”), user content (“%@”を削除しますか?). No quotes in a button that names the app it opens
  (システム設定を開く, %@を開く) — Apple writes it that way.
- Half-width colon + space (状況: %@), full-width parentheses （ ） around Japanese and placeholders as macOS
  (自動（%@）, バージョン%@（%@）), half-width ? after a question, 、。 punctuation, … (U+2026), 〜 (U+301C) for ranges
  in running text, ▸ with spaces in Settings paths (設定 ▸ キーボード).
- Search keyword lists keep the English separator (", " or a space): the code splits on it.
- No grammatical plural: every plural key has the single form `other`; counters 件 (events, to-dos), 項目 (Tray
  items, as Finder), 個 (overflow tiles), セル (grid cells), 日, 分, ミリ秒.

| English | 日本語 | Note |
|---|---|---|
| Cranny | Cranny | never translated or transliterated; no space before particles (Crannyを開く) |
| notch | ノッチ | camera housing = カメラハウジング |
| open panel / panel | パネル | |
| Home (built-in page) | ホーム | header tab |
| page | ページ | |
| Tray | トレイ | トレイに保持 / トレイから取り除く / トレイを消去 |
| item (Tray) | 項目 | %lld項目, as Finder |
| Layout & Widgets | レイアウトとウィジェット | Settings pane |
| layout | レイアウト | レイアウトを編集 |
| widget / widget library | ウィジェット / ウィジェットライブラリ | |
| cell (grid) | セル | %lldセル; "N cells left" = 空き%lldセル |
| Live Activities (pane, Cranny's name) | ライブアクティビティ | Apple's own Japanese term |
| live activity (one) | アクティビティ | |
| peek | ミニ表示 | never プレビュー (= Preview) or クイックルック (= Quick Look) |
| satellite | サテライト | |
| fold away | 格納 | 操作がないときに格納 |
| compact (beside the camera) | コンパクト | |
| HUD | インジケータ | Apple katakana style without final ー; search keywords also list HUD, OSD |
| pipeline / step | パイプライン / ステップ | Your pipelines = マイパイプライン |
| drop zone | ドロップ領域 | AirDrop zone = AirDrop領域 |
| drag / drop | ドラッグ / ドロップ | ここにファイルをドロップ |
| click | クリック | |
| pointer / hover | ポインタ / ポインタを置く | Hover delay = ポインタを置く時間 |
| pin, Keep Cranny open | 固定 / Crannyを開いたままにする | Unpin = 固定を解除, Toggle pin = 固定のオン/オフ, pin button = ピンボタン |
| Demo mode | デモモード | |
| tutorial | チュートリアル | never ツアー in UI (search keyword only) |
| Welcome / setup | ようこそ / セットアップ | |
| Quick Apps | クイックアプリ | |
| tile | タイル | |
| Shortcuts (Apple's app) | ショートカット | “ショートカット” in running text |
| shortcut (Shortcuts item) | ショートカット | names quoted: “%@”を実行 |
| keyboard shortcut | キーボードショートカット | also the section header in Settings ▸ Keyboard, so it is not confused with the Shortcuts pane; short ショートカット only in rows inside that pane (ショートカットを記録, “%@”のショートカット) |
| Mirror | ミラー | ミラーウィジェット |
| Notes / note | メモ | 新規メモ, as Apple Notes |
| To-dos / to-do | ToDo | 新規ToDo, 残り%lld件 |
| Timer / preset | タイマー / プリセット | |
| Calendar / event / meeting | カレンダー / イベント / ミーティング | |
| Join (meeting) | 参加 | capsule 参加; VoiceOver ミーティングに参加 |
| Meeting soon / Meeting in progress | まもなくミーティング / ミーティング中 | |
| Media / Now Playing | メディア / 再生中 | |
| player / track / song | プレーヤー / トラック / 曲 | |
| artwork | アートワーク | |
| visualizer (Off/Static/Ambient/Live) | ビジュアライザ（オフ/静止/アンビエント/ライブ） | |
| media helper | メディアヘルパー | |
| Apple Events fallback | Apple Eventsの代替手段 | Apple Events kept as the technology name |
| Settings (Cranny) | 設定 | Settings… = 設定… |
| System Settings | システム設定 | button: システム設定を開く |
| Permissions (pane) | アクセス許可 | |
| Allow / Grant | 許可 | Allow… / Grant… = 許可… |
| Allowed / Granted | 許可済み | |
| Denied / Restricted / Not yet / Unknown | 拒否 / 制限あり / 未設定 / 不明 | permission pills |
| Reset to Default | デフォルトに戻す | Changed from the default = デフォルトから変更済み |
| Remove (from a list, Tray, Quick Apps) | 取り除く | Delete = 削除; a widget or page is 削除 |
| Dismiss | 閉じる; an activity: 非表示にする | Swipe up to dismiss = 上にスワイプして非表示 |
| Done / Failed / Copied (wing words) | 完了 / 失敗 / コピー済 | macOS writes コピー済 (copy progress); 50 pt, fits the 72-pt wide wing |
| Paused / Resumed (wing words) | 一時停止 / 再開 | |
| Accent | アクセントカラー (HUD color option: アクセント) | |
| Ambient light / Underglow | 環境光 / アンダーグロー | |
| Quality (the light: Detailed · Efficient) | 品質 (高精細 · 軽量) | Settings ▸ Appearance ▸ Light; never 省エネ (it saves memory, battery is not promised) or 詳細 (= details); search keywords メモリ · パフォーマンス |
| Motion: Calm / Standard / Lively / Instant | 動き: 穏やか / 標準 / 活発 / 即時 | |
| Density: Compact / Standard / Roomy | 密度: コンパクト / 標準 / ゆったり | |
| Floating island / Attached / Glass island | フローティングアイランド / 上端に密着 / ガラスアイランド | as ダイナミックアイランド |
| handle | ハンドル | |
| Type to capture | タイプ入力で書き留める | macOS says タイプ入力 (Siriにタイプ入力); タイプで alone reads as “by type” |
| Command palette | コマンドパレット | |
| Confirmations (Live Activities row: Copied, Paused…) | 確認メッセージ | |
| Tray ▸ Storage (section) / Save results / Next to the original | ストレージ / 結果の保存先 / 元のファイルと同じ場所 | Storage is never 保存, the verb |
| zip archive | ZIPアーカイブ | as macOS; pipeline step Zip = ZIPに圧縮 |
| Alerts keep their own colors | アラートは専用の色で表示されます | |
| weekday + time (pause status) | %1$@曜日 %2$@ | the weekday argument is one kanji (木) |
| Make way for the menu bar | メニューバーを優先 | |
| Excluded apps | 除外するアプリ | |
| App not installed | インストールされていないアプリ | |
| Never (timeout 0) | しない | |
| Brightness / Volume / Mute | 輝度 / 音量 / 消音 | as macOS keyboard settings |
| Try again / Retry | 再試行 | |
| Untitled | 名称未設定 | |
| Apple's names | from `apple-terms.py ja` | アクセシビリティ, プライバシーとセキュリティ, ログイン項目, 低電力モード, カラー以外で区別, 視差効果を減らす, 透明度を下げる, クイックルック; alert sounds keep their English names (Boop, Crystal, Mezzo…) as macOS 27 Japanese does |

Reviewed 2026-10-14 (independent review).
