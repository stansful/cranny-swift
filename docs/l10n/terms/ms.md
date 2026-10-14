# Cranny — Malay (ms, Bahasa Melayu) terminology sheet

Register: **anda** in lower case, as macOS. Buttons, menu items and toggles use the bare imperative ("Buka",
"Tunjukkan", "Keluarkan", "Jeda"), as Apple's Malay does. Where English uses Title Case (menu items, buttons,
standard AppKit chrome) the Malay is Title Case too ("Semak Kemas Kini…", "Keluar daripada Cranny", "Alih ke
Bawah"); function words stay lower case (ke, di, dari, daripada, dalam, dan, untuk, pada, kepada, dengan).
Settings rows, toggles, footnotes and VoiceOver text are sentence case.
Typography: quotes “…” (‘…’ inside), the apostrophe ’, one-character ellipsis …, " ▸ " in Settings paths with
Apple's pane names unquoted (as Apple's Malay writes "Seting Sistem > Privasi & Keselamatan > Foto"); a setting or
button named inside a sentence is quoted (“Kurangkan pergerakan”, “Sertai”, “Simpan di Rak”); Apple's apps are not
("app Muzik", "app Pintasan"), user-made names are (“%@” for notes and shortcuts). No serial comma ("fon, tataletak
dan warna"), as Apple's Malay.
Malay has no grammatical plural: every plural key has only `other` ("%lld item", "%lld sel", "Tinggal %lld").
Numbers, dates and durations arrive formatted; units written by Cranny: jam / min / saat.
Apple's own names come from `apple-terms.py ms` (read from macOS 27) and macOS 27's own Malay loctables (AppKit
menus, Calendar, Music, Preview, System Settings, the keyboard-shortcut table).

| English | Malay | Note |
|---|---|---|
| Cranny | Cranny | never translated; also the open panel ("Buka Cranny", "Kekalkan Cranny terbuka") |
| notch | takuk | the hardware cut-out: "pada takuk", "takuk sebenar"; "Takuk" as the Settings group header |
| camera housing | kotak kamera | Notch fit footnotes |
| panel (the open Cranny) | panel | |
| Home (built-in page) | Utama | as Apple's "Skrin Utama"; tab ≤ 12 characters |
| Tray | Rak | Cranny's name, capital R: "di Rak", "Simpan di Rak", "Keluarkan daripada Rak", "Kosongkan Rak" |
| item(s) (Tray) | item | |
| Files (mini-shelf widget) | Fail | |
| pipeline | aliran kerja | "Aliran Kerja Baharu…", "Aliran kerja anda", "aliran kerja dipinkan" |
| step (pipeline) | langkah | Apple (Automator) |
| drop zone | zon lepas | "Zon lepas %lld" |
| live activity / Live Activities | aktiviti langsung / Aktiviti Langsung | Apple's term; short "aktiviti" in tight places |
| peek (noun) / peek (verb) | intaian / intai | "Tempoh intaian", "Intai apabila berubah"; never "Pratonton" (= Preview) |
| compact | padat | |
| satellite | satelit | |
| HUD | Penunjuk / penunjuk | Settings ▸ HUD pane and Displays column ("penunjuk kelantangan"); search words keep "HUD", "OSD" |
| widget · widget library | widget · pustaka widget | |
| layout · Layout & Widgets | tataletak · Tataletak & Widget | Apple's "tataletak" |
| page · cell | halaman · sel | "Tinggal %lld sel"; over the limit "Lebihan %lld sel" (never "Lebih %lld sel" = more than N cells) |
| Pin / Unpin | Pinkan / Nyahpin | Apple Notes "Pinkan Nota", Music "Nyahpin" |
| Keep Cranny open | Kekalkan Cranny terbuka | the pin command and button; "Kekal terbuka" in the key reference |
| Toggle pin | Togol pin | Apple: "Togol keterlihatan" |
| Mirror · Notes · To-dos · Timer · Calendar · Media | Cermin · Nota · Tugasan · Pemasa · Kalendar · Media | widgets |
| Quick Apps | App Pantas | Apple writes "app" (singular and plural) |
| Shortcuts (Apple's app) · a shortcut (Shortcuts.app) | Pintasan · pintasan | "app Pintasan" wherever bare "Pintasan" could read as "shortcuts": "Buka app Pintasan", "Muat semula daripada app Pintasan", "Tidak ditemui dalam app Pintasan"; the Settings pane name stays "Pintasan" |
| keyboard shortcut | pintasan papan kekunci / pintasan | Settings ▸ Keyboard section: "Pintasan papan kekunci" |
| tile (Quick Apps) | jubin | Apple: "Jubinkan Separuh Kiri" |
| launcher (search word) | pelancar | |
| Settings · System Settings | Seting · Seting Sistem | "Seting…" in menus |
| General · Appearance · Keyboard · Gestures · Permissions · About | Umum · Penampilan · Papan Kekunci · Gerak Isyarat · Keizinan · Perihal | Settings panes |
| About Cranny · Quit Cranny | Perihal Cranny · Keluar daripada Cranny | Apple's app-menu pattern |
| Demo mode | Mod demo | |
| tutorial · Skip tutorial | tutorial · Langkau tutorial | search words may keep "lawatan" (tour) |
| setup (welcome flow) | persediaan | "Langkau persediaan" (not "seting" = Settings) |
| Join (meeting) | Sertai | Apple's word; also the short Join capsule (34 pt: "Sertai" 34.3 pt at 12 pt, narrower than Russian «Войти») |
| event · meeting · all-day | peristiwa · mesyuarat · seharian | Apple Calendar |
| Meeting soon · Meeting in progress | Mesyuarat akan bermula · Mesyuarat sedang berlangsung | activity names |
| Reset to Default · Reset | Reset kepada Lalai · Reset | Apple ("Reset kepada Lalai", "mereset") |
| Changed from the default | Diubah daripada lalai | |
| default | lalai | |
| Granted / Allowed / Denied / Not yet / Restricted / Unknown | Dibenarkan / Dibenarkan / Ditolak / Belum lagi / Dihadkan / Tidak diketahui | permission pills |
| Allow… · Grant… | Benarkan… | Apple "Benarkan" / "Jangan Benarkan" |
| permission · access | keizinan · akses | Apple |
| Move up / down / left / right | Alih ke atas / bawah / kiri / kanan | Apple ("Alih ke Atas"); Title Case in menus |
| Preview | Pratonton | Apple |
| drag · drop | seret · lepas | "Seret fail ke takuk…", "Lepaskan fail di sini…" |
| click | klik | |
| hover / rest the pointer | tuding / letakkan penuding | Apple: "perkara yang saya tuding"; options "Tuding / Klik / Pintasan sahaja" |
| pointer | penuding | Apple |
| display | paparan | Apple's "Paparan" pane; "Paparan terbina dalam", "Paparan dengan penuding" |
| Show on | Tunjukkan pada | |
| Never (timeout 0) · Off · On | Tidak pernah · Mati · Hidup | segment pickers "Mati" |
| Turn on · Turn off (as a pair) | Hidupkan · Matikan | the pair as Apple's Home app: "Hidupkan mod demo" / "Matikan mod demo", "matikan penunjuk, kemudian hidupkannya semula"; on its own "mengaktifkan" stays fine for features and fallbacks, and a system setting quoted in a sentence is "… diaktifkan" |
| open · closed (a state) / opens · closes (an event) | terbuka · tertutup / dibuka · ditutup | "Semasa Cranny terbuka", "Panel yang terbuka", preview "Cranny, tertutup"; but "sebelum Cranny dibuka", "apabila Cranny ditutup" |
| set (a value) | ditetapkan / tetapkan | never colloquial "diset": "Ditetapkan kepada %@", "Juga ditetapkan dalam Aktiviti Langsung" |
| Status | Status | Apple ("Status"); not "Keadaan" |
| Short · Standard · Long (hover delay) | Singkat · Biasa · Lama | durations take "singkat / lama", not "pendek / panjang" (lengths) |
| draw / show the HUD | memaparkan | not "melukis" (draw with a pen) |
| the helper answered in N ms · didn't answer · sees | bertindak balas dalam N ms · tidak membalas · mengesan | not "menjawab" / colloquial "nampak" |
| Effect: Aurora · Motes · Tide | Aurora · Zarah · Pasang surut | "Aurora" as Apple's Malay (ExtensionKit); search word keeps "cahaya kutub" |
| Open %@ · Run %@ | Buka %@ (an app) · Buka “%@” / Jalankan “%@” (a note, a shortcut) | app names unquoted, as Apple's Malay ("Buka dalam %@"); user-made titles in quotes |
| Pause Live Activities · Paused · Resumed | Jeda Aktiviti Langsung · Dijeda · Aktif | wing words measured: "Dijeda" fits the 48-pt slot; "Aktif" (the state after resuming) fits — "Diteruskan" does not fit even the 72-pt slot; the sentence keeps "diteruskan" |
| Copied (Tray wing) | Disalin | 46 pt at 1u, fits the medium slot |
| Done (Quick Apps wing, buttons) · Done (Timer band, ≤ 6) | Selesai · Tamat | |
| Failed | Gagal | |
| Remove (widget from a page, app from a list, item from the Tray) | Keluarkan | Apple's "Remove"; never "Padam" (= Delete); "Keluarkan daripada …" as Apple's "Keluarkan daripada Dock" ("Keluarkan daripada Rak", "Keluarkan daripada App Pantas") |
| Delete | Padam | Apple |
| Rename | Nama Semula (menus, buttons) · namakan semula (sentences, tooltips) | Apple's AppKit "Nama Semula…" |
| Dismiss (an activity, a reminder, a failed run) · Dismiss (a banner) | Ketepikan · Tutup | "Leret ke atas untuk mengetepikan" never collides with "ke atas untuk menutup" (close the panel) |
| Activate (press the focused control) | Tekan | not "Aktifkan" (= turn on) |
| App not installed | App tidak dipasang | |
| player (media app) | pemain | "pemain media" |
| media helper | pembantu media | |
| Apple Events fallback | sandaran Apple Events | |
| visualizer · Live / Ambient / Static / Off | pentampak · Langsung / Ambien / Statik / Mati | Apple Music's "Pentampak" |
| track · song | trek · lagu | Apple ("Trek Seterusnya") |
| artwork | karya seni | Apple Music |
| shuffle · repeat | rombak · ulang | Apple Music |
| Typing effect · Instant | Kesan menaip · Serta-merta | |
| Symbol | Simbol | |
| Zip · Unzip · Compress · Convert · Resize | Arkibkan · Ekstrak · Mampatkan · Tukar · Saiz semula | Apple: "Arkib", "Mampat", "Saiz Semula" |
| Quick Look · Reveal in Finder · Show in Finder | Lihat Cepat · Dedahkan dalam Finder · Tunjukkan dalam Finder | Apple |
| Share… · Move to Trash · screenshot | Kongsi… · Pindah ke Sampah · gambar skrin | Apple |
| Copy path(s) · path | Salin laluan · laluan | Apple ("Salin Laluan") |
| Undo | Buat asal | Apple |
| Check for Updates | Semak Kemas Kini | Apple |
| Accent | Aksen | Apple ("Warna aksen") |
| Low Power Mode · Battery | Mod Kuasa Rendah · Bateri | Apple |
| headphones · earbuds · case | fon kepala · bud telinga · bekas | Apple |
| Login Items | Item Log Masuk | Apple |
| Launch at login / Open at login | Buka semasa log masuk | |
| Haptic feedback | Maklum balas haptik | Apple |
| swipe | leret | Apple ("Leret dengan Dua Jari") |
| Alerts (priority class) | Isyarat | Apple ("Isyarat") |
| Accessibility settings named in copy | “Kurangkan pergerakan”, “Kurangkan kelutsinaran”, “Tingkatkan kontras”, “Membezakan tanpa warna” | never paraphrased |
| Music (Apple's app) | Muzik | "app Muzik" in running text, where it could read as music; bare in lists ("Apple Events (Muzik, Spotify)") |
