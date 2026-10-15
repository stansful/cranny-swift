# Cranny — Thai (ไทย, th) terminology sheet

Register and typography (as macOS writes Thai):
- Polite neutral register, คุณ for "you" (used sparingly, as Apple does); no polite particles (ครับ/ค่ะ).
- No full stop at the end of a sentence; sentences and clauses are separated by a space. Questions end in
  "…หรือไม่" without "?" (Apple: "ลบ “%@” หรือไม่").
- No spaces between Thai words; a space before and after Latin words, numbers and placeholders
  ("เปิด Cranny", "%lld รายการ"), as macOS does.
- Quotes “…” (secondary ‘…’), ellipsis … (U+2026), no straight quotes.
- Buttons and menu items are bare verbs ("เปิด", "ยกเลิก", "ตรวจหารายการอัปเดต…"); Thai has no letter case, so the
  English title case/sentence case split disappears.
- Number + classifier: "%lld รายการ", "%lld ช่อง", "%lld วัน". Thai has one plural form (other).
- Apple's names come from `apple-terms.py th` (System Settings panes, privacy services, apps, sounds).
- "Cranny" is never translated or transliterated.

| English (Cranny concept) | Thai | Notes |
|---|---|---|
| Cranny (also the open panel in copy) | Cranny | "Open Cranny" → "เปิด Cranny" |
| notch | รอยบาก | "บนรอยบาก", "ที่รอยบาก"; the common Thai word for the camera notch |
| camera housing | ตัวเรือนกล้อง | Notch fit |
| panel (the open Cranny surface) | แผง | "Panel padding" → "ระยะขอบแผง" |
| Home (built-in widget page, tab) | หน้าหลัก | never "บ้าน" (Apple's Home app) |
| page (user pages) | หน้า | "Page %lld" → "หน้า %lld" |
| Layout & Widgets (Settings pane) | เค้าโครงและวิดเจ็ต | |
| layout | เค้าโครง | "Edit layout" → "แก้ไขเค้าโครง" |
| widget / widget library | วิดเจ็ต / คลังวิดเจ็ต | |
| cell (grid unit) | ช่อง | "%lld cells left" → "เหลือ %lld ช่อง" |
| Tray | ถาด | "เก็บไว้ในถาด" (Keep in Tray), "เอาออกจากถาด", "ล้างถาด" |
| item (Tray) | รายการ | "%lld รายการ" |
| pipeline | ไปป์ไลน์ | a chain of steps on Tray files |
| step (pipeline) | ขั้นตอน | |
| drop zone | โซนวาง | |
| drag / drop (files) | ลาก / วาง | "ลากไฟล์มาวางบนรอยบาก" |
| Live Activities (feature, pane) | กิจกรรมสด | Apple's own Thai name for Live Activities |
| live activity / activity | กิจกรรมสด | always with สด, to keep it apart from calendar events (กิจกรรม) |
| peek | มุมมองย่อ | not "ดูแบบรวดเร็ว" (= Quick Look) |
| satellite (second activity) | ดาวบริวาร | small circle beside the notch |
| HUD (volume/brightness overlay) | ตัวแสดงระดับ | Settings ▸ HUD pane, column header; search keywords keep "HUD" |
| compact wing word: Paused / Resumed | หยุดพัก / ทำงานต่อ | measured: 42 pt medium slot / 52 pt wide slot |
| Pause / Resume Live Activities | หยุดพักกิจกรรมสด / ให้กิจกรรมสดทำงานต่อ | Apple: Pause = หยุดพัก |
| Pin / Keep open | ปักหมุด | "Keep Cranny open" → "ปักหมุด Cranny"; Unpin → ปลดหมุด (Apple Notes) |
| Demo mode | โหมดสาธิต | Apple's term |
| Settings | การตั้งค่า | Apple's term |
| System Settings | การตั้งค่าระบบ | glossary |
| permission | สิทธิ์ | "Permissions" pane → "สิทธิ์" |
| Allow… / Grant… | อนุญาต… | |
| Allowed / Granted | อนุญาตแล้ว | |
| Denied | ถูกปฏิเสธ | |
| Restricted | ถูกจำกัด | |
| Reset to Default | รีเซ็ตเป็นค่าเริ่มต้น | Apple's term |
| Changed from the default | เปลี่ยนจากค่าเริ่มต้นแล้ว | |
| Remove (from a list) / Delete | เอาออก / ลบ | Apple: Remove = เอาออก; "ลบแอป" would read as uninstalling |
| App not installed | ไม่ได้ติดตั้งแอป | |
| app | แอป | Apple's term |
| player (media app) | แอปเล่นสื่อ | |
| Media (module) | สื่อ | Apple's term |
| Now Playing | กำลังเล่นอยู่ | Apple's term |
| visualizer | ตัวแสดงภาพเสียง | Off · Static · Ambient · Live → ปิด · นิ่ง · บรรยากาศ · สด |
| media helper | ตัวช่วยสื่อ | the perl/ruby MediaRemote helper |
| Apple Events fallback | ทางสำรองผ่าน Apple Events | |
| Join (meeting) | เข้าร่วม | also the short capsule word (40 pt, as wide as Russian «Войти») |
| meeting | การประชุม | "Meeting soon" → "ใกล้ถึงเวลาประชุม", "Meeting in progress" → "กำลังประชุม" |
| event (calendar) | กิจกรรม | Apple Calendar's term |
| Notes · To-dos · Timer · Calendar | โน้ต · สิ่งที่ต้องทำ · นับถอยหลัง · ปฏิทิน | Apple: Notes = โน้ต, Timer = นับถอยหลัง |
| Quick Apps | แอปด่วน | patterned on Apple's โน้ตด่วน (Quick Note). Never write โน้ตด่วน for Cranny's notes: it is Apple's Quick Note feature (Notes description = “จดโน้ตได้รวดเร็ว…”) |
| Shortcuts (Apple's app) / a shortcut in it | คำสั่งลัด | glossary |
| keyboard shortcut | ปุ่มลัด | Apple: Keyboard Shortcuts = ปุ่มลัดแป้นพิมพ์ |
| tile (Quick Apps) | ไทล์ | |
| Mirror (widget) | กระจก | |
| Files (widget) | ไฟล์ | |
| Quick Look | ดูแบบรวดเร็ว | glossary |
| Zip / Unzip | สร้างไฟล์ zip / แตกไฟล์ zip | Compress (images) = บีบอัด; file-name suffix “compressed” = บีบอัดแล้ว (Apple) |
| Copied (Tray flash) | คัดลอกแล้ว | 62 pt, wide slot (72) |
| Done (Quick Apps flash) | เสร็จสิ้น | 42 pt, medium slot |
| Failed (flash) | ไม่สำเร็จ | 47 pt, wide slot |
| Hi (greeting flash) | สวัสดี | 31 pt |
| Done (timer, ≤ 6 characters) | เสร็จ | |
| tutorial | การฝึกใช้ | Apple: Open Tutorial = เปิดการฝึกใช้ |
| click / press (key) | คลิก / กด | |
| hover / rest the pointer | วางตัวชี้ | Apple: pointer = ตัวชี้ |
| swipe | ปัด | two fingers: "ปัดด้วยสองนิ้ว" |
| display | จอภาพ | Apple's term; "Display with the pointer" → "จอภาพที่มีตัวชี้" |
| Show on | แสดงบน | |
| menu bar | แถบเมนู | glossary |
| full screen | เต็มหน้าจอ | |
| Never (timeout 0) | ไม่เลย | Apple's term |
| Instant | ทันที | |
| Preview (noun) | ตัวอย่าง | "Notch preview" → "ตัวอย่างรอยบาก" |
| Typing effect | เอฟเฟ็กต์การพิมพ์ | Apple spells เอฟเฟ็กต์ |
| accent color | สีเน้น | Cranny's own picker and footnotes; when the text points at macOS's setting, write Apple's name in quotes: “สีที่ใช้เน้น” |
| HUD colours Mono · Accent · Semantic | ขาว · สีเน้น · ตามความหมาย | |
| Haptic feedback | การตอบกลับการสัมผัส | Apple's trackpad term |
| Launch at login / Open at login | เปิดเมื่อเข้าสู่ระบบ | Apple's term |
| Login Items | รายการเข้าสู่ระบบ | glossary |
| update / check for updates | อัปเดต / ตรวจหารายการอัปเดต | Apple's term; Update Available = มีรายการอัปเดต; Version %@ is available = เวอร์ชัน %@ พร้อมให้ใช้งานแล้ว (not “มีเวอร์ชัน %@ แล้ว”, which reads “you already have”) |
| version | เวอร์ชัน | |
| Excluded apps | แอปที่ยกเว้น | |
| ambient light | แสงรอบข้าง | Appearance ▸ Light |
| density | ความหนาแน่น | Compact · Standard · Roomy → กะทัดรัด · มาตรฐาน · กว้างขวาง |
| actions (page actions, More actions) / Behavior | การทำงาน / ลักษณะการทำงาน | Apple: Quick Actions = การทำงานด่วน |
| path (Copy path) | เส้นทาง | Apple: Copy as Pathname = คัดลอกเป็นชื่อเส้นทาง |
| metadata | เมตาดาต้า | Apple Photos' spelling |
| Remove background | เอาพื้นหลังออก | Apple Preview |
| archive (zip) | ที่เก็บถาวร | Apple's noun (Archive Utility; Finder names Archive.zip “ที่เก็บถาวร”, LocalizableMerged AR40); also the dated zip base name. “Name zip archives” row = ตั้งชื่อไฟล์ zip |
| Gestures (pane) | คำสั่งนิ้ว | Apple: More Gestures = คำสั่งนิ้วเพิ่มเติม |
| alert (priority class) | การเตือน | |
| in %@ (band, Meeting soon) | %@ | no preposition: "อีก 30นาที" is 55 pt in a 48-pt slot; "30นาที" is 38 pt |
| Collapsed (VoiceOver value) | ยุบอยู่ | Apple VoiceOver; ย่อ is Minimize |
| Repeat one / Repeat all | เล่นซ้ำรายการเดียว / เล่นซ้ำทั้งหมด | Apple; the item may be a podcast or video |
| Move earlier / Move later (reorder actions) | เลื่อนลำดับขึ้น / เลื่อนลำดับลง | Move up/down/left/right stay ย้ายขึ้น/ย้ายลง/ย้ายไปทางซ้าย/ย้ายไปทางขวา |
| Dismiss | ปิดทิ้ง | Apple (67 uses); the Reset All banner's close button is plain ปิด |
| Pause (media, Timer, Live Activities) / Paused | หยุดพัก / หยุดพักอยู่ | Apple (Control Center Now Playing, Clock); Resume = ทำต่อ, media Resume = เล่นต่อ |
| Quality (the light: Detailed · Efficient) | คุณภาพ (ละเอียด · เรียบง่าย) | Settings ▸ Appearance ▸ Light; never “ประหยัด” (Low Power Mode is โหมดประหยัดพลังงาน; it saves memory, battery is not promised); search keywords หน่วยความจำ · ประสิทธิภาพ |
