# Cranny — Chinese, Traditional (繁體中文, zh-Hant / macOS zh_TW) terminology sheet

Register and typography (follow macOS 27 Traditional Chinese, Taiwan vocabulary; zh-HK falls back here):

- Address the user as 你 (never 您), as macOS does. Sentences (footnotes, errors, permission reasons, VoiceOver
  announcements) end in 。; buttons, menu items, toggles, pickers and headers are short verb or noun phrases without
  final punctuation (打開, 加入小工具, 顯示選單列圖像).
- Apple's verbs: Open 打開 · Close 關閉 · Quit 結束 · Add 加入 · New 新增 · Remove 移除 · Delete 刪除 · Copy 拷貝
  (Duplicate = 複製) · Undo 還原 · Show/Hide 顯示/隱藏 · Turn on/off 開啟/關閉 · Click 按一下 · Double-click 按兩下 ·
  Drag 拖移 · Try again 再試一次 · Skip 略過 · Continue 繼續 · Cancel 取消 · Done 完成 · Rename 重新命名.
- Questions as Apple does: 要刪除「%@」嗎？ · 要重置所有設定嗎？
- No spaces between Chinese and Latin text, digits or placeholders (打開Cranny, %lld個項目, macOS 14.2或以上版本);
  Latin words keep their own spaces (Apple Events, Liquid Glass, Force Touch). One exception, as Finder numbers copies
  (未命名檔案夾 2): a numbered default name keeps the space (未命名 %lld); a page is 第%lld頁.
- Quotes 「…」 (secondary 『…』) around app names, System Settings panes and settings in running text and in buttons that
  name them, exactly as macOS: 打開「系統設定」, 在「捷徑」中, 「隱私權與安全性」▸「輔助使用」, 打開「%@」. Cranny's own name
  is never quoted (關於Cranny, 結束Cranny). User content in 「%@」 (要刪除「%@」嗎？).
- Full-width punctuation ，。：；？！（）; full-width colon with no space (狀態：%@); full-width parentheses around
  Chinese or placeholders (自動（%@）, 版本%1$@（%2$@）). Separator " · " and arrows/keys (⌘K, ⌥←) kept as in English;
  ▸ between Settings path parts without spaces (「設定」▸「權限」).
- Ellipsis: macOS zh_TW writes the midline ellipsis ⋯ (U+22EF) in every menu item and progress text (設定⋯, 載入中⋯,
  886 of 886 system strings that end in "…" in English). Cranny follows macOS: ⋯, never "..." and not U+2026.
  Review decision: keep ⋯, so Cranny's 設定⋯ / 檢查更新項目⋯ match the system menus beside them; the generic U+2026
  note in languages.json is the template line shared by every language (the validator accepts both).
- Instructions: Apple's zh_TW writes "verb + 來 + purpose" (按一下來評分此遊戲, 拖移來變更縮放, 用三指點兩下並拖移來…), so
  按兩下來重新命名, 拖移來重新排序 and 向下拉來打開 follow macOS; don't "correct" them to 以.
- Literary particles (之, 其 in place of 它的) are avoided in short UI copy; plain modern phrasing as macOS.
- Search keyword lists keep the ASCII separator of the English key (", " or a space): the code splits on it. They may add
  the English word as an extra synonym (HUD, OSD, Spotify).
- No grammatical plural: every plural key has the single form `other`; counters 個 (items, apps), 項 (to-dos), 格 (grid
  cells), 天, 分鐘, 毫秒. Units as macOS: %@點 (pt), %@像素 (px), %lld毫秒 (ms).
- Width: CJK glyphs are ≈ 1 em wide; the compact wing (48 pt at 13 pt) holds 3 characters. Wing words: 完成, 失敗,
  已拷貝, 已暫停, 已恢復, 嗨.

| English | 繁體中文 | Note |
|---|---|---|
| Cranny | Cranny | never translated or transliterated; no space around it (打開Cranny) |
| notch | 瀏海 | the usual Taiwan word for the camera notch; camera housing = 相機外殼 |
| open panel / panel | 面板 | |
| Home (built-in page) | 主頁 | header tab |
| page | 頁面 | default page name Page %lld = 第%lld頁; Pages = 頁面 |
| Tray | 托盤 | 保留在托盤 / 從托盤移除 / 清空托盤; header tab |
| item (Tray) | 項目 | %lld個項目 (as Finder) |
| Layout & Widgets | 佈局與小工具 | Settings pane; Apple's 佈局 |
| layout | 佈局 | 編輯佈局 |
| widget / widget library | 小工具 / 小工具庫 | Apple's 小工具 |
| cell (grid) | 格 | %lld格; "N cells left" = 剩餘%lld格 |
| Live Activities (pane) / a live activity | 即時動態 | Apple's own zh_TW term; one activity is also 即時動態 |
| peek | 速覽 | a noun: never 預覽 (= Preview) or 快速查看 (= Quick Look). Toggles say …時顯示速覽 (曲目變更時顯示速覽, 變化時顯示速覽, 懸浮時顯示速覽, 剩下一分鐘時顯示速覽), not …時速覽 |
| satellite | 衛星 | the second activity in a small circle |
| fold away (compact inactivity) | 收合 | 閒置後收合 |
| HUD | 指示器 | 音量與亮度指示器; Show the HUD for = 為以下項目顯示指示器; search keywords also list HUD, OSD |
| pipeline / step | 流程 / 步驟 | 你的流程, 已釘選的流程, 新增流程⋯ |
| drop zone | 放置區 | AirDrop zone = AirDrop放置區 |
| drag / drop | 拖移 / 拖放 | 將檔案拖移到瀏海上 |
| click | 按一下 | 按一下瀏海 |
| pointer / hover | 指標 / 懸浮 | Hover delay = 懸浮延遲 (Apple: 懸浮延遲); rest the pointer = 將指標停在… |
| pin, Keep Cranny open | 釘選 / 保持Cranny打開 | Unpin = 取消釘選Cranny, Toggle pin = 切換釘選, pin button = 圖釘按鈕 |
| Demo mode | 示範模式 | Apple's 示範模式 |
| tutorial | 教學 | 顯示教學, 略過教學; never 導覽 in UI (search keyword only) |
| Welcome / setup | 歡迎使用 / 設定 | 略過設定 |
| Quick Apps | 快速App | |
| tile | 圖塊 | 編輯圖塊 |
| Shortcuts (Apple's app) | 捷徑 | 「捷徑」 in running text and buttons |
| shortcut (Shortcuts item) | 捷徑 | names quoted: 執行「%@」 |
| keyboard shortcut | 快速鍵 | Apple's 快速鍵 |
| Mirror | 鏡子 | 「鏡子」小工具 |
| Notes / note | 筆記 | Cranny's own notes; not 備忘錄 (= Apple's Notes app); New note = 新增筆記, New notes (mode picker) = 新筆記模式 |
| To-dos / to-do | 待辦事項 | 剩下%lld項 |
| Timer / preset | 計時器 / 預設組 | Apple Clock's words |
| Calendar / event / meeting | 行事曆 / 行程 / 會議 | Apple Calendar's 行程 |
| Join (meeting) | 加入 | capsule 加入; VoiceOver 加入會議; Open meetings in [App / Browser] = 會議打開方式 [在App中 / 在瀏覽器中] |
| Meeting soon / Meeting in progress | 會議即將開始 / 會議進行中 | |
| Media / Now Playing | 媒體 / 播放中 | |
| player / track / song / artwork | 播放器 / 曲目 / 歌曲 / 插圖 | Apple Music's 插圖 |
| visualizer (Off / Static / Ambient / Live) | 視覺效果（關閉 / 靜態 / 氛圍 / 即時） | |
| media helper | 媒體輔助程式 | |
| Apple Events fallback | Apple Events備援方式 | |
| Settings (Cranny) | 設定 | Settings… = 設定⋯ |
| System Settings | 系統設定 | 打開「系統設定」 |
| Permissions (pane) | 權限 | |
| access (to calendars, camera, Bluetooth) | 取用權限 in sentences (行事曆取用權限已關閉。); 權限 in short labels | Access is off = 權限已關閉; Camera access is off / restricted = 相機權限已關閉 / 相機權限受限 (never the bare 取用已關閉) |
| Managed by your organization | 由你的組織管理 | Apple's 你的組織 (not 機構) |
| Allow / Grant | 允許 | Allow… / Grant… = 允許⋯ |
| Allowed / Granted | 已允許 | |
| Denied / Restricted / Not yet / Unknown | 已拒絕 / 受限制 / 尚未設定 / 未知 | permission pills |
| Reset to Default | 重置為預設值 | Changed from the default = 與預設值不同 |
| Remove (from a list, Tray, Quick Apps) | 移除 | a widget, page or note: 刪除 only where English says Delete |
| Dismiss | 隱藏 (an activity, a reminder); 關閉 (a banner) | |
| Done / Failed / Copied (wing words) | 完成 / 失敗 / 已拷貝 | 3 characters fit the 48-pt wing |
| Paused / Resumed (wing words) | 已暫停 / 已恢復 | Pause/Resume Live Activities = 暫停/恢復即時動態 |
| Accent | 強調顏色 | as System Settings ▸ Appearance |
| Ambient light / Underglow / Album glow | 環境光 / 底部光暈 / 專輯光暈 | |
| Quality (the light: Detailed · Efficient) | 品質 (精細 · 高效率) | Settings ▸ Appearance ▸ Light; not 節能 (it saves memory, battery is not promised); search keywords 記憶體 · 效能 |
| Motion: Calm / Standard / Lively / Instant | 動畫：平穩 / 標準 / 活潑 / 立即 | 動態 is taken by 即時動態 |
| Density: Compact / Standard / Roomy | 密度：緊湊 / 標準 / 寬鬆 | |
| Floating island / Attached / Glass island | 浮動島 / 貼齊頂端 / 玻璃島 | as 動態島 |
| handle | 把手 | Visible / Hidden until hover = 一律顯示 / 懸浮時才顯示 |
| Type to capture | 輸入即記錄 | |
| Command palette | 指令面板 | |
| Make way for the menu bar | 讓位給選單列 | |
| Excluded apps | 排除的App | Media ▸ Ignore apps (row label and file-picker button) = 忽略App |
| App not installed | App未安裝 | |
| Never (timeout 0) | 永不 | |
| Brightness / Volume / Mute | 亮度 / 音量 / 靜音 | |
| Try again / Retry | 再試一次 | |
| Untitled | 未命名 | |
| release (publish) | 發佈 | Apple's spelling (已發佈); GitHub releases = 發行版本 |
| Quick Look · Reveal in Finder · Share… | 快速查看 · 顯示於Finder · 分享⋯ | |
| Zip · Unzip · Compress (images) · Make PDF | 製作Zip · 解壓縮 · 壓縮 · 製作PDF | archive base name 封存 (as Finder) |
| Apple's names | from `apple-terms.py zh-Hant` | 輔助使用, 隱私權與安全性, 登入項目, 低耗電模式, 不以顏色來區分, 減少動態效果, 減少透明度, 快速查看, 藍牙, 下載項目; alert sounds keep their English names (Boop, Crystal, Mezzo…) as macOS 27 zh_TW does |
