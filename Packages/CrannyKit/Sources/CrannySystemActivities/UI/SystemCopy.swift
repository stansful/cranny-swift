// CrannySystemActivities/UI/SystemCopy.swift — every user-visible string of the module (en + ru catalog)
// and the number/duration formatting (FormatStyle only, never concatenation; ARCHITECTURE.md §8.7).
import Foundation

enum SystemCopy {
    /// The bundle every string comes from. Debug builds let the snapshot test pick a language's `.lproj`
    /// (the test runner itself is not localized, so `.module` always answers in English there).
    #if DEBUG
    static var bundle: Bundle { languageBundle ?? .module }
    private static var languageBundle: Bundle?

    /// Debug only: answer in `language` ("ru"), or the system's choice for nil.
    static func useLanguage(_ language: String?) {
        languageBundle = language.flatMap { Bundle.module.path(forResource: $0, ofType: "lproj") }.flatMap(Bundle.init(path:))
    }
    #else
    static var bundle: Bundle { .module }
    #endif

    // MARK: Values

    /// "82%" ("82 %" in Russian).
    static func percent(_ value: Int) -> String { value.formatted(.percent) }

    /// The same value without the locale's (no-break) space before "%", for the band when nothing else fits.
    static func tightPercent(_ value: Int) -> String {
        percent(value).filter { !$0.isWhitespace }
    }

    /// "1h 20m" in the peek, "1 hour, 20 minutes" for VoiceOver.
    static func duration(minutes: Int, spoken: Bool = false) -> String {
        Duration.seconds(Double(max(minutes, 1)) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: spoken ? .wide : .narrow))
    }

    /// Joins short phrases for VoiceOver ("Left 84%, Right 82% and Case 45%").
    static func list(_ parts: [String]) -> String { parts.formatted(.list(type: .and)) }

    // MARK: Activity names (Settings ▸ Live Activities)

    static var charging: String {
        String(localized: "Charging", bundle: bundle,
               comment: "Charging activity: peek title while the Mac charges; also its row name in Settings ▸ Live Activities")
    }
    static var lowBattery: String {
        String(localized: "Low battery", bundle: bundle,
               comment: "Low battery activity: peek title; also its row name in Settings ▸ Live Activities")
    }
    static var bluetoothDevices: String {
        String(localized: "Bluetooth devices", bundle: bundle,
               comment: "Settings ▸ Live Activities: row name of the activity shown when a Bluetooth accessory connects")
    }

    // MARK: Charging

    static var fullyCharged: String {
        String(localized: "Fully charged", bundle: bundle, comment: "Charging activity: peek title when the battery is full on power")
    }
    static var connectedToPower: String {
        String(localized: "Connected to power", bundle: bundle,
               comment: "Charging activity: peek subtitle when the battery is full and the power adapter is connected")
    }
    static var pluggedIn: String {
        String(localized: "Plugged in", bundle: bundle,
               comment: "Charging activity: peek title when power is connected but the battery does not charge")
    }
    static var notCharging: String {
        String(localized: "Not charging", bundle: bundle,
               comment: "Charging activity: peek subtitle when power is connected but the battery does not charge (charge limit, optimized charging)")
    }
    static var onBattery: String {
        String(localized: "On battery", bundle: bundle,
               comment: "Charging activity: peek title right after the power adapter was disconnected")
    }
    static var calculating: String {
        String(localized: "Calculating…", bundle: bundle,
               comment: "Battery activities: peek subtitle while macOS still estimates the remaining time")
    }
    static func untilFull(_ duration: String) -> String {
        String(localized: "\(duration) until full", bundle: bundle,
               comment: "Charging activity: peek subtitle; %@ is a short duration such as “1h 20m”")
    }
    static func timeLeft(_ duration: String) -> String {
        String(localized: "\(duration) left", bundle: bundle,
               comment: "Battery activities: time until the battery is empty; %@ is a short duration such as “3h 10m”")
    }

    // MARK: Low battery

    static func levelAndStatus(_ level: String, _ status: String) -> String {
        String(localized: "\(level) · \(status)", bundle: bundle,
               comment: "Low battery activity: peek subtitle; the first value is the battery level (“10%”), the second the time left or a status")
    }
    static var lowPowerModeButton: String {
        String(localized: "Low Power Mode…", bundle: bundle,
               comment: "Low battery activity: button that opens Battery settings (apps cannot switch Low Power Mode themselves)")
    }
    static var lowPowerModeIsOn: String {
        String(localized: "Low Power Mode is on", bundle: bundle,
               comment: "Low battery activity: peek subtitle when Low Power Mode is already on (the button to it is then hidden)")
    }
    static var batterySettings: String {
        String(localized: "Open Battery Settings", bundle: bundle,
               comment: "Low battery activity: VoiceOver action that opens Battery settings in System Settings")
    }

    // MARK: Bluetooth

    static var connected: String {
        String(localized: "Connected", bundle: bundle, comment: "Bluetooth activity: peek subtitle under the device name")
    }
    static func deviceConnected(_ name: String) -> String {
        String(localized: "\(name) connected", bundle: bundle,
               comment: "Bluetooth activity: VoiceOver label; %@ is the device name (Russian: “Подключено: …” avoids gender agreement)")
    }
    static var left: String { String(localized: "Left", bundle: bundle, comment: "Bluetooth activity: label of the left earbud's battery gauge") }
    static var right: String { String(localized: "Right", bundle: bundle, comment: "Bluetooth activity: label of the right earbud's battery gauge") }
    static var chargingCase: String {
        String(localized: "Case", bundle: bundle, comment: "Bluetooth activity: label of the charging case's battery gauge")
    }
    /// VoiceOver value of one battery ("Left 84%").
    static func part(_ part: AccessoryPart, _ level: String) -> String {
        switch part {
        case .left: String(localized: "Left \(level)", bundle: bundle,
                           comment: "Bluetooth activity: VoiceOver value of the left earbud's battery; %@ is a level such as “84%”")
        case .right: String(localized: "Right \(level)", bundle: bundle,
                            comment: "Bluetooth activity: VoiceOver value of the right earbud's battery; %@ is a level such as “84%”")
        case .chargingCase: String(localized: "Case \(level)", bundle: bundle,
                                   comment: "Bluetooth activity: VoiceOver value of the charging case's battery; %@ is a level such as “84%”")
        }
    }

    /// The gauge label under a battery ring.
    static func label(_ part: AccessoryPart) -> String {
        switch part {
        case .left: left
        case .right: right
        case .chargingCase: chargingCase
        }
    }
    static var batteryUnknown: String {
        String(localized: "Battery level unknown", bundle: bundle,
               comment: "Bluetooth activity: VoiceOver value when the device does not report its battery")
    }

    /// Generic device names, shown instead of the device's own (often personal) name in Demo mode.
    static func genericName(_ kind: AccessoryKind) -> String {
        switch kind {
        case .headphones: String(localized: "Headphones", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .earbuds: String(localized: "Earbuds", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .speaker: String(localized: "Speaker", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .keyboard: String(localized: "Keyboard", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .mouse: String(localized: "Mouse", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .trackpad: String(localized: "Trackpad", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .gameController: String(localized: "Game controller", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        case .other: String(localized: "Bluetooth device", bundle: bundle, comment: "Bluetooth activity: generic device name (Demo mode hides the real name)")
        }
    }

    // MARK: Settings ▸ Live Activities options

    static var firstWarning: String {
        String(localized: "First warning", bundle: bundle, comment: "Settings ▸ Live Activities ▸ Low battery: picker for the higher warning level")
    }
    static var finalWarning: String {
        String(localized: "Final warning", bundle: bundle, comment: "Settings ▸ Live Activities ▸ Low battery: picker for the lowest warning level")
    }
    static var finalWarningFootnote: String {
        String(localized: "Stays until you connect power.", bundle: bundle,
               comment: "Settings ▸ Live Activities ▸ Low battery: footnote under “Final warning”")
    }
    static var off: String {
        String(localized: "Off", bundle: bundle, comment: "Settings ▸ Live Activities ▸ Low battery: “First warning” picker value for no first warning")
    }
    static var showAllDevices: String {
        String(localized: "Show all Bluetooth devices", bundle: bundle, comment: "Settings ▸ Live Activities ▸ Bluetooth devices: toggle")
    }
    static var showAllDevicesFootnote: String {
        String(localized: "Also shows keyboards, mice and headphones from other makers. Needs Bluetooth access.", bundle: bundle,
               comment: "Settings ▸ Live Activities ▸ Bluetooth devices: footnote under the toggle")
    }
    static var bluetoothAccessOff: String {
        String(localized: "Bluetooth access is off for Cranny.", bundle: bundle,
               comment: "Settings ▸ Live Activities ▸ Bluetooth devices: shown when the option is on but access was denied")
    }
    static var openSystemSettings: String {
        String(localized: "Open System Settings", bundle: bundle,
               comment: "Settings ▸ Live Activities ▸ Bluetooth devices: button to the Bluetooth privacy settings")
    }
    static var bluetoothPermissionReason: String {
        String(localized: "Shows every Bluetooth device that connects. Headphones and Magic accessories work without it.", bundle: bundle,
               comment: "Permissions pane and onboarding: why Cranny may ask for Bluetooth access")
    }
}
