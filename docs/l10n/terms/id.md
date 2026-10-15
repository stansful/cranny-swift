# Cranny — Indonesian (id) terminology sheet

Register: formal **Anda** (capital A), as macOS. Buttons and menu items use the bare imperative
("Buka", "Tampilkan", "Jeda"), as Apple's Indonesian does. Where English uses Title Case (menu items, buttons) the
Indonesian is Title Case too ("Periksa Pembaruan…", "Tutup Cranny", "Pindahkan ke Bawah"); function words stay
lower case (ke, di, dari, dan, untuk, yang, dengan). Settings rows, toggles and footnotes are sentence case.
Typography: quotes “…” (‘…’ inside), one-character ellipsis …, “ ▸ ” in Settings paths, no straight quotes.
Indonesian has no grammatical plural: every plural key has only `other` ("%lld item", "%lld hari", "Sisa %lld sel").
Apple's own names come from `apple-terms.py id` (read from macOS 27) and from macOS 27's own loctables
(AppKit menus, Finder, Calendar, keyboard-shortcut table).

| English | Indonesian | Note |
|---|---|---|
| Cranny | Cranny | never translated; also the open panel ("Buka Cranny", "Biarkan Cranny terbuka") |
| Quit Cranny · Close Cranny (Esc, the panel) · When Cranny quits | Tutup Cranny · Tutup panel Cranny · Hingga app Cranny ditutup | macOS says "Tutup [App]" for Quit (TextEdit: "Tutup TextEdit"), so wherever closing the *panel* could be read as quitting, say "panel"; where the *app* quits, say "app Cranny" |
| notch | notch | loanword, lower case in running text ("di notch"); "Notch" as the Settings group header |
| panel (the open Cranny) | panel | |
| Home (built-in page) | Beranda | |
| Tray | Rak | Cranny's name, capital R: "di Rak", "Simpan di Rak", "Keluarkan dari Rak", "Kosongkan Rak" |
| item(s) (Tray) | item | |
| Remove from Tray | Keluarkan dari Rak | "take off the shelf": never reads as deleting the file |
| pipeline | alur | "Alur Baru…", "Alur Anda", "alur yang dipin" |
| live activity / Live Activities | aktivitas langsung / Aktivitas Langsung | Apple's term; short "aktivitas" ("Jeda aktivitas") |
| peek | intipan (verb: intip) | "Durasi intipan", "Tampilkan intipan saat lagu berganti" |
| compact (activity beside the camera) | ringkas | |
| satellite | satelit | |
| HUD | Indikator / indikator | Settings ▸ HUD pane, column; "indikator volume"; search words keep "HUD", "OSD" |
| widget · widget library | widget · pustaka widget | |
| layout · Layout & Widgets | tata letak · Tata Letak & Widget | |
| page · cell | halaman · sel | "Sisa %lld sel", "kelebihan %lld sel" |
| Pin / Unpin / pinned | Pin / Lepas pin / dipin | Apple Notes: "Pin Catatan", "Lepas Pin Catatan" |
| Keep Cranny open | Biarkan Cranny terbuka | the pin command and button |
| Mirror · Notes · To-dos · Timer · Calendar · Media | Cermin · Catatan · Tugas · Timer · Kalender · Media | widgets |
| Quick Apps | App Cepat | Apple writes "app" |
| Shortcuts (Apple's app) · a shortcut | Pintasan · pintasan | "app Pintasan" in sentences where it could mean keyboard shortcuts |
| keyboard shortcut | pintasan / pintasan papan ketik | |
| tile (Quick Apps) | kotak | Apple: "Kotak Layar Penuh" |
| Files (mini shelf) | File | |
| Settings · System Settings | Pengaturan · Pengaturan Sistem | "Pengaturan…" in menus |
| General · Appearance · Keyboard · Gestures · Permissions · About | Umum · Tampilan · Papan Ketik · Gerakan · Izin · Mengenai | Settings panes; Apple: "Mengenai Mac Ini" |
| About Cranny · Quit Cranny | Mengenai Cranny · Tutup Cranny | Apple's app-menu pattern ("Mengenai TextEdit", "Tutup TextEdit", verified in TextEdit's Edit.loctable) |
| Demo mode | Mode demo | |
| tutorial · Skip tutorial | tutorial · Lewati tutorial | search words may keep "tur" |
| setup (welcome flow) | penyiapan | "Lewati penyiapan" (not "pengaturan" = Settings) |
| Join (meeting) | Bergabung | Apple Calendar's word |
| Join (event-row capsule) | Ikut | the only short form; Apple Calendar's own Join button (CalendarUIKit "Join" → "Ikut"), 25 pt vs 50 for "Gabung" |
| event · meeting · all-day | acara · rapat · seharian | Apple Calendar |
| Meeting soon · Meeting in progress | Rapat segera dimulai · Rapat berlangsung | activity names |
| Reset to Default · Reset | Atur Ulang ke Default · Atur Ulang | Apple: "Atur Ulang ke Default" |
| Changed from the default | Diubah dari default | |
| Granted / Allowed / Denied / Not yet / Restricted / Unknown | Diizinkan / Diizinkan / Ditolak / Belum / Dibatasi / Tidak diketahui | permission pills |
| Allow… · Grant… | Izinkan… | |
| permission · access | izin · akses | |
| Move up / down / left / right | Pindahkan ke atas / bawah / kiri / kanan | Title Case in menus |
| Preview | Pratinjau | |
| drag · drop | seret · lepas | "Seret file ke notch…", "Lepaskan file di salah satunya" |
| click | klik | |
| hover / rest the pointer | arahkan penunjuk | "Arahkan penunjuk / Klik / Hanya pintasan" |
| pointer | penunjuk | Apple |
| display | layar | Apple's "Layar" pane |
| Show on · Display with the pointer · Built-in display | Tampilkan di · Layar dengan penunjuk · Layar internal | |
| Never (timeout 0) · Off · On | Tidak pernah · Mati · menyala | |
| Open %@ (an app) | Buka “%@” | app and note names in quotes |
| Pause Live Activities · Paused · Resumed | Jeda Aktivitas Langsung · Dijeda · Aktif | wing words; "Dilanjutkan" in the sentence |
| Copied (Tray wing) | Disalin | 43 pt at 1u (Russian «Готово» is 44) |
| Done (Quick Apps wing, buttons) | Selesai | Timer band (≤ 6 characters): Usai |
| Failed | Gagal | |
| Remove (widget from a page) | Hapus dari halaman | |
| Remove (app from a list) | Hapus … dari daftar | never a bare "Hapus app" |
| App not installed | App tidak terinstal | |
| player (media app) | pemutar | |
| media helper | alat bantu media | |
| Apple Events fallback | cadangan Apple Events | |
| visualizer · Live / Ambient / Static / Off | visualisasi · Langsung / Ambien / Statis / Mati | |
| track (song) | lagu | "Lagu berikutnya" |
| Typing effect · Instant | Efek mengetik · Instan | |
| Symbol | Simbol | |
| Zip · Unzip · Compress (images) · Convert · Resize | Arsipkan · Ekstrak · Kompres · Konversi · Ubah ukuran | "Arsipkan" avoids Finder's "Kompresi" next to "Kompres" |
| Quick Look · Reveal in Finder · Show in Finder | Lihat Cepat · Perlihatkan di Finder · Tampilkan di Finder | Apple |
| Move to Trash · screenshot | Pindahkan ke Tong Sampah · tangkapan layar | Apple |
| Copy path(s) | Salin jalur | |
| Excluded apps | App yang dikecualikan | |
| Volume · Brightness · Keyboard backlight | Volume · Kecerahan · Lampu belakang papan ketik | Apple |
| battery level · charging case · mouse | level baterai · casing · tetikus | Apple (BatteryUI "Level Baterai", HeadphoneSettings "casing pengisi daya", Bluetooth/System Settings "Tetikus"); Speaker, Headphone, Trackpad stay as Apple keeps them |
| colours | Biru, Cokelat, Abu-abu, Hijau, Nila, Mint, Oranye, Pink, Ungu, Merah, Hijau Kebiruan, Kuning, Grafit | Apple's AccentColorNames / MenuCommands: "Pink" and "Mint", not "Merah Muda" / "Hijau Mint" |
| Work · Personal (sample calendars) | Kantor · Pribadi | Apple's default iCloud ‘work’ calendar is "Kantor" |
| Edit (menu items, buttons) | Edit | everywhere, also "Edit…" in Settings ▸ Tray; never "Ubah…" (that is Change / Rename: "Ubah Nama") |
| Buttons: Capsule / Rounded | Kapsul / Sudut bulat | |
| Sound output · output device · Mute · Muted | Output bunyi · perangkat output · Bisukan · Dibisukan | Apple ("Bunyi") |
| Low Power Mode · Low battery · Charging | Mode Daya Rendah · Baterai lemah · Mengisi daya | Apple |
| Ambient light · Subtle · Vivid | Cahaya ambien · Lembut · Cerah | the light layer; "pendar" for glow |
| Quality (the light: Detailed · Efficient) | Kualitas (Detail · Hemat) | Settings ▸ Appearance ▸ Light; search keywords memori · kinerja |
| Motion (Appearance picker) · Calm / Standard / Lively / Instant | Animasi · Tenang / Standar / Lincah / Instan | not "Gerakan": that is the Gestures pane (Apple's trackpad word); Apple's "Kurangi gerakan" stays quoted in the footnote; search keyword "animasi gerakan" |
| Gestures (Settings pane) · swipe | Gerakan · gesek | Apple's trackpad "Gerakan Lainnya" |
| Notch fit | Penyesuaian notch | not "kesesuaian" (conformity) |
| Density · Compact / Standard / Roomy | Kepadatan · Padat / Standar / Lega | not "Rapat" (= meeting) |
| Floating island · Attached · Handle | Pulau mengambang · Menempel · Pegangan | displays without a notch |
| System settings named in copy | “Kurangi gerakan”, “Kurangi transparansi”, “Tambah kontras”, “Bedakan tanpa warna” | Apple's names, quoted |
| Music (Apple's app) | “Musik” | quoted when it names the app |
| Timer alert sounds | Apple's names: Boop, Angin, Gelembung, Kristal, Funky, Pahlawan Wanita, Lompat, Mezzo, Kerikil, Petikan, Pong, Sonar, Sonumi, Menyelam | |
| ms (milliseconds) | md | |

Reviewed 2026-10-14 (independent review).
