# Cranny — Hindi (हिन्दी, `hi`) terminology sheet

Register and style, following macOS 27 in Hindi (checked against the system's own loctables on this Mac):

- Formal **आप**; buttons and menu commands in the polite imperative (**खोलें, दिखाएँ, हटाएँ, रद्द करें, जारी रखें**), the way
  macOS writes them. Toggles are imperative phrases too (macOS: “मेन्यू बार में दिखाएँ”).
- Apple's Hindi keeps many established English words in Devanagari (ऐक्सेस, सेटिंग, डिलीट करें, मूव करें, स्किप करें,
  ऑटोमैटिक, ब्राइटनेस, वॉल्यूम, फ़ुल स्क्रीन). Cranny follows that hybrid register instead of Sanskritised coinages.
- Full stop is the danda **।**; ? and ! as in English; ellipsis **…** (U+2026); quotes **“…”** (and ‘…’ inside).
  Nukta spellings as macOS: फ़ाइल, फ़ोल्डर, फ़ोकस, डिफ़ॉल्ट, ज़िप.
- Apple names a pane without quotes in running text (“सिस्टम सेटिंग में लॉगइन आइटम खोलें”) and an app as “<name> ऐप”
  (संगीत ऐप, शॉर्टकट ऐप) — also inside parentheses and lists (“Apple Events (संगीत ऐप, Spotify)”), because bare संगीत
  reads as the common noun “music”. A pane whose name is an ordinary word gets quotes and पेन, as Apple does
  (“… “सामान्य” पेन में …”, cf. Apple “… “डाउनटाइम” पेन …”). Settings paths keep Cranny's ▸.
- “never X or Y”: the correlative **न तो … न ही …** (“Cranny उन्हें न तो कभी बदलता है, न ही अपलोड करता है।”), never
  “कभी न X है, न Y है”.
- Postpositions after names stay separate words: “Cranny को”, “Cranny में”, “Cranny का”. Cranny is grammatically
  **masculine** (“Cranny खुलता है”, like ऐप). macOS: “macOS ने … नहीं जोड़ा”.
- Plurals: one/other. Loan nouns do not inflect (1 सेल / 3 सेल, 1 आइटम / 3 आइटम), so most forms are identical but every
  plural key still gets both.
- Abbreviated units as Foundation writes them for hi: घं॰, मि॰, से॰, मि॰से॰ (ms). Points: “%@ पॉइंट” (System Settings ▸
  Accessibility text size), pixels: पिक्सेल.
- Typed timer durations stay Latin (“25 या 90s”): `DurationParser` accepts English and Russian unit words only, so a
  Devanagari suffix (90से॰) would not parse.

## Cranny's own concepts

| English | Hindi | Notes |
|---|---|---|
| Cranny | Cranny | never translated/transliterated; masculine |
| notch | नॉच | “नॉच पर ड्रॉप करें”, “बिना नॉच वाले डिस्प्ले” |
| camera housing | कैमरा हाउसिंग | |
| panel (the open Cranny) | पैनल | “खुला पैनल” |
| Home (built-in page) | होम | tab; never “Nook” |
| Tray | ट्रे | “ट्रे में रखें”, “ट्रे से हटाएँ”, “ट्रे साफ़ करें” |
| item (in the Tray) | आइटम | invariant |
| Layout & Widgets | लेआउट और विजेट | Settings pane |
| layout | लेआउट | |
| page | पृष्ठ | as macOS (“होम स्क्रीन पृष्ठ”) |
| widget / widget library | विजेट / विजेट लाइब्रेरी | |
| cell (grid) | सेल | |
| Live Activities / live activity | लाइव ऐक्टिविटी | Apple's own name (Control Center settings); feminine; short form ऐक्टिविटी |
| peek | मिनी व्यू | never “झलक” (= Quick Look) and never “प्रीव्यू” (= Preview); peek toggles end in दिखाएँ (“बदलाव पर मिनी व्यू दिखाएँ”, “होवर पर मिनी व्यू दिखाएँ”) |
| compact (state) | कॉम्पैक्ट | |
| satellite | सैटेलाइट | macOS uses सैटेलाइट in System Settings |
| HUD | संकेतक | Apple's word for “indicator”; search terms keep HUD. Replace the system HUD (toggle) = सिस्टम संकेतक की जगह इस्तेमाल करें; another app “takes the keys” = कीज़ को अपने नियंत्रण में ले सकता है |
| pipeline | पाइपलाइन | feminine |
| step (pipeline) | चरण | |
| drop zone | ड्रॉप ज़ोन | |
| Pin / Unpin | पिन करें / अनपिन करें | as macOS |
| Keep (Cranny) open | (Cranny को) खुला रखें | the pin command |
| Demo mode | डेमो मोड | |
| tutorial | ट्यूटोरियल | English never says “tour”; search words may |
| welcome (window) | स्वागत | “Cranny में आपका स्वागत है” |
| Command palette | कमांड पैलेट | |
| Type to capture | टाइप करके जोड़ें | |
| Quick Apps | क्विक ऐप्स | Cranny's widget name (cf. macOS “क्विक नोट”) |
| tile (Quick Apps) | टाइल | |
| Mirror (widget) | दर्पण | “Mirror the image” = इमेज को मिरर करें (as macOS) |
| Notes / note | नोट्स / नोट | as Apple's Notes |
| To-dos / to-do | कार्य | “नया कार्य”, “%lld बाकी” |
| Timer | टाइमर | |
| Calendar · event · meeting | कैलेंडर · इवेंट · मीटिंग | as Apple's Calendar (इवेंट) |
| Join (meeting) | जुड़ें | as FaceTime; VoiceOver “मीटिंग से जुड़ें”; the capsule is also जुड़ें |
| Meeting soon / Meeting in progress | जल्द ही मीटिंग / मीटिंग जारी है | |
| Media · player · track · song | मीडिया · प्लेयर · ट्रैक · गीत | |
| sound output | ध्वनि आउटपुट | Apple's “Sound Output”; never साउंड आउटपुट |
| built-in display | बिल्टइन डिस्प्ले | Apple's spelling (no hyphen) |
| up to date | अप-टू-डेट | as Software Update |
| longer side (of an image) | लंबा किनारा | Apple's “long edge”; not भुजा |
| any files (kind of file) | कोई भी फ़ाइल | कोई भी takes the singular |
| Now Playing | अभी चल रहा है | Apple's term |
| visualizer (Ambient / Live / Static / Off) | विज़ुअलाइज़र (ऐम्बिएंट / लाइव / स्थिर / बंद) | |
| media helper | मीडिया हेल्पर | |
| Apple Events fallback | Apple Events फ़ॉलबैक | macOS uses फ़ॉलबैक |
| artwork | कलाकृति | Apple: ऐल्बम कलाकृति |
| accent / accent color | ऐक्सेंट / ऐक्सेंट कलर | Apple's term |
| Ambient light · Effect · Underglow | ऐम्बिएंट लाइट · प्रभाव · नीचे की चमक | |
| Quality (the light: Detailed · Efficient) | गुणवत्ता (विस्तृत · किफ़ायती) | Settings ▸ Appearance ▸ Light; search keywords मेमोरी · प्रदर्शन |
| Floating island · Attached · Glass island | फ़्लोटिंग आइलैंड · जुड़ा हुआ · ग्लास आइलैंड | |
| handle (no-notch) | हैंडल | |
| Notch fit | नॉच फ़िट | |
| Excluded apps | बाहर रखे गए ऐप्स | |
| Confirmations | पुष्टियाँ | |
| Alerts · Ongoing · Passive (priority classes) | अलर्ट · जारी · निष्क्रिय | |
| Bluetooth devices | Bluetooth डिवाइस | |
| keys / keyboard shortcut | कीज़ / कीबोर्ड शॉर्टकट | “Shortcuts” in Settings ▸ Keyboard = कीबोर्ड शॉर्टकट |
| shortcut (a Shortcuts.app shortcut) | शॉर्टकट | the app itself in sentences: शॉर्टकट ऐप |

## Standard verbs and states (as macOS)

| English | Hindi |
|---|---|
| Settings / Settings… / System Settings | सेटिंग / सेटिंग… / सिस्टम सेटिंग |
| Open / Close / Quit Cranny | खोलें / बंद करें / Cranny बंद करें |
| About / About Cranny | परिचय / Cranny परिचय |
| Add / Remove / Delete | जोड़ें / हटाएँ / डिलीट करें |
| Rename | नाम बदलें |
| Move up / down / left / right | ऊपर / नीचे / बाएँ / दाएँ मूव करें |
| Resize | आकार बदलें |
| Edit | संपादित करें |
| Done | पूर्ण (flash words in the wings: हो गया; Done editing = संपादन समाप्त करें; All done = सब हो गया) |
| Cancel / Continue / Back / Skip | रद्द करें / जारी रखें / वापस / स्किप करें |
| Undo | पहले जैसा करें |
| Try again | फिर कोशिश करें |
| Reset to Default · Changed from the default | डिफ़ॉल्ट पर रीसेट करें · डिफ़ॉल्ट से बदला गया |
| Allow… / Grant… | अनुमति दें… |
| Allowed / Granted · Denied · Not yet · Restricted · Unknown | अनुमति है · अस्वीकृत · अभी नहीं · प्रतिबंधित · अज्ञात |
| On / Off · Never · Automatic | चालू / बंद · कभी नहीं · ऑटोमैटिक |
| Show / Hide | दिखाएँ / छिपाएँ |
| Dismiss (an activity) | छिपाएँ |
| click · double-click · drag · drop · swipe · press · hold | क्लिक करें · डबल-क्लिक करें · ड्रैग करें · ड्रॉप करें · स्वाइप करें · दबाएँ · दबाए रखें |
| pointer · rest the pointer · hover | पॉइंटर · पॉइंटर रखें · होवर |
| Show on · Display with the pointer | कहाँ दिखाएँ · पॉइंटर वाला डिस्प्ले |
| Fold away after | निष्क्रियता के बाद समेटें |
| Instant (motion, delay) | तुरंत |
| Preview | प्रीव्यू |
| Typing effect | टाइपिंग इफ़ेक्ट |
| Untitled | अनामांकित |
| Quick Look | झलक देखें |
| Share… · Show in / Reveal in Finder | शेयर करें… · Finder में दिखाएँ |
| Loading… | लोड हो रहा है… |

## Wing words (compact band, measured with CoreText at 13 pt semibold rounded)

| English | Hindi | width |
|---|---|---|
| Hi | नमस्ते | 28.5 pt |
| Paused | पॉज़ | 21.3 pt |
| Resumed | चालू | 21.9 pt |
| Copied · Done (Quick Apps) | हो गया | 34.3 pt |
| Failed | विफल | 32.1 pt |
| Timer done (band) | समाप्त | 32.7 pt |
| in %@ (wing, preview) | %@ | the duration alone, as Russian |

## Apple's names (from `apple-terms.py hi`)

सिस्टम सेटिंग · गोपनीयता और सुरक्षा · ऐक्सेसिबिलिटी · ऑटोमेशन · कैलेंडर · कैमरा · Bluetooth · सिस्टम ऑडियो रिकॉर्डिंग ·
लॉगइन आइटम · सामान्य · प्रकटन · कीबोर्ड · निम्न पावर मोड · डाउनलोड · संगीत · शॉर्टकट · नोट्स · Finder · Dock · Spotlight ·
Mission Control · AirDrop · गति घटाएँ · पारदर्शिता घटाएँ · कॉन्ट्रास्ट बढ़ाएँ · रंग के बिना अंतर करें · झलक देखें ·
alert sounds: बूप, ब्रीज़, बबल, क्रिस्टल, फ़ंकी, हीरोइन, छलांग, मेज़ो, पेबल, प्लक, पॉन्ग, सोनार, सोनुमी, सबमर्ज.
