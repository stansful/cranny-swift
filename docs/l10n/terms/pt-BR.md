# Cranny — Portuguese (Brazil) (pt-BR) terminology

Base: Apple's own Brazilian macOS wording (`apple-terms.py pt-BR`, AppKit/Finder/System Settings/Clock loctables
read on this Mac). Brazilian vocabulary only: arquivo, tela, câmera, app, apagar, Ajustes do Sistema.

## Voice and typography

- **você**, as macOS ("seus eventos", "Clique…", "Arraste…"). Instructions to the user: imperative with você
  forms (Clique, Arraste, Solte, Pressione, Mantenha pressionada, Deixe o ponteiro…).
- **Buttons, menu items, toggles, commands: infinitive** ("Abrir o Cranny", "Mostrar valor", "Buscar Atualizações…").
- **Capitalization:** where English uses title case for standard macOS chrome (menu bar menu, AppKit-style buttons
  such as "Check for Updates…", "Reset to Default", "Move Up"), follow Apple pt-BR title case: nouns, verbs and
  adjectives capitalized, articles/prepositions lower case ("Buscar Atualizações…", "Mover para Cima",
  "Redefinir para o Padrão", "Até Eu Retomar"). Everything else is sentence case, like the English source.
- Quotes “…” (secondary ‘…’), apostrophe ’, one-character ellipsis …. Apple names of settings and panes in running
  text are written as macOS writes them, without quotes ("em Privacidade e Segurança ▸ Acessibilidade"); Apple app
  names that are also common words get "app" in front instead of quotes ("os apps Música e Spotify").
  User content (note titles, app names passed as arguments) in “%@” where Apple quotes them.
- Errors: "Não foi possível…" (Apple pt-BR). Units: "min", "h", "ms", "px", "pt"; numbers/durations arrive formatted
  (pt-BR durations are "4min", "1h 30min").
- Gender: **o Cranny** (masculine, like "o app"); **o macOS**; **o app / os apps**; **o Mac**; **o notch**;
  **a Bandeja**; **o widget**.
  Commands with the brand (menu items, buttons, ⌘K commands, shortcut names) have no article, as Apple pt-BR
  ("Encerrar Safari" → "Encerrar Cranny", "Abrir Cranny", "Manter Cranny Aberto"); running text and row labels take
  it ("o Cranny mostra…", "Sobre o Cranny", row label "Abrir o Cranny"). The welcome cheat sheet lists commands, so
  no article there either ("Abrir ou fechar Cranny", "Fechar Cranny", "Manter Cranny aberto").
- Confirmation messages and footnotes about what an action will do use the **future** ("Todos os ajustes do Cranny
  voltarão ao padrão", "As cópias … serão apagadas", "Notas, tarefas e arquivos da Bandeja serão mantidos").
- Key combinations as Apple pt-BR writes them, with " + ": "Option + 1", "Command + Seta para Cima"; key names
  Option, Command, Shift, Return, Esc, Delete, Espaço (Spotlight pane), "Mantenha Option pressionada".
- Plurals: pt = one / many / other. **one covers 0 and 1** (Apple pt-BR also writes the singular there:
  "%d item"); **many** (millions) always has the same wording as other. The singular for 0 is the normative
  Brazilian rule (numbers below 2 take the singular: "zero hora", "zero grau"), so "0 dia" / "0 célula livre" are
  correct and stay; no key is reworded to dodge it.

## Cranny's own vocabulary

| English | pt-BR | Note |
|---|---|---|
| Cranny | Cranny | never translated; masculine ("o Cranny"); also the open panel ("Abrir Cranny") |
| notch | notch | masculine: "o notch", "no notch", "sobre o notch"; Apple pt-BR has no UI word for it (Finder only says "câmera integrada"); Brazilian users and press say "notch" |
| camera housing | área da câmera | |
| open panel | painel | "o painel aberto" |
| Home (built-in page, tab) | Início | tab ≤ 12 characters |
| Tray (page, pane) | Bandeja | Cranny's name, capitalized like English: "na Bandeja", "Limpar Bandeja", "Remover da Bandeja", "Manter na Bandeja" |
| item (Tray) | item / itens | as Finder |
| Files (widget) | Arquivos | |
| Live Activities (pane, feature) | Atividades ao Vivo | Apple's own pt-BR term; one activity = atividade (lower case in running text) |
| Pause Live Activities | Pausar Atividades ao Vivo | menu: Por 1 Hora / Até Amanhã / Até Eu Retomar |
| Paused / Resumed (wing words) | Pausadas / Ativas | measured: "Pausadas" fits the wide wing (60 pt of 72), "Ativas" the medium (39 of 48); "Retomadas" (70 pt) fits none |
| peek | espiada | verb "espiar" (iOS pt-BR "Espiar"); never "Visualização Rápida" (= Quick Look) |
| compact (state) | compacto | |
| satellite | satélite | |
| HUD | indicador | pane "Indicador"; "indicador de volume", "indicador do sistema"; search terms keep "HUD", "OSD" |
| widget | widget | masculine; "Biblioteca de widgets" |
| cell (grid) | célula | "%lld células livres" |
| page | página | |
| layout | layout | masculine: "Layout e Widgets", "Editar layout", "layout inicial" |
| Keep open / pin | Manter aberto / fixar | "Manter Cranny Aberto" (menu), "Manter o Cranny aberto" (sentence case), "Desafixar Cranny", "Fixar/desafixar"; pin button = botão de alfinete (as Apple "Fixar Aba") |
| pipeline | fluxo | "Seus fluxos", "Fluxos fixados", "Novo Fluxo…"; step = etapa |
| drop zone | zona para soltar | pinned slots: "Zona 1–3" |
| drag / drop | arrastar / soltar | |
| click | clicar / clique | Apple pt-BR |
| press (keys) | pressionar | "Mantenha ⌘ pressionada" |
| hover / rest the pointer | passar o ponteiro / deixar o ponteiro sobre | Settings ▸ General "Abrir o Cranny": Ao passar o ponteiro / Ao clicar / Só pelo atalho; onboarding cards: Passar o ponteiro / Clicar / Só o atalho; Hover delay = Atraso ao passar o ponteiro (not "Atraso do ponteiro", which reads as pointer lag); Hold ⌥ to pass over = Não abrir com ⌥ pressionada |
| keyboard shortcut | atalho de teclado (short: atalho) | Apple: "Atalhos de Teclado…"; Settings ▸ Keyboard section = "Atalhos de teclado" |
| Shortcuts (Apple's app) | Atalhos | an item of it = atalho; Cranny's pane named after it = "Atalhos" |
| Quick Apps | Apps Rápidos | Cranny's name: "Adicionar aos Apps Rápidos", "Remover dos Apps Rápidos" |
| tile (Quick Apps) | bloco | |
| launcher | lançador | search keyword only |
| Command palette (⌘K) | Paleta de comandos | |
| Settings (Cranny's window) | Ajustes | as Apple pt-BR "Ajustes…"; System Settings = Ajustes do Sistema; paths "Ajustes ▸ Teclado" |
| Permissions | Permissões | Allow… / Grant… = Permitir…; Denied = Negado; Granted = Permitido; Not yet = Ainda não; Restricted = Restrito |
| Demo mode | Modo de demonstração | menu: "Modo de Demonstração" |
| tutorial | tutorial | Skip = Pular tutorial; Show = Mostrar tutorial; never "tour" |
| Welcome | boas-vindas | window title "Boas-vindas ao Cranny" (Apple's current neutral form) |
| Done (button) | OK | Apple pt-BR; Welcome's closing button (also VoiceOver's word for a finished step) = Concluído; Quick Apps flash = Pronto; Timer band = Fim |
| Copied / Failed / Hi (flash) | Copiado / Falhou / Olá | measured: Copiado wide (53 of 72), Falhou medium, Olá medium |
| Remove (from a list, page, Tray) | Remover | Delete (destroy: note, to-do, pipeline) = Apagar (Apple pt-BR) |
| App not installed | App não instalado | |
| Reset to Default | Redefinir para o Padrão | "Alterado em relação ao padrão"; Reset = Redefinir |
| Media (module) | Mídia | Apple pt-BR "Mídia e Apple Music" |
| Now Playing | Reproduzindo | Apple pt-BR (Control Center) |
| player | player | masculine; Brazilian usage ("o player") |
| track / song | faixa / música | Apple Music pt-BR |
| media helper | auxiliar de mídia | |
| Apple Events fallback | alternativa via Apple Events | |
| visualizer modes Live · Ambient · Static · Off | Ao vivo · Ambiente · Estático · Desativado | |
| artwork | capa | |
| Calendar · event · meeting | Calendário · evento · reunião | |
| Join | Entrar | Apple pt-BR (Calendar, FaceTime); "Entrar na reunião"; the row's short capsule is also "Entrar" (narrower than Russian «Войти») |
| Meeting soon / in progress | Reunião em breve / Reunião em andamento | |
| time left | faltam %@ | "Agora · faltam 12min"; band uses the bare duration ("4min"), as Russian |
| time elapsed | começou há %@ | |
| Lead time | Antecedência | |
| Mirror | Espelho | |
| Notes · note | Notas · nota | Focus (the widget's own mode) = Focar / Sair do foco, never Apple's "Foco" |
| To-dos · to-do | Tarefas · tarefa | "%lld restantes"; "Tudo feito" |
| Timer | Timer | Apple pt-BR Clock; presets = Pré-ajustes; Timer done = Timer concluído; "Ends 14:35" = "Até 14:35" (ring caption); units under presets h / min / seg |
| Start / Pause / Resume / Stop | Iniciar / Pausar / Retomar / Parar | Apple Clock pt-BR |
| Display (screen) | tela | built-in = Tela integrada; Display with the pointer = Tela com o ponteiro (Apple pane "Telas") |
| Show on | Mostrar em | |
| full screen | tela cheia | "apps em tela cheia" |
| Excluded apps | Apps excluídos | file-panel button "Excluir" (exclude). Confirmed: Apple pt-BR uses "excluir" for exclude (Spotlight "excluir da indexação", VPN "Domínios Excluídos", Notes, Mail "Excluir Anexos") and "Apagar" for Delete, so every destructive Delete is "Apagar" |
| Floating island · Attached | Ilha flutuante · Acoplado | Glass island = Ilha de vidro; Liquid Glass stays |
| handle | alça | |
| ambient light | luz ambiente | Off / Subtle / Vivid = Desativado / Suave / Intensa |
| Accent · Mono · Semantic (HUD colors) | Realce · Branco · Por tipo | accent color = cor de realce (Apple pt-BR) |
| keyboard backlight | retroiluminação do teclado | Apple pt-BR (Ajustes ▸ Teclado "Desligar a retroiluminação do teclado após inatividade"); HUD toggle "Retroiluminação do teclado", keys "teclas de retroiluminação"; the HUD's own title for the level is "Brilho do teclado" (Apple "Brilho do teclado") |
| Mute / Unmute | Silenciar / Reativar som | Apple pt-BR "Reativar Som"; Muted = Silenciado |
| Game controller | Controle de videogame | Apple pt-BR "Controle de Videogame" |
| Teal (swatch) | Verde-acinzentado | Apple pt-BR wallpaper colour name (WallpaperGradientExtension), kept |
| Typing effect | Efeito de digitação | |
| Instant | Instantâneo | |
| Preview (Settings stage) | Pré-visualização | the Preview app is "Pré-Visualização" |
| Fold away after | Recolher após inatividade | |
| Make way for the menu bar | Dar espaço à barra de menus | |
| Alerts · Ongoing · Passive | Alertas · Em andamento · Passivas | |
| Dismiss | Ocultar | (the Reset All banner's close button: Fechar) |
| Zip · Unzip · Compress | Criar ZIP · Descompactar · Comprimir | Finder's "Comprimir" makes a zip, so the zip step says "Criar ZIP" explicitly |
| archive (zip) | arquivo ZIP | dated base name "Arquivo" (as Finder's "Arquivo.zip") |
| Quick Look | Visualização Rápida | Apple pt-BR |
| Show / Reveal in Finder | Mostrar no Finder | Apple pt-BR |
| Share… | Compartilhar… | |
| Type to capture | Digitar para capturar | |
| haptic feedback | retorno tátil | Apple pt-BR trackpad pane |
| swipe (gesture) | deslizar | "Para trocar de faixa, deslize dois dedos para os lados"; toggles "Ocultar deslizando para cima" |
| Meeting soon band ("in 4m") | %@ | the bare duration "4min" (like Russian «4 мин»): "em 4min" is 49 pt in the 48-pt slot |
| Undo / Cancel | Desfazer / Cancelar | |
| Quality (the light: Detailed · Efficient) | Qualidade (Detalhada · Eficiente) | Settings ▸ Appearance ▸ Light; search keywords memória · desempenho |

## Apple names used (from `apple-terms.py pt-BR`)

Ajustes do Sistema · Privacidade e Segurança · Acessibilidade · Automação · Calendários · Câmera · Bluetooth ·
Gravação do Áudio do Sistema · Itens de Início · Downloads · Aplicativos (folder) · Bateria · Modo Pouca Energia ·
Música · Calendário · Atalhos · Finder · Spotlight · Mission Control · Dock · Visualização Rápida · Reproduzindo ·
Reduzir movimento · Reduzir transparência · Diferenciar sem cor · Janelas do aplicativo · Capturas de Tela ·
Menu de Ajuda · Layouts de Teclado · Space · Atividades ao Vivo ·
alert sounds Tinido, Brisa, Balão, Cristal, Funky, Heroína, Pulo, Médio, Seixo, Ronrom, Morse, Sonar, Sonumi, Submarino
(checked in Sound.appex AlertSounds.loctable: macOS 26 renamed the English sounds but kept these pt-BR names, so
they must stay even where the meaning differs from the new English name).
