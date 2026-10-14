# Cranny — Portuguese (Portugal) (pt-PT) terminology

European Portuguese only (pt-BR has its own file). Base: Apple's own `pt_PT` macOS 27 wording
(`apple-terms.py pt-PT` plus System Settings, Finder, Clock, Music and FaceTime loctables), never Brazilian forms
(ficheiro, ecrã, câmara, aceder, utilizador, definições, aplicação — not arquivo, tela, câmera, acessar, usuário,
ajustes, app).

## Voice and typography

- Neutral formal address as macOS pt-PT: verbs in the 3rd person without a pronoun ("Clique…", "Arraste…", "Pode…"),
  possessives "o seu / a sua" only when needed ("os seus eventos"); never "tu", never "você" written out.
- **Buttons, menu items, toggles, commands, pickers: infinitive** ("Abrir o Cranny", "Procurar atualizações…",
  "Mostrar o valor"). **Instructions in sentences and coach marks: imperative** ("Clique no entalhe", "Prima ⌘",
  "Pouse o cursor aqui"). Footnotes and statuses: present indicative.
- Sentence case everywhere; English title-case menu items become sentence case ("Check for Updates…" →
  "Procurar atualizações…").
- Quotes “…” (secondary ‘…’), as macOS 27 pt-PT writes them (not « »). One-character ellipsis …. Apostrophe ’.
- Hyphens inside words are U+2011 (non-breaking hyphen) as in Apple pt-PT ("ative‑o", "pré‑visualização",
  "Wi‑Fi", "e‑mail"); search keywords keep the plain hyphen-minus so typed queries match.
- Paths: "Definições ▸ Permissões" with a no-break space before ▸ (Apple writes "Definições do Sistema > Teclado"
  with U+00A0); path parts are not quoted. Setting names and Cranny's mode names in running text are quoted:
  “Reduzir movimento”, “Ao vivo”, “Entrar”.
- Gender: **o Cranny** (masculine, with the article, as Apple writes "Sair do Safari", "Acerca do Safari",
  "Ocultar o Safari"); **o macOS**; **o Mac**; **a aplicação**; **o widget**.
- Errors: "Não foi possível …" (Apple pt-PT). Retry: "Tentar novamente". Loading: "A carregar…" (a + infinitive
  progressive, also "A verificar…", "A reproduzir").
- Plurals: pt-PT = one / many / other; one = exactly 1; many (millions) always has the same wording as other.
- Pronominal verbs when the thing itself changes state: "a câmara liga‑se / desliga‑se", "as formas desvanecem‑se",
  "o puxador desaparece"; statuses say "Começa…", not a bare "Inicia…" (review).
- Picker values agree with the picker's noun: Linguagem ▸ "Automática"; Câmara ▸ "Automática"; Densidade ▸
  "Compacta / Espaçosa"; a shared generic "Off" stays "Desativado" (review).
- Lists: one determiner per noun ("A sua música, o calendário, os ficheiros e os atalhos…") (review).
- Keys in running text as Apple pt-PT names them: tecla Comando (⌘), Opção (⌥), Controlo (⌃), Shift, Escape/Esc,
  Return, Espaço, seta para cima / para baixo. Verb for keys: premir ("Prima ⌘", "Mantenha premida a tecla ⌘").

## Cranny's own vocabulary

| English | pt-PT | Note |
|---|---|---|
| Cranny | Cranny | never translated; masculine with article: "o Cranny", "do Cranny", "no Cranny"; also the open panel ("Abrir o Cranny") |
| notch | entalhe | "no entalhe", "sobre o entalhe", "para o entalhe"; group header "Entalhe" |
| camera housing | zona da câmara | |
| open panel | painel | "o painel aberto" |
| Home (built-in page, tab) | Início | tab ≤ 12 characters |
| Tray (page, pane, module) | Bandeja | lower case in running text: "na bandeja", "Manter na bandeja", "Remover da bandeja", "Esvaziar a bandeja" |
| item (Tray) | elemento / elementos | as Finder ("Comprimir 3 elementos…") |
| Files (widget) | Ficheiros | |
| Live Activities (pane, feature) | Atividades em tempo real | Apple's own pt-PT term; one = atividade; short = atividades |
| Pause Live Activities | Pausar atividades em tempo real | durations "Durante 1 hora / Até amanhã / Até eu retomar" |
| Paused / Resumed (wing words) | Em pausa / Ativas | measured: "Em pausa" 60 pt (wide slot), "Ativas" 39 pt; "Retomadas" (70 pt) fits no wing |
| peek | espreitadela (noun) / espreitar (verb) | never "Vista rápida" (= Quick Look) nor "pré‑visualização" (= Preview) |
| compact (state) | compacto | |
| satellite | satélite | |
| HUD | indicador | pane "Indicador"; "indicador do sistema", "indicador de volume"; search terms keep "HUD", "OSD" |
| widget | widget (m.) | "Biblioteca de widgets", "Adicionar widget" |
| cell (grid) | célula | "3 células", "Resta 1 célula / Restam 3 células" |
| page | página | |
| layout | disposição | Apple pt-PT "Disposição"; "Disposição e widgets", "Editar disposição", "disposição inicial" |
| Keep open / pin | Manter aberto / afixar | Apple pt-PT pin = afixar / desafixar; "Manter o Cranny aberto", "Desafixar o Cranny", "botão do alfinete" |
| pipeline | sequência | "As suas sequências", "Sequências afixadas", "Nova sequência…"; step = passo |
| drop zone | zona | "Zona 1–3"; VoiceOver "Zonas para largar" |
| drag / drop | arrastar / largar | Apple pt-PT "Arrastar e largar"; instructions prefer "Arraste … para o entalhe" |
| click | clicar / clique | |
| hover / rest the pointer | passar o cursor / pousar o cursor | Apple pt-PT "pousar o cursor"; option value "Ao passar o cursor" |
| pointer | cursor | Apple pt-PT (never "ponteiro") |
| keyboard shortcut | atalho de teclado (short: atalho) | |
| Shortcuts (Apple's app) | Atalhos | an item of it = atalho; pane "Atalhos"; Run = Executar (Apple pt-PT "Executar atalho") |
| Quick Apps | Aplicações rápidas | "Adicionar às aplicações rápidas", "Remover das aplicações rápidas" |
| tile (Quick Apps) | mosaico | |
| launcher | lançador | search keyword |
| Command palette (⌘K) | Paleta de comandos | |
| Settings | Definições | as Apple pt-PT "Definições…"; always capitalised as the window's name ("Abrir Definições", "Definições ▸ Teclado"); System Settings in running text = Definições do Sistema |
| About (Settings pane) | Informações | Apple pt-PT names System Settings ▸ Geral ▸ About "Informações"; the menu item "About Cranny" keeps AppKit's "Acerca do Cranny" (review) |
| real notch (vs. the preview) | entalhe real | not "entalhe verdadeiro" (review) |
| pipeline finished (VoiceOver) | Sequência “%@” concluída | names what finished, like "O atalho “%@” terminou" (review) |
| Permissions | Permissões | Allow… / Grant… = Permitir…; Allowed / Granted = Permitido; Denied = Negado; Restricted = Restrito |
| Demo mode | Modo demo | Apple pt-PT |
| tutorial | tutorial | Skip = Ignorar tutorial (Apple pt-PT Skip = Ignorar); Show = Mostrar tutorial |
| Welcome | boas‑vindas | window title "Damos‑lhe as boas‑vindas ao Cranny" (Apple pt-PT formula) |
| Done (button) | OK | Apple pt-PT; flash word: Concluído; Timer done (≤ 6): Fim; To-dos all done: Tudo feito |
| Copied / Failed / Hi (flash) | Copiado / Falhou / Olá | measured: 53 / 42 / 22 pt |
| Remove (from a list, page, Tray) | Remover | Delete (destroy) = Apagar (Apple pt-PT) |
| Dismiss | Ocultar | a banner's close button: Fechar |
| App not installed | Aplicação não instalada | |
| Reset to Default | Repor predefinição | "Alterado em relação à predefinição"; Reset = Repor |
| Media (module) | Multimédia | Apple pt-PT ("Multimédia e Apple Music") |
| Now Playing | A reproduzir | Apple pt-PT |
| player | leitor | |
| track / song | faixa / música | |
| media helper | auxiliar multimédia | |
| Apple Events fallback | alternativa Apple Events | |
| visualizer modes Live · Ambient · Static · Off | Ao vivo · Ambiente · Estático · Desativado | a live stream = "Em direto" |
| artwork | capa | |
| Calendar · event · meeting | Calendário · evento · reunião | |
| Join | Entrar | everywhere ("Entrar na reunião"); measured 35 pt in the capsule like Russian «Войти» ("Aceder", FaceTime's word, is 40 pt) |
| Meeting soon / in progress | Reunião em breve / Reunião em curso | |
| time left (meeting, timer, media) | Falta: %@ | Apple pt-PT's agreement-free pattern ("%@ left" → "Falta: %@"); "Agora · falta: 12 min"; counted to-dos use the plural ("Falta 1" / "Faltam 3"); battery time = "Autonomia: %@"; elapsed = "Decorrido: %@" / "Em curso há %@" |
| in %@ (compact band) | %@ | no room for "em": "4 min" alone, as Russian «4 мин» |
| Lead time | Antecedência | |
| Mirror | Espelho | |
| Notes · note | Notas · nota | Focus (the widget's mode) = Foco / Sair do foco, never Apple's "Concentração" |
| To-dos · to-do | Tarefas · tarefa | "Faltam 3" |
| Timer | Temporizador | presets = Predefinições (Apple Clock pt-PT) |
| Start / Pause / Resume / Stop | Iniciar / Pausar / Retomar / Parar | |
| Display | monitor | built-in = monitor integrado; Display with the pointer = Monitor com o cursor; screen = ecrã |
| Show on | Mostrar em | |
| full screen | ecrã completo | "aplicações em ecrã completo" |
| Excluded apps | Aplicações excluídas | |
| Floating island · Attached | Ilha flutuante · Acoplado | Glass island = Ilha de vidro; Liquid Glass stays |
| handle | puxador | |
| ambient light | luz ambiente | Off / Subtle / Vivid = Desativada / Suave / Intensa |
| Accent · Mono · Semantic (HUD colors) | Realce · Branco · Por tipo | Apple pt-PT "Cor de realce" |
| Typing effect | Efeito de escrita | |
| Instant | Instantâneo | |
| Preview (Settings stage) | Pré‑visualização | |
| Fold away after | Recolher após | |
| Make way for the menu bar | Dar espaço à barra de menus | |
| Alerts · Ongoing · Passive | Alertas · Em curso · Passivas | |
| Zip · Unzip · Compress | Criar ZIP · Descomprimir · Comprimir | Finder's "Comprimir" makes a zip, so the image step keeps "Comprimir" and Zip says "Criar ZIP" |
| archive (zip) | arquivo | dated base name "Arquivo" |
| Quick Look | Vista rápida | Apple pt-PT |
| Show / Reveal in Finder | Mostrar no Finder | Apple pt-PT |
| Type to capture | Captura ao escrever | |
| Rename… | Alterar nome… | Apple pt-PT |
| Back (Welcome) | Anterior | Apple pt-PT |

## Apple names used (from `apple-terms.py pt-PT` and the system loctables)

Definições do Sistema (Dock name "Definições") · Privacidade e segurança · Acessibilidade · Automatização ·
Calendários · Câmara · Bluetooth · Gravação de áudio do sistema · Início de sessão e extensões / elementos de início de
sessão · Descargas · Aplicações (folder) · Bateria · Modo de baixo consumo · Música · Calendário · Atalhos · Finder ·
Spotlight · Mission Control · Dock · Vista rápida · “Reduzir movimento” · “Reduzir transparência” · “Distinguir sem
cor” · Janelas da aplicação · Capturas de ecrã · Mostrar menu Ajuda · Espaço · Feedback háptico ·
alert sounds Boop, Brisa, Bolha, Cristal, Funky, Heroína, Salto, Mezzo, Seixo, Dedilhar, Pong, Sonar, Sonumi, Submergir.
