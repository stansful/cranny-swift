# Cranny — Arabic terminology (ar, RTL)

Register and style, following macOS 27 Arabic:

- Buttons, menu items, toggles and commands use the verbal noun (masdar), as Apple does: فتح، إغلاق، إظهار، إنهاء Cranny، التحقق من وجود تحديثات…، إضافة أداة.
- Sentences that tell the user what to do use the masculine imperative, as Apple does: انقر، اسحب، أفلت، ضع المؤشر، حاول مرة أخرى.
- Prefer verb-first sentences (يعرض Cranny…، لا يسجّل Cranny…). This is natural Arabic and keeps paragraphs that start with a Latin name out of LTR.
- Punctuation: Arabic comma ، semicolon ؛ question mark ؟; one-character ellipsis …; names of apps and settings in straight double quotes "…" as macOS 27 writes them (تطبيق "الموسيقى"، "تقليل الحركة").
- Breadcrumb paths: English ▸ becomes ◂, which points the way an RTL reader reads (الإعدادات ◂ الأذونات). This is Apple's own mapping: the Arabic loctables translate "▸" as "◂" and "START ▸ END" as "البداية ◂ النهاية". An English → in an example chain (Resize → Convert) becomes ←.
- Never digits in a translation. Numbers come from placeholders, and English literals are written as words (لمدة ساعة، خلال عشر ثوانٍ، +دقيقة). Exceptions: key names (⌥1–⌥9, Go to page 1–5), versions (macOS 14.2), file-name examples (Brief.zip) and typed input formats (25 أو 90s).
- Plurals have six forms. zero and one/two drop the number where Arabic does (عنصر واحد، عنصران). Then the other placeholders are positional.

## Concepts

| English | Arabic | Note |
|---|---|---|
| Cranny | Cranny | never translated or transliterated; masculine (التطبيق): «يعرض Cranny» |
| notch | النتوء | «في النتوء»، «على النتوء»، «شاشات بلا نتوء». Apple has no Arabic term for it. |
| camera housing | منطقة الكاميرا | Notch fit |
| open panel | اللوحة | «اللوحة المفتوحة»; opening it is «فتح Cranny» |
| Home (built-in page) | الرئيسية | header tab (44 pt) |
| page | صفحة / صفحات | |
| Layout & Widgets (pane) | التخطيط والأدوات | |
| layout | التخطيط / تخطيط | onboarding presets: «تخطيط البداية» |
| widget | أداة / الأدوات | Apple's own Arabic word for widgets |
| widget library | مكتبة الأدوات | |
| cell (grid) | خلية / خليتان / خلايا | |
| Tray | الرف | «على الرف»، «إزالة من الرف»، «مسح الرف»؛ not «الصينية» |
| Keep in Tray (drop zone) | إضافة إلى الرف | not «الاحتفاظ على الرف» (الاحتفاظ takes بـ) |
| Keep at most (item cap) | الحد الأقصى للعناصر | |
| item (Tray) | عنصر / عناصر | |
| pipeline | سلسلة / سلاسل | «سلاسلك»، «سلسلة جديدة…»، «السلاسل المثبّتة» |
| step (pipeline) | خطوة / خطوات | |
| drop zone | منطقة الإفلات | |
| Live Activities (pane, feature) | الأنشطة المباشرة | Apple's term; one activity is «نشاط» (نشاط مباشر) |
| peek | لمحة / لمحات | not «معاينة سريعة», which is Quick Look |
| satellite | الدائرة التابعة | the second activity in a small circle |
| compact / wings | بجانب النتوء | «wings» is never translated literally |
| HUD | مؤشر المستوى | volume, brightness and keyboard backlight overlay; never «المؤشر» alone, which is the pointer |
| pointer | المؤشر | Apple |
| Quick Apps | التطبيقات السريعة | |
| tile | مربّع / مربّعات | Apple Home's word |
| shortcut (Shortcuts app) | اختصار / اختصارات | the app is "الاختصارات" in quotes when it means the app |
| keyboard shortcut | اختصار لوحة المفاتيح / مفاتيح الاختصار | Settings ▸ Keyboard |
| Command palette | لوحة الأوامر | |
| Pin / Keep Cranny open | تثبيت / إبقاء Cranny مفتوحًا | Unpin = إلغاء التثبيت |
| Demo mode | نمط العرض التوضيحي | Apple uses «نمط» for modes |
| Settings | الإعدادات | |
| Permissions | الأذونات | |
| Allow… / Grant… | السماح… | Apple's «السماح» |
| Granted / Denied / Restricted | مسموح / مرفوض / مقيَّد | permission pills |
| Join (meeting) | انضمام | Apple FaceTime. Full form «الانضمام إلى الاجتماع» |
| meeting / event | اجتماع / حدث | Calendar uses «الأحداث» |
| Reset to Default | إعادة التعيين إلى الافتراضي | Apple |
| Changed from the default | تم تغييره عن القيمة الافتراضية | |
| Move up / down | نقل لأعلى / لأسفل | |
| Move left / right (layout editor, pages) | نقل إلى موضع سابق / نقل إلى موضع لاحق | the code shifts by −1 / +1 and the layout mirrors under RTL, so «لليسار/لليمين» would point the wrong way; same wording as Quick Apps' Move earlier / later |
| Typing effect | تأثير الكتابة | |
| Instant (motion, delay) | فوري | |
| Preview (Settings stage) | معاينة | |
| drag / drop | اسحب، السحب / أفلت، الإفلات | Apple |
| click | انقر / النقر | |
| hover, rest the pointer | التحويم / ضع المؤشر على… | «تمرير» means scroll in Apple Arabic, so it is avoided |
| swipe | اسحب بإصبعين / السحب | Apple uses «سحب» for swipes too |
| tutorial | البرنامج التعليمي | Apple; never «جولة» (tour) |
| Show … (switches) | إظهار … | |
| Open %@ | فتح "%@" | the name in straight quotes |
| Remove (from a list) | إزالة | «حذف» only for a real deletion (a note, a to-do, a pipeline) |
| App not installed | التطبيق غير مثبّت | |
| player (media app) | المشغّل | |
| Media | الوسائط | |
| Apple Events | أحداث Apple | Apple's Arabic (Safari «السماح بـ JavaScript من أحداث Apple», Sharing «أحداث Apple عن بُعد»); «البديل عبر أحداث Apple» |
| Sound output / output device | إخراج الصوت / جهاز الإخراج | Apple's Sound pane («الإخراج»); not «مخرج» |
| Now Playing | قيد التشغيل | Apple |
| track / song | المسار / الأغنية | Apple Music |
| artwork | الغلاف | Apple Music |
| visualizer | المؤثر المرئي | modes: إيقاف · ثابت · محيطي · مباشر |
| Mirror | المرآة | |
| Notes · To-dos · Timer · Calendar | الملاحظات · المهام · المؤقت · التقويم | |
| preset (Timer) | إعداد مسبق | |
| Accent (colour) | اللون الثانوي | Apple's Arabic for Accent color (Appearance intents); the Appearance pane's own loctable also has «استخدام لون السمة» (Use Theme Color), a different setting |
| …then settle (typing effect) | ثم تعود إلى لونها العادي | not «تستقر» |
| Low battery | شحن البطارية منخفض | Apple (Find My «Low Battery») |
| Restarting / Starting / Loading… | تجري إعادة التشغيل / يجري البدء / يجري التحميل… | Apple; «تجري» agrees with the feminine «إعادة» |
| Brightness · Volume | الإضاءة · مستوى الصوت | Apple |
| Keyboard backlight | الإضاءة الخلفية للوحة المفاتيح | the HUD shows «إضاءة لوحة المفاتيح» |
| Haptic feedback | الاستجابة اللمسية | Apple |
| Low Power Mode | نمط الطاقة المنخفضة | Apple |
| Never (a timeout of 0) | مطلقًا | Apple |
| Off / On (values) | إيقاف / تشغيل; VoiceOver states متوقف / مشغّل | |
| Done (flash) · Copied (flash) · Failed (flash) | تم · تم النسخ · فشل | measured: 14, 48 and 27 pt |
| Paused · Resumed (pause confirmation) | متوقفة · نشطة | 38 / 32 pt; the sentence says «تم إيقاف الأنشطة المباشرة مؤقتًا» / «تم استئناف…» |
| Hi (greeting) | مرحبًا | 30 pt |
| in %@ (band) | بعد %@ | «بعد ٣٠د» is 41 pt in compactLabel |

## Apple names used (apple-terms.py)

إعدادات النظام · فايندر · "الموسيقى" · التقويم · "الاختصارات" · سفاري · الخصوصية والأمن · تسهيلات الاستخدام · التحكم التلقائي ·
التقويمات · الكاميرا · Bluetooth · تسجيل صوت النظام · عناصر تسجيل الدخول · البطارية · شريط القوائم · شريط الأيقونات ·
الإرسال السريع (AirDrop) · الباحث (Spotlight) · إدارة المهام (Mission Control) · معاينة سريعة (Quick Look) · التنزيلات ·
تقليل الحركة · تقليل الشفافية · التمييز بدون لون · التعليق الصوتي · عام · المظهر · لوحة المفاتيح · لوحة التعقب ·
alert sounds: بوب، نسيم، فقاعة، بلور، فانكي، بطلة، قفز، وسطي، حصى، نقر، بونغ، السونار، سونومي، غمر.
