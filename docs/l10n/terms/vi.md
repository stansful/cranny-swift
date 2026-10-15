# Cranny — Vietnamese (Tiếng Việt, vi) terminology sheet

Register and typography (as macOS writes Vietnamese):
- Neutral, polite register; "bạn" for "you", used sparingly as Apple does. No "quý khách", no particles (nhé, ạ).
- Sentence case everywhere. Apple's names and Cranny's own named features keep their initial capital
  mid-sentence, as Apple does with "Chuyển vào Thùng rác", "trong Trung tâm điều khiển": "Giữ trong Khay",
  "trang Trang chủ", "tiện ích Gương".
- Buttons and menu items are bare imperative verbs ("Mở", "Hủy", "Thêm trang", "Kiểm tra bản cập nhật…");
  status words are adjectives/participles with "Đã" where Apple does ("Đã cho phép", "Đã kết nối").
- Apple's diacritic placement: hóa, khóa, hủy, thủy (not hoá, khoá, huỷ).
- Quotes “…” (secondary ‘…’), ellipsis … (U+2026), no straight quotes. Apple setting names and Cranny row names
  inside a sentence go in “…”; pane paths keep the arrow: "Cài đặt ▸ Bàn phím".
- Vietnamese has no grammatical plural: the single plural form "other" holds every count ("%lld mục", "%lld ô").
- Numbers, durations, dates arrive formatted (vi narrow duration: "4ph", "1g 5ph").
- "Cranny" is never translated or transliterated; it takes no inflection in Vietnamese.

| English (Cranny concept) | Vietnamese | Notes |
|---|---|---|
| Cranny (also the open panel in copy) | Cranny | "Open Cranny" → "Mở Cranny" |
| notch | tai thỏ | the established Vietnamese word for the camera notch; "trên tai thỏ", "vào tai thỏ" |
| camera housing | phần camera | Notch fit footers |
| panel (the open Cranny surface) | bảng | "Panel padding" → "Lề bảng" |
| wings (compact area beside the camera) | (not named) | copy says "hai bên tai thỏ" / "cạnh tai thỏ" |
| compact (state) | thu gọn | "Collapsed" → "đã thu gọn" |
| Home (built-in widget page, tab) | Trang chủ | 63 pt as a tab (Russian «Главная» 53 pt; Tray tab is short) |
| page (user pages) | trang | "Page %lld" → "Trang %lld" |
| Layout & Widgets (Settings pane) | Bố cục & Tiện ích | Apple pane pattern ("Màn hình nền & Dock") |
| layout | bố cục | "Edit layout" → "Sửa bố cục" |
| widget / widget library | tiện ích / thư viện tiện ích | Apple's word for widgets ("Sửa tiện ích") |
| cell (grid unit) | ô | "%lld cells left" → "Còn trống %lld ô" |
| Tray | Khay | "Giữ trong Khay", "Xóa khỏi Khay", "Dọn Khay" |
| item (Tray) | mục | Apple's "%d mục" |
| pipeline | quy trình | a chain of steps on Tray files; "Quy trình của bạn", "Quy trình đã ghim" |
| step (pipeline) | bước | |
| drop zone | vùng thả | |
| drag / drop (files) | kéo / thả | "Kéo tệp vào tai thỏ" |
| Live Activities (feature, pane) | Hoạt động trực tiếp | Apple's own Vietnamese name |
| live activity / activity | hoạt động | generic, lower case |
| peek | xem lướt | not "Xem nhanh" (= Quick Look) |
| satellite (second activity) | vệ tinh | small circle beside the notch |
| HUD (volume/brightness overlay) | chỉ báo | pane "Chỉ báo"; search terms keep "HUD", "OSD"; "Replace the system HUD" → "Thay thế chỉ báo của hệ thống" (not the colloquial "thay"); "Alerts and HUD only" → "Chỉ hiện cảnh báo và chỉ báo" ("Chỉ cảnh báo và chỉ báo" stutters) |
| Paused / Resumed (pause confirmation wing word) | Tạm dừng / Đã bật | "Tạm dừng" (62 pt) fits the wide slot; Resumed names the state like Russian «Активны»: "Đã bật" (41 pt, fits the medium slot). "Tiếp tục" is the Resume command and looked like a button beside the play glyph |
| Pause / Resume Live Activities | Tạm dừng / Tiếp tục Hoạt động trực tiếp | also the Settings ▸ Keyboard shortcut name "Pause activities" (a bare "Tạm dừng hoạt động" reads as "suspend operation") |
| Pin / Keep open / Unpin | Ghim / Ghim / Bỏ ghim | Apple's Pin = Ghim; "Keep Cranny open" → "Ghim Cranny" |
| Demo mode | Chế độ trình diễn | Apple's term |
| Settings | Cài đặt | Apple's term |
| System Settings | Cài đặt hệ thống | glossary |
| permission | quyền | pane "Quyền" |
| Allow… / Grant… | Cho phép… | Apple's Allow = Cho phép |
| Allowed / Granted | Đã cho phép | |
| Denied | Bị từ chối | |
| Not yet (permission pill) | Chưa cấp | the permission was never asked; pairs with "Đã cho phép" |
| Restricted | Bị hạn chế | |
| Reset to Default | Đặt lại về mặc định | Apple's term |
| Changed from the default | Đã thay đổi so với mặc định | |
| Remove (from a list/page) / Delete | Xóa (khỏi …) / Xóa | Apple uses Xóa for both; "khỏi" says it leaves a list, not the disk |
| App not installed | Ứng dụng chưa được cài đặt | |
| app | ứng dụng | |
| player (media app) | trình phát | |
| Media (module) | Phương tiện | Apple's term ("Phương tiện & Apple Music") |
| Now Playing | Đang phát | glossary |
| visualizer | hiệu ứng sóng nhạc | Off · Static · Ambient · Live → Tắt · Tĩnh · Dịu nhẹ · Trực tiếp |
| media helper | trình trợ giúp phương tiện | the perl/ruby MediaRemote helper |
| Apple Events fallback | phương án dự phòng Apple Events | |
| Join (meeting) | Tham gia | Apple's Join; the short capsule word is "Vào" (24 pt) |
| meeting / event | cuộc họp / sự kiện | Apple Calendar's "sự kiện" |
| Notes · To-dos · Timer · Calendar | Ghi chú · Việc cần làm · Hẹn giờ · Lịch | Apple: Notes = Ghi chú, Timer = Hẹn giờ, Calendar = Lịch |
| Quick Apps | Ứng dụng nhanh | patterned on Apple's "Ghi chú nhanh" (Quick Note) |
| Shortcuts (Apple's app) / a shortcut in it | Phím tắt / phím tắt | glossary; "ứng dụng Phím tắt" where ambiguous ("Ứng dụng Phím tắt không khả dụng…"). Likewise "ứng dụng Nhạc" in running text and the usage description ("cho Nhạc" reads as "for music") |
| keyboard shortcut | tổ hợp phím | kept apart from the Shortcuts app, whose Vietnamese name is also "Phím tắt" |
| tile (Quick Apps) | mục | "Sửa các mục", "Hiển thị tên dưới các mục"; "Done editing" → "Đã sửa xong" (Apple, Voice Memos) |
| N more (overflow) | %lld khác / +%lld khác | Quick Apps overflow tile and the Calendar list ("+3 khác"); not the colloquial "3 nữa" |
| More (the widget card's ⋯ button) | Tác vụ khác | as the Tray's "More actions"; a bare "Thêm" sounds like Add ("Thêm tiện ích") |
| Mirror (widget) | Gương | |
| Files (widget) | Tệp | |
| Quick Look | Xem nhanh | glossary |
| Zip / Unzip | Nén zip / Giải nén | Compress (images) = Nén ảnh; Compress video = Nén video |
| Copied (Tray flash) | Xong | the copy glyph says "copied" (as Russian «Готово»); "Đã sao chép" is 77 pt |
| Done (Quick Apps flash, timer ≤ 6 characters) | Xong | Apple's Done = Xong |
| Failed (flash) | Lỗi | fits the medium slot |
| Hi (greeting flash) | Xin chào | fits the wide slot (54 pt at 13 pt) |
| tutorial | hướng dẫn | Apple: Open Tutorial = Mở hướng dẫn; never "tour" |
| click / press (key) | bấm / nhấn | Apple: Click = Bấm |
| hover / rest the pointer | di con trỏ / đặt con trỏ | Apple: hover = di con trỏ, pointer = con trỏ |
| swipe | vuốt | "vuốt bằng hai ngón tay" |
| display | màn hình | Apple's term; "Display with the pointer" → "Màn hình có con trỏ"; built-in → "Màn hình tích hợp" |
| Show on | Hiển thị trên | |
| menu bar | thanh menu | glossary |
| full screen | toàn màn hình | Apple's term |
| Never (timeout 0) | Không bao giờ | |
| Instant | Tức thì | |
| Preview (noun) | bản xem trước | "Xem trước" is also Apple's Preview app |
| Typing effect | Hiệu ứng gõ chữ | |
| accent color | màu nhấn | Apple's term |
| HUD colours Mono · Accent · Semantic | Trắng · Màu nhấn · Theo ý nghĩa | |
| Haptic feedback | Phản hồi cảm ứng | Apple's trackpad term |
| Launch at login / Open at login | Mở khi đăng nhập | Apple's term |
| Login Items | Mục đăng nhập | glossary |
| update / check for updates | bản cập nhật / kiểm tra bản cập nhật | |
| Excluded apps | Ứng dụng bị loại trừ | passive, as Apple's Excluded = "Bị loại trừ"; "một ứng dụng bị loại trừ" in the footnote |
| ambient light | ánh sáng nền | Off · Subtle · Vivid → Tắt · Nhẹ · Rực rỡ |
| density | mật độ | Compact · Standard · Roomy → Gọn · Tiêu chuẩn · Rộng rãi |
| motion | chuyển động | Calm · Standard · Lively · Instant → Êm · Tiêu chuẩn · Sống động · Tức thì |
| floating island / attached | đảo nổi / gắn liền | no-notch styles |
| handle (no-notch displays) | tay nắm | |
| Low Power Mode | Chế độ nguồn điện thấp | glossary; the peek button is the short "Nguồn điện thấp…" |
| Low battery | Pin yếu | Apple's term |
| Command palette | Bảng lệnh | |
| Dismiss (hide until the next change) | Ẩn | the Reset All banner's close button is "Đóng" |
| Remove (a widget from a page) | Xóa khỏi trang | |
| Fold away after | Thu lại khi không hoạt động | the value (seconds / "Không bao giờ") follows the label |
| tutorial step counter "2 of 5" / "Step 2 of 5" | 2 trên 5 / Bước 2 trên 5 | |
| Quality (the light: Detailed · Efficient) | Chất lượng (Chi tiết · Tiết kiệm) | Settings ▸ Appearance ▸ Light; search keywords bộ nhớ · hiệu năng |

Verified with vi imported: FlashLabelFitTests, BandCopyTests,
FeaturedRowTests, the header tab test and the longest tutorial bubble pass for vi; `lint-copy.py` and
`validate.py vi --catalogs` pass. The 6 remaining validator warnings are words macOS keeps in Vietnamese
(Camera, the alert sounds Boop / Pong / Sonumi, "video").

Independent review (2026-10-14): 45 strings changed.
Kept after review: notch = "tai thỏ" (the word Vietnamese users and tech press use for the camera cut-out; "phần
khuyết" / "vùng camera" read as descriptions, not a name); keyboard shortcut = "tổ hợp phím" next to Apple's
"Phím tắt" app (Cranny has both a Keyboard pane and a Shortcuts pane, so the split is needed); Quick Apps tile =
"mục"; Copied = "Xong" (ruling E4, the copy glyph carries "copied"); Join capsule = "Vào"; "Ngày mai %@"; sample
names (Lan, Nam, "Giao ban nhóm", "Thống nhất lộ trình"). Accent and tile colour names (Lam, Lục, Tía, Than chì,
Bạc hà, Nâu, Xám) are Apple's (AppKit AccentColorNames / HighlightColorNames / MenuCommands loctables).

