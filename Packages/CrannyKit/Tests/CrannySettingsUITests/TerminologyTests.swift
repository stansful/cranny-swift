// Russian wording across every String Catalog (ARCHITECTURE.md §8.7.7 glossary). Each target words its own strings,
// and Settings shows them side by side, so these checks read all catalogs from the source tree and fail when a shared
// control or term is worded differently, a retired wording comes back, or a row label ends in a preposition that
// bends the value after it («Показывать на [Встроенный дисплей]»). They run with `make test` and in CI.
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - Reading the catalogs

/// One entry of a String Catalog.
private struct CatalogEntry {
    let target: String
    let key: String
    /// The English text: the `en` value when the catalog has one (positional or plural keys; a plural's `other`
    /// form), otherwise the key.
    let english: String
    /// The Russian text, one element per plural form (in category order).
    let russian: [String]
    let comment: String

    var place: String { "\(target): \(key)" }
    /// Keys made with `defaultValue:` differ from their English on purpose (§8.7.3): never compared with other entries.
    var isPlainKey: Bool { Terms.normalized(key) == Terms.normalized(english) }
    var isSearchTerm: Bool { comment.localizedCaseInsensitiveContains("search") }
    var russianText: String { russian.joined(separator: " | ") }
}

private struct CatalogFile: Decodable {
    struct Entry: Decodable {
        let comment: String?
        let localizations: [String: Localization]?
    }
    struct Localization: Decodable {
        struct Unit: Decodable { let value: String }
        let stringUnit: Unit?
        let variations: [String: [String: Localization]]?

        /// Every form, plural variations flattened in category order.
        var forms: [String] {
            if let stringUnit { return [stringUnit.value] }
            return (variations ?? [:]).sorted { $0.key < $1.key }.flatMap { _, cases in
                cases.sorted { $0.key < $1.key }.flatMap(\.value.forms)
            }
        }
    }
    let strings: [String: Entry]
}

private enum Catalogs {
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")

    /// `Sources/<Target>/Resources/Localizable.xcstrings` of every target that has one, by target name.
    static func files() throws -> [(target: String, url: URL)] {
        try FileManager.default.contentsOfDirectory(atPath: sources.path).sorted().compactMap { target in
            let url = sources.appending(path: "\(target)/Resources/Localizable.xcstrings")
            return FileManager.default.fileExists(atPath: url.path) ? (target, url) : nil
        }
    }

    /// Every entry of every catalog.
    static func entries() throws -> [CatalogEntry] {
        try files().flatMap { target, url -> [CatalogEntry] in
            let file = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: url))
            return file.strings.map { key, entry in
                let localizations = entry.localizations ?? [:]
                return CatalogEntry(target: target, key: key,
                                    english: localizations["en"]?.forms.last ?? key,
                                    russian: localizations["ru"]?.forms ?? [],
                                    comment: entry.comment ?? "")
            }
        }
    }
}

// MARK: - The glossary

private enum Terms {
    /// Case and argument positions do not make a different text ("Move Up" = "Move up", "%1$@" = "%@").
    static func normalized(_ text: String) -> String {
        text.replacing(/%\d+\$/, with: "%").lowercased()
    }

    /// The words of a text, lowercased, as " w1 w2 … " so a pattern " stem" matches at a word start only. Digits stay
    /// in their word ("90с" is not the preposition «с»).
    static func words(_ text: String) -> String {
        " " + text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "%" && $0 != "@" }.joined(separator: " ") + " "
    }

    /// The same English text worded differently on purpose (normalized English → why).
    static let deliberatelyDifferent: [String: String] = [
        "%@ finished": "different subjects: a shortcut that ran (Quick Apps), a pipeline (Tray)",
        "%@ left": "the meeting countdown is the compact «ещё 12 мин»; elsewhere «осталось»",
        "app": "Calendar: a value after «Открывать встречи» («В приложении»); Quick Apps: a kind of tile",
        "check for updates": "a switch in onboarding («Проверять») and a button in Settings («Проверить»)",
        "click": "onboarding card title (nominative) vs the value after «Открывать Cranny» (instrumental)",
        "hover": "onboarding card title (nominative) vs the value after «Открывать Cranny» (instrumental)",
        "shortcut only": "onboarding card title (nominative, a narrow card) vs the value after «Открывать Cranny» (instrumental)",
        "dismiss": "closing the Reset All banner («Закрыть») vs hiding an activity («Скрыть»)",
        "in %@": "Calendar's sentence form «через %@» vs the compact countdown that drops the preposition",
        "now playing": "the Settings search adds the macOS name «Исполняется» as a synonym of «Сейчас играет»",
        "off": "the Mirror widget's spoken state «выключено» vs the «Выкл.» picker value",
        "open": "a state of the preview stage («Открыт») vs an action («Открыть»)",
        "open settings": "Mirror's chip opens System Settings («Настройки»); the Keyboard row opens Cranny's",
        "paused": "Media's spoken state «На паузе» vs the Timer's ring label «Пауза»",
        "resize": "a widget's width (NotchUI, search) vs the Tray's image step «Уменьшить»",
        "shortcuts": "Apple's Shortcuts app («Быстрые команды») vs keyboard shortcuts («Сочетания клавиш»)",
        "show": "a row label («Показывать») vs a VoiceOver action («Показать»)",
        "stop": "the Timer's short peek button «Стоп» vs «Остановить» in menus",
    ]

    /// Glossary decisions: wherever one of these English texts appears, its Russian is this.
    static let pinned: [(english: String, russian: String)] = [
        ("HUD", "Индикатор"),
        ("Reset to Default", "Вернуть значение по умолчанию"),
        ("Changed", "Изменено"),
        ("Changed from the default", "Изменено по сравнению со значением по умолчанию"),
        ("Changed from the default.", "Изменено по сравнению со значением по умолчанию."),
        ("Denied", "Запрещено"),
        ("Move up", "Переместить вверх"),
        ("Move down", "Переместить вниз"),
        ("Move left", "Переместить влево"),
        ("Move right", "Переместить вправо"),
        ("Typing effect", "Эффект набора"),
        ("Instant", "Мгновенно"),
        ("Preview", "Предпросмотр"),
        ("Open %@", "Открыть «%@»"),
        ("Show on", "Где показывать"),
        ("Display with the pointer", "На дисплее с указателем"),
        ("Never", "Никогда"),
        // Taking an app off a list is «Убрать» (as «Убрать с полки»); «Удалить приложение» reads as uninstalling it.
        ("Remove app", "Убрать приложение"),
        ("Remove %@", "Убрать «%@»"),
    ]

    /// Wordings that were replaced; " stem" matches at a word start (« сбросить» does not contain " брос").
    static let retired: [(pattern: String, use: String)] = [
        (" превью", "«Предпросмотр»"),
        (" брос", "«Перетащите» / «Перетащить» (drag and drop)"),
        (" крыл", "say what moves («Активности у выреза»); «крылья» is internal jargon"),
        (" hud", "«Индикатор» (search terms may keep HUD)"),
        (" до стандартного", "«Вернуть значение по умолчанию»"),
        (" от стандартного", "«Изменено по сравнению со значением по умолчанию»"),
        (" восстановить по умолчанию", "«Вернуть значение по умолчанию»"),
        (" вернуть по умолчанию", "«Вернуть значение по умолчанию»"),
        (" отказано", "«Запрещено»"),
        (" эффект печати", "«Эффект набора»"),
    ]

    /// macOS settings are quoted by their Russian names (macOS 27 Accessibility ▸ Display), never paraphrased.
    static let systemSettings: [String: String] = [
        "Reduce Motion": "Уменьшить движение",
        "Reduce Transparency": "Понизить прозрачность",
        "Increase Contrast": "Увеличить контраст",
        "Differentiate without color": "Дифференцировать без цвета",
    ]

    static let prepositions: Set<String> = ["в", "во", "на", "для", "через", "с", "со", "по", "о", "об", "обо", "к", "ко", "из",
                                            "от", "до", "при", "за", "под", "над", "у", "без", "после", "перед", "про", "между"]
    /// Labels whose value is always a number with a unit, which reads correctly after the preposition («за 5 мин»).
    static let numericValueLabels: Set<String> = ["CrannyCalendar: Lead time", "CrannyTray: Resize to"]
}

// MARK: - Checks

@Test func everyCatalogIsRead() throws {
    #expect(try Catalogs.files().count >= 16)                     // every target but CrannyMediaBridge (Objective-C)
    let entries = try Catalogs.entries()
    #expect(entries.count > 1000)
    #expect(entries.contains { $0.target == "CrannySettingsUI" && $0.key == "Show on" })
}

/// One English text, one Russian wording in every catalog (C-SET-4), unless listed in `deliberatelyDifferent`.
@Test func oneRussianWordingPerEnglishText() throws {
    let groups = Dictionary(grouping: try Catalogs.entries().filter(\.isPlainKey)) { Terms.normalized($0.english) }
    for (english, group) in groups where Terms.deliberatelyDifferent[english] == nil {
        let wordings = Set(group.map { Terms.normalized($0.russianText) })
        #expect(wordings.count == 1, "\(english): \(group.map { "\($0.place) → \($0.russianText)" })")
    }
}

@Test func glossaryTermsKeepTheirRussian() throws {
    let entries = try Catalogs.entries()
    for term in Terms.pinned {
        for entry in entries where entry.isPlainKey && Terms.normalized(entry.english) == Terms.normalized(term.english) {
            #expect(entry.russian == [term.russian], "\(entry.place) → \(entry.russianText); the glossary says «\(term.russian)»")
        }
    }
}

@Test func retiredWordingsStayRetired() throws {
    for entry in try Catalogs.entries() where !entry.isSearchTerm {
        let words = Terms.words(entry.russianText)
        for retired in Terms.retired {
            #expect(!words.contains(retired.pattern), "\(entry.place) → \(entry.russianText); use \(retired.use)")
        }
    }
}

/// «macOS» is feminine in every catalog («macOS сама выбрала», «не передала»).
@Test func macOSIsFeminine() throws {
    for entry in try Catalogs.entries() {
        var words = Terms.words(entry.russianText).split(separator: " ").map(String.init)[...]
        while let index = words.firstIndex(of: "macos") {
            words = words[(index + 1)...]
            let verb = words.first == "не" ? words.dropFirst().first : words.first
            if let verb { #expect(!(verb.count > 2 && verb.hasSuffix("л")), "\(entry.place) → \(entry.russianText)") }
        }
    }
}

@Test func systemSettingsAreQuotedByName() throws {
    for entry in try Catalogs.entries() {
        for (english, russian) in Terms.systemSettings where entry.english.contains(english) {
            #expect(entry.russian.allSatisfy { $0.contains("«\(russian)»") }, "\(entry.place) → \(entry.russianText)")
        }
    }
}

/// A label followed by a picker or a group of switches stands on its own; the case lives in the values (C-SET-1).
@Test func russianTextNeverEndsInAPreposition() throws {
    for entry in try Catalogs.entries() where !Terms.numericValueLabels.contains(entry.place) {
        for form in entry.russian {
            let last = Terms.words(form).split(separator: " ").last.map(String.init) ?? ""
            #expect(!Terms.prepositions.contains(last), "\(entry.place) → \(form)")
        }
    }
}

/// Show-switches say «Показывать …» in every pane.
@Test func showSwitchesSayShow() throws {
    for entry in try Catalogs.entries() where entry.english.hasPrefix("Show ") && entry.comment.contains("toggle") {
        #expect(entry.russianText.localizedCaseInsensitiveContains("показывать"), "\(entry.place) → \(entry.russianText)")
    }
}

/// Apple's Music app is quoted («Музыка»), unlike the word "music".
@Test func theMusicAppIsQuoted() throws {
    for entry in try Catalogs.entries() {
        let namesTheApp = entry.english.ranges(of: "Music").contains { range in
            range.lowerBound != entry.english.startIndex
                && (range.upperBound == entry.english.endIndex || !entry.english[range.upperBound].isLetter)
        }
        if namesTheApp { #expect(entry.russianText.contains("«Музык"), "\(entry.place) → \(entry.russianText)") }
    }
}

// MARK: - Settings rows in Russian (compiled catalog)

private func russianBundle() throws -> Bundle {
    let path = try #require(Bundle.module.path(forResource: "ru", ofType: "lproj"))
    return try #require(Bundle(path: path))
}

/// General ▸ «Где показывать: На встроенном дисплее» — the values carry the case, the label ends in no preposition.
@Test func showOnReadsAsASentenceInRussian() throws {
    let russian = try russianBundle()
    func ru(_ key: String) -> String { russian.localizedString(forKey: key, value: "\u{0}", table: "Localizable") }
    #expect(ru("Show on") == "Где показывать")
    for key in ["Built-in display", "Display with the pointer", "All displays", "Chosen displays"] {
        #expect(ru(key).hasPrefix("На "), "\(key) → \(ru(key))")
    }
    #expect(ru("Fold away after") == "Сворачивать при бездействии")
    #expect(ru("Never") == "Никогда")
}

/// A zero timeout is "Never", not a generic "Off" that a label such as "Fold away after" would have to bend.
@Test func zeroTimeoutsSayNever() {
    let en = Locale(identifier: "en_US")
    #expect(SettingsFormat.timeout(0, locale: en) == SettingsFormat.neverTitle)
    #expect(SettingsFormat.timeout(-1, locale: en) == SettingsFormat.neverTitle)
    #expect(SettingsFormat.timeout(10, locale: en) == SettingsFormat.seconds(10, locale: en))
}
