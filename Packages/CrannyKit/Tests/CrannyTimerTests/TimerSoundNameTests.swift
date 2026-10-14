import CrannyCore
import Foundation
import Testing
@testable import CrannyTimer

// The sound picker stores file names ("Glass", what `NSSound(named:)` plays) but shows the names System Settings ▸
// Sound uses since macOS 14 ("Crystal" / «Кристалл»), in that pane's order.

@Suite struct TimerSoundNameTests {
    /// File name → (System Settings English name, its Russian name), from macOS's Sound settings (AlertSounds.loctable).
    static let systemSettingsNames: [String: (en: String, ru: String)] = [
        "Basso": ("Mezzo", "Меццо"), "Blow": ("Breeze", "Бриз"), "Bottle": ("Pebble", "Галька"),
        "Frog": ("Jump", "Пружина"), "Funk": ("Funky", "Фанк"), "Glass": ("Crystal", "Кристалл"),
        "Hero": ("Heroine", "Героиня"), "Morse": ("Pong", "Понг"), "Ping": ("Sonar", "Сонар"),
        "Pop": ("Bubble", "Пузырьки"), "Purr": ("Pluck", "Щипок"), "Sosumi": ("Sonumi", "Сонуми"),
        "Submarine": ("Submerge", "Погружение"), "Tink": ("Boop", "Капля"),
    ]

    @Test func storedValuesStayTheFileNames() {
        #expect(Set(TimerSettings.systemSounds) == Set(Self.systemSettingsNames.keys))
        #expect(TimerSettings.sound.defaultValue == "Glass")
        for name in TimerSettings.systemSounds {                       // what `NSSound(named:)` resolves
            #expect(FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(name).aiff"), "\(name)")
        }
    }

    /// Each sound shows its System Settings name, in whatever language this process resolves the catalog to.
    @Test func everySoundShowsItsSystemSettingsName() {
        for (file, names) in Self.systemSettingsNames {
            let shown = TimerCopy.soundName(file)
            #expect(shown == Bundle.module.localizedString(forKey: names.en, value: nil, table: "Localizable"), "\(file)")
            #expect(shown != file, "\(file) is shown under its file name")
        }
        #expect(TimerCopy.soundName("Custom") == "Custom")              // not a system sound: shown as stored
    }

    @Test func russianNamesAreApples() throws {
        let path = try #require(Bundle.module.path(forResource: "ru", ofType: "lproj"))
        let russian = try #require(Bundle(path: path))
        for (file, names) in Self.systemSettingsNames {
            #expect(russian.localizedString(forKey: names.en, value: "\u{0}", table: "Localizable") == names.ru, "\(file)")
        }
    }

    @Test func choicesAreSortedByShownName() {
        let english = TimerOptionsView.soundChoices { Self.systemSettingsNames[$0]?.en ?? $0 }
        #expect(english.map(\.name) == ["Boop", "Breeze", "Bubble", "Crystal", "Funky", "Heroine", "Jump", "Mezzo",
                                        "Pebble", "Pluck", "Pong", "Sonar", "Sonumi", "Submerge"])
        #expect(english.first?.fileName == "Tink" && english.last?.fileName == "Submarine")
        let russian = TimerOptionsView.soundChoices { Self.systemSettingsNames[$0]?.ru ?? $0 }
        #expect(russian.map(\.name) == ["Бриз", "Галька", "Героиня", "Капля", "Кристалл", "Меццо", "Погружение",
                                        "Понг", "Пружина", "Пузырьки", "Сонар", "Сонуми", "Фанк", "Щипок"])
        #expect(Set(russian.map(\.fileName)) == Set(TimerSettings.systemSounds))
        #expect(TimerOptionsView.soundChoices().count == TimerSettings.systemSounds.count)
    }

    /// When this Mac has the Sound settings table, the catalog still matches what System Settings shows.
    @Test func matchesThisMacsSoundSettings() throws {
        let url = URL(filePath: "/System/Library/ExtensionKit/Extensions/Sound.appex/Contents/Resources/AlertSounds.loctable")
        guard let data = try? Data(contentsOf: url) else { return }                  // another macOS layout: nothing to compare
        let table = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let english = try #require(table["en"] as? [String: String])         // also holds a non-language "LocProvenance"
        let russian = try #require(table["ru"] as? [String: String])
        for (file, names) in Self.systemSettingsNames {
            #expect(english[file] == names.en, "\(file)")
            #expect(russian[file] == names.ru, "\(file)")
        }
    }
}
