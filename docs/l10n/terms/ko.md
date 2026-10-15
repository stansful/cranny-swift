# Cranny — Korean (한국어, `ko`) terminology sheet

Register and style follow Korean macOS 27 (checked in the system's own loctables):

- **Sentences** in the formal polite style macOS uses: statements “-습니다”, requests “-십시오”
  (“나중에 다시 시도하십시오.”, “인터넷 연결을 확인하십시오.”). No “당신”; “you/your” is omitted or, where
  needed, “사용자의” as Apple does.
- **Buttons, menu items, toggles, picker options and titles** are noun phrases, as macOS writes them:
  “취소”, “완료”, “열기”, “Cranny 종료”, “업데이트 확인…”, “메뉴 막대 아이콘 보기”, “로그인 시 열기”.
  Show-toggles are “… 보기” (System Settings: “메뉴 막대에서 보기”, “배터리 잔량 보기”); hide-toggles “… 가리기”.
  States and confirmations end in “-됨” (“일시 정지됨”, “복사됨”, “허용됨”).
- **Quotes**: ‘…’ around names and setting names (macOS: “‘%@’ 압축”, “‘세게 클릭 및 햅틱 피드백’ 업데이트”);
  “…” only inside them. Ellipsis … (one character). No straight quotes.
- **Particles** after a placeholder use both forms: ‘%@’을(를), 이(가), 은(는), 와(과), (으)로. After *Cranny*
  (vowel ending, 크래니) always 는 / 가 / 를 / 와 / 의 / 에서 / 로. After any other Latin name, choose by how
  it is read: “Spotify를”, “macOS가”, “PDF를”, “AirDrop으로”, “JPEG으로” (제이펙), “1600px로”.
- **Counts**: one plural form (`other`) with a counter: “%lld개 항목”, “%lld칸”, “%lld일”, “%lld분”, “%lld ms”.
- **Typed input**: hints that show what the user can type keep the Latin units the parsers accept: the timer
  hint is “25 또는 90s”, never “90초” (DurationParser reads only English and Russian units).
- **Spacing**: 띄어쓰기 as Apple (“일시 정지”, “하루 종일”, “미리 알림”); Latin names keep their spelling.
- **Cranny** is never translated or transliterated (no “크래니” in copy).

## Apple’s own names (from `apple-terms.py ko`, used verbatim)

| English | Korean |
|---|---|
| System Settings | 시스템 설정 |
| Privacy & Security ▸ Accessibility | 개인정보 보호 및 보안 ▸ 손쉬운 사용 |
| Automation · Calendars · Camera · Bluetooth | 자동화 · 캘린더 · 카메라 · Bluetooth |
| System Audio Recording (Screen & System Audio Recording) | 시스템 오디오 녹음 (화면 및 시스템 오디오 녹음) |
| Login Items | 로그인 항목 |
| Low Power Mode · Battery · battery level | 저전력 모드 · 배터리 · 배터리 잔량 |
| Live Activities (Apple and Cranny) | 실시간 현황 |
| Now Playing | 지금 재생 중 |
| Music · Shortcuts · Calendar · Notes (apps) | 음악 · 단축어 · 캘린더 · 메모 (“음악 앱”, “단축어 앱” in running text) |
| Quick Look | 훑어보기 |
| Downloads · Applications | 다운로드 · 응용 프로그램 |
| Reduce Motion · Reduce Transparency · Increase Contrast · Differentiate without color | ‘동작 줄이기’ · ‘투명도 줄이기’ · ‘대비 증가’ · ‘색상 제외하고 구별’ (quoted in running text) |
| Menu bar · Control Center · Mission Control · Spotlight · Dock | 메뉴 막대 · 제어 센터 · Mission Control · Spotlight · Dock |
| Trackpad · Force Touch · haptic feedback | 트랙패드 · Force Touch · 햅틱 피드백 |
| Swipe (two fingers) | 쓸어넘기기 (up 쓸어올리기, down 쓸어내리기) |
| Pointer · click · drag | 포인터 · 클릭 · 드래그 |
| Reveal in Finder / Show in Finder | Finder에서 보기 |
| Share… · Open · Rename · Delete · Remove · Undo | 공유… · 열기 · 이름 변경 · 삭제 · 제거 · 실행 취소 |
| Compress (Finder, zip) · Uncompress | 압축 · 압축 해제 |
| Remove Background · Copy Text · Make PDF | 배경 제거 · 텍스트 복사 · PDF 만들기 |
| Timer · Timer Done · Presets (Clock) | 타이머 · 타이머 완료 · 프리셋 |
| Alert sounds | Boop, Breeze, Bubble, Crystal, Funky, Heroine, Jump, Mezzo, Pebble, Pluck, Pong, Sonar, Sonumi, Submerge (macOS keeps them in English) |
| Shuffle · Repeat all · Repeat one (Music) | 임의 재생 · 전체 반복 · 하나만 반복 |
| Accent colours | 파란색, 보라색, 분홍색, 빨간색, 주황색, 노란색, 초록색, 흑색 (Graphite), 청록색 (Teal), 민트색, 남색, 갈색, 회색 |
| Accent color · Text size | 강조 색상 · 텍스트 크기 |
| Spaces · input source · Screenshots · Help menu | Space · 입력 소스 · 스크린샷 · 도움말 메뉴 |
| Option · Command · Return · Space keys | Option · Command · Return · Space(스페이스 바) |

## Cranny’s concepts

| English | Korean | Note |
|---|---|---|
| Cranny | Cranny | never translated; Cranny는 / Cranny가 / Cranny를; also the open panel (“Cranny 열기”) |
| notch | 노치 | the hardware cut-out; “노치에”, “노치로” |
| camera housing | 카메라 하우징 | Apple’s Korean support term |
| panel / open panel | 패널 / 열린 패널 | in copy usually “Cranny” |
| Home (built-in page) | 홈 | tab and page name |
| page | 페이지 | “페이지 %lld” |
| Tray | 선반 | “선반에 보관”, “선반에서 제거”, “선반 비우기”, “선반 열기”; never “트레이” |
| item (Tray) | 항목 | as Finder: “%lld개 항목” |
| drag / drop (files) | 드래그 / 놓기 | “파일을 노치로 드래그하십시오”; drop zone = 드롭 영역 |
| pipeline | 파이프라인 | “새로운 파이프라인…”, “고정된 파이프라인” |
| step (pipeline) | 단계 | |
| chip (in copy) | 버튼 | |
| live activity / Live Activities | 실시간 현황 | Apple’s term; one form for singular and plural |
| peek | 살짝 보기 | the 52-pt row under the notch; never “미리보기” (= Preview) or “훑어보기” (= Quick Look) |
| satellite | 위성 | |
| HUD | 표시기 | “음량 표시기”, “시스템 표시기 대체”; Settings ▸ 표시기; search keywords keep “HUD, OSD” |
| widget · widget library | 위젯 · 위젯 갤러리 | Apple: “위젯 갤러리” |
| layout | 레이아웃 | “레이아웃 편집” |
| Layout & Widgets (pane) | 레이아웃 및 위젯 | “및” as in Apple’s pane names |
| cell (grid) | 칸 | “%lld칸”, “%lld칸 남음”, “%lld칸 초과” |
| pin / keep open / unpin | 고정 / 고정 해제 | “Cranny 고정”, “Cranny 고정 해제” |
| Demo mode | 데모 모드 | |
| Settings | 설정 | “설정 ▸ 키보드” |
| Join (meeting) | 참여 | capsule “참여”; VoiceOver “회의 참여” |
| meeting · event | 회의 · 이벤트 | as Calendar |
| Reset to Default | 기본값으로 재설정 | |
| Changed from the default | 기본값에서 변경됨 | |
| Denied · Granted · Not yet · Restricted · Unknown | 거부됨 · 허용됨 · 요청 전 · 제한됨 · 알 수 없음 | permission pills (“요청 전”: short pill, as in the file) |
| Allow… / Grant… | 허용… | |
| Move up / down / left / right | 위로 이동 / 아래로 이동 / 왼쪽으로 이동 / 오른쪽으로 이동 | |
| Typing effect | 타이핑 효과 | |
| Instant | 즉시 | |
| Preview (Settings stage) | 미리보기 | |
| tutorial | 튜토리얼 | never “둘러보기” (= tour) |
| Show On / Show on | 표시 위치 | options “모든 디스플레이”, “내장 디스플레이”, “포인터가 있는 디스플레이”, “선택한 디스플레이” |
| Never (timeout 0) | 안 함 | Apple’s value word |
| Off / On (values) | 끔 / 켬 | Apple’s value words |
| Fold away after | 비활성 시 접기 | |
| Open Cranny with | Cranny 여는 방법 | Hover 포인터 올리기 · Click 클릭 · Shortcut only 단축키만 |
| Open %@ | ‘%@’ 열기 | |
| Style · Mono · Semantic (HUD colours) | 스타일 · 흰색 · 의미별 | |
| Quick Apps | 빠른 앱 | widget name |
| Shortcuts (Apple app) · a shortcut | 단축어 · 단축어 | “단축어 실행”; never “바로 가기” |
| keyboard shortcut | 단축키 | “키보드 단축키” |
| Mirror | 거울 | widget name |
| Notes · note | 메모 · 메모 | “새로운 메모” as Notes |
| To-dos · to-do | 할 일 · 할 일 | |
| Timer · preset | 타이머 · 프리셋 | as Clock |
| Media · player | 미디어 · 플레이어 | |
| Visualizer: Ambient · Live · Static · Off | 비주얼라이저: 앰비언트 · 라이브 · 정적 · 끔 | “앰비언트” as in Korean macOS loctables; never “분위기” |
| artwork | 앨범 표지 | Apple (Control Center ▸ Now Playing) |
| Files (widget) | 파일 | |
| Remove (from a list) | 제거 | “선반에서 제거”, “빠른 앱에서 제거”; 삭제 only for deleting data (note, to-do, pipeline) |
| App not installed | 설치되지 않은 앱 | |
| Excluded apps | 제외된 앱 | |
| Confirmations (Live Activities row) | 확인 메시지 | never “확인 표시” (= check mark) |
| Copied (wing) · Done · Failed | 복사됨 · 완료 · 실패 | fit the 48-pt wing (measured) |
| Paused · Resumed (pause confirmation) | 일시 정지됨 · 재개됨 | as the Timer’s paused state; measured: 60 pt (wide slot, 6.8 pt to spare) · 34 pt (medium). English “Paused” (46 pt) also takes the wide slot |
| Hi (greeting) | 안녕하세요 | 57 pt, wide slot |
| Pause Live Activities | 실시간 현황 일시 정지 | |
| Zip · Unzip | 압축 · 압축 해제 | as Finder / Archive Utility |
| Compress (images, video) | 용량 줄이기 | distinct from Zip |
| Convert · Resize | 변환 · 크기 조절 | |
| Ambient light · Light | 배경 조명 · 조명 | |
| Quality (the light: Detailed · Efficient) | 품질 (세밀하게 · 효율적으로) | Settings ▸ Appearance ▸ Light; search keywords 메모리 · 성능 |
| Floating island · Attached · Glass island | 플로팅 아일랜드 · 상단 부착 · 글래스 아일랜드 | Attached = a tab on the top edge (DESIGN.md §3); never “붙임형” |
| handle (no-notch) | 핸들 | |
| Density: Compact · Standard · Roomy | 밀도: 촘촘하게 · 표준 · 여유롭게 | |
| Motion: Calm · Standard · Lively · Instant | 동작: 차분하게 · 표준 · 생동감 있게 · 즉시 | |
| Alerts · Ongoing · Passive (priority classes) | 알림 · 진행 중 · 대기 | |
| Type to capture | 바로 입력 | |
| launcher (keyword) | 런처 | |
| Welcome (window) | Cranny 시작하기 | Apple: “Mac 시작하기” |
| Previous day · Next day (Calendar widget) | 전날 · 다음 날 | Apple Calendar: “전날” |
| Hide calendar titles (Demo mode) | 이벤트 제목 가리기 | the titles of events, not of calendars |
| Hold ⌥ to pass over | ⌥ 키로 열지 않고 지나가기 | |
| Remove items (Tray retention) | 항목 보관 기간: 직접 제거할 때까지 · Cranny 종료 시까지 · 하루 동안 | the label is a retention period, so the options are durations |
| Tea (sample timer) | 차 우리기 | “차” alone also means “car” |

## Review rulings (independent review)

- **Tray = 선반**: confirmed. It reads naturally in every phrase (“선반에 보관”, “선반에서 제거”, “선반 비우기”).
  “트레이” suggests the system tray, and “보관함” is Apple's word for Library.
- **HUD = 표시기**: confirmed. Korean macOS has no name for the volume overlay, “HUD” means nothing to most users,
  and the footnotes say what the 표시기 is. “HUD” and “OSD” stay as search keywords.
- **peek = 살짝 보기**: confirmed. It is short, natural, and clashes with neither 미리보기 nor 훑어보기.
- **Live Activities = 실시간 현황** (Apple's term), also for one activity: confirmed. The column header and segment
  fit (budget 12). A shortened “현황” would no longer be Apple's term.
- **Paused = 일시 정지됨, Hi = 안녕하세요**: kept. Both fit the wide slot that `FlashActivity.labelSlots` allows, at
  every notch unit, and English “Paused”, “Resumed” and “Copied” also take that slot. “일시정지” or “일시 정지”
  would still need the wide slot, and “안녕” is too casual for an app greeting.
- **Appearance = 모양**: confirmed. “화면 모드” is the System Settings pane for light and dark mode, and Cranny's
  pane covers more than that.
- **Register -습니다 / -십시오**: confirmed, as Korean macOS writes (“나중에 다시 시도하십시오.”, “…하겠습니까?”).
- **Visualizer = 비주얼라이저**: confirmed. Mode names are now 앰비언트 · 라이브 · 정적 · 끔.
- **Compress = 용량 줄이기, suffix “용량 줄임”**: confirmed. It stays distinct from Zip = 압축.
- **단축어 / 단축키 / 빠른 앱**: checked across all 1211 keys; no mix-ups.
- **Loanwords**: 플로팅 아일랜드 and 글래스 아일랜드 are kept (Apple keeps “Dynamic Island” and “Liquid Glass”
  as names). Attached is now 상단 부착.
- **권한 / 정보**, **경로 복사됨** for both counts, **%lld ms**, the localized sample data, and the English alert
  sound names: all confirmed.
