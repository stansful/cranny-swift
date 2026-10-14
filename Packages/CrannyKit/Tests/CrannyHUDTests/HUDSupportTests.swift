// Small pure rules: feedback sound, output-device glyphs, symbols, tints, copy, competing apps, QA arguments.
import AppKit
import CoreAudio
import CrannyCore
import Foundation
import Testing
@testable import CrannyHUD

@Suite struct FeedbackSoundTests {
    @Test func followsTheSystemSettingInvertedByShift() {
        #expect(FeedbackSound.shouldPlay(systemFeedback: true, shiftHeld: false, demoMode: false, muted: false))
        #expect(!FeedbackSound.shouldPlay(systemFeedback: true, shiftHeld: true, demoMode: false, muted: false))
        #expect(FeedbackSound.shouldPlay(systemFeedback: false, shiftHeld: true, demoMode: false, muted: false))
        #expect(!FeedbackSound.shouldPlay(systemFeedback: false, shiftHeld: false, demoMode: false, muted: false))
    }

    @Test func silentInDemoModeAndWhileMuted() {
        #expect(!FeedbackSound.shouldPlay(systemFeedback: true, shiftHeld: false, demoMode: true, muted: false))
        #expect(!FeedbackSound.shouldPlay(systemFeedback: true, shiftHeld: false, demoMode: false, muted: true))
    }

    @Test func readsTheGlobalDefault() throws {
        // A suite still searches the global domain (where macOS keeps the switch), so set both values explicitly.
        let defaults = try #require(UserDefaults(suiteName: "cranny.hud.tests.\(UUID().uuidString)"))
        defaults.set(1, forKey: FeedbackSound.feedbackDefaultsKey)
        #expect(FeedbackSound.systemFeedbackEnabled(defaults))
        defaults.set(0, forKey: FeedbackSound.feedbackDefaultsKey)
        #expect(!FeedbackSound.systemFeedbackEnabled(defaults))
    }
}

/// Every symbol DESIGN.md §14.1 allows the HUD (HUD, power and Devices rows, `display`, `airplayaudio`).
private let allowedSymbols: Set<String> = [
    "speaker.wave.3.fill", "speaker.slash.fill", "sun.max.fill", "sun.min.fill", "light.max", "light.min",
    "airpodspro", "airpodsmax", "airpods", "beats.headphones", "earbuds", "headphones", "display", "airplayaudio",
]

@Suite struct OutputDeviceTests {
    private func glyph(_ name: String, _ transport: UInt32?) -> String? {
        OutputDevice(id: 1, name: name, transport: transport).glyph
    }

    @Test func mapsTransportsAndProducts() {
        #expect(glyph("Stan’s AirPods Pro", kAudioDeviceTransportTypeBluetooth) == "airpodspro")
        #expect(glyph("AirPods Max", kAudioDeviceTransportTypeBluetooth) == "airpodsmax")
        #expect(glyph("AirPods", kAudioDeviceTransportTypeBluetoothLE) == "airpods")
        #expect(glyph("Beats Studio Pro", kAudioDeviceTransportTypeBluetooth) == "beats.headphones")
        #expect(glyph("WH-1000XM5", kAudioDeviceTransportTypeBluetooth) == "headphones")
        #expect(glyph("LG UltraFine", kAudioDeviceTransportTypeHDMI) == "display")
        #expect(glyph("Studio Display", kAudioDeviceTransportTypeDisplayPort) == "display")
        #expect(glyph("Living Room", kAudioDeviceTransportTypeAirPlay) == "airplayaudio")
        #expect(glyph("USB Headset", kAudioDeviceTransportTypeUSB) == "headphones")
        #expect(glyph("USB Audio DAC", kAudioDeviceTransportTypeUSB) == nil)
        #expect(glyph("MacBook Pro Speakers", kAudioDeviceTransportTypeBuiltIn) == nil)
        #expect(glyph("Unknown", nil) == nil)
    }

    @Test func glyphsAreAllowedAndExist() {
        let names = ["AirPods Pro", "AirPods Max", "AirPods", "Beats", "Other"]
        let transports = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeAirPlay,
                          kAudioDeviceTransportTypeUSB]
        for name in names {
            for transport in transports {
                guard let symbol = glyph(name + " Headphones", transport) else { continue }
                #expect(allowedSymbols.contains(symbol), "\(symbol) is not in DESIGN.md §14.1")
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) missing")
            }
        }
    }
}

@Suite struct HUDGlyphAndTintTests {
    @Test func symbolsPerKindAndLevel() {
        #expect(HUDKind.volume.symbol(level: 0.5, muted: false) == "speaker.wave.3.fill")
        #expect(HUDKind.volume.symbol(level: 0.5, muted: true) == "speaker.slash.fill")
        #expect(HUDKind.brightness.symbol(level: 0.25, muted: false) == "sun.min.fill")
        #expect(HUDKind.brightness.symbol(level: 0.75, muted: false) == "sun.max.fill")
        #expect(HUDKind.keyboardBacklight.symbol(level: 0, muted: false) == "light.min")
        #expect(HUDKind.keyboardBacklight.symbol(level: 0.25, muted: false) == "light.max")
        for kind in HUDKind.allCases {
            for level in [0.0, 0.75] {
                for muted in [false, true] {
                    let symbol = kind.symbol(level: level, muted: muted)
                    #expect(allowedSymbols.contains(symbol))
                    #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) missing")
                }
            }
        }
    }

    @Test func muteWinsOverTheDeviceGlyph() {
        var display = HUDDisplay(kind: .volume, level: 0.62, deviceGlyph: "airpodspro")
        #expect(display.symbolName == "airpodspro")
        #expect(display.symbolVariableValue == nil)
        display.isMuted = true
        #expect(display.symbolName == "speaker.slash.fill")
        #expect(display.symbolVariableValue == nil)
        display.deviceGlyph = nil
        display.isMuted = false
        #expect(display.symbolName == "speaker.wave.3.fill")
        #expect(display.symbolVariableValue == 0.62)
        #expect(HUDDisplay(kind: .brightness, level: 0.75).symbolName == "sun.max.fill")
    }

    @Test func onlyTheSpeakerFillsWithTheLevel() {
        #expect(HUDKind.volume.variableValue(level: 0.62, muted: false) == 0.62)
        #expect(HUDKind.volume.variableValue(level: 0.62, muted: true) == nil)
        #expect(HUDKind.brightness.variableValue(level: 0.62, muted: false) == nil)
        #expect(HUDKind.keyboardBacklight.variableValue(level: 0.62, muted: false) == nil)
    }

    @Test func tints() {
        for kind in HUDKind.allCases {
            #expect(HUDTint(.mono, kind: kind) == .white)
            #expect(HUDTint(.accent, kind: kind) == .accent)
        }
        #expect(HUDTint(.semantic, kind: .volume) == .accent)
        #expect(HUDTint(.semantic, kind: .brightness) == .caution)
        #expect(HUDTint(.semantic, kind: .keyboardBacklight) == .info)
        #expect(HUDTint.white.color(in: CrannyTheme()) == nil)       // LevelBar's default white fill
    }

    @Test func copyCarriesTheValue() {
        let display = HUDDisplay(kind: .volume, level: 0.62)
        #expect(HUDCopy.percentText(0.62).contains("62"))
        #expect(HUDCopy.accessibilityValue(display) == HUDCopy.percentText(0.62))
        #expect(HUDCopy.announcement(display).contains("62"))
        #expect(HUDCopy.announcement(display).hasPrefix(HUDKind.volume.title))
        var muted = display
        muted.isMuted = true
        #expect(!HUDCopy.accessibilityValue(muted).contains("62"))
        #expect(!HUDCopy.announcement(muted).contains("62"))
        #expect(HUDCopy.announcement(HUDDisplay(kind: .brightness, level: 0.25)).contains("25"))
        #expect(Set(HUDKind.allCases.map(\.title)).count == 3)
    }
}

@Suite struct CompetingHUDAppsTests {
    @Test func findsKnownAppsCaseInsensitively() {
        let running: [String?] = ["com.apple.finder", nil, "me.guillaumeb.MonitorControl", "com.rogueamoeba.SoundSource",
                                  "me.guillaumeb.MonitorControl"]
        #expect(CompetingHUDApps.running(in: running) == ["MonitorControl", "SoundSource"])
        #expect(CompetingHUDApps.running(in: ["com.apple.Safari"]).isEmpty)
    }
}

@Suite struct HUDQAHookTests {
    @Test func parsesArguments() throws {
        #expect(HUDQAHook.display(arguments: ["Cranny"]) == nil)
        #expect(HUDQAHook.display(arguments: ["Cranny", "--qa-hud"]) == nil)
        #expect(HUDQAHook.display(arguments: ["Cranny", "--qa-hud", "nonsense"]) == nil)
        #expect(HUDQAHook.display(arguments: ["--qa-hud", "volume"]) == HUDDisplay(kind: .volume, level: 0.62))
        #expect(HUDQAHook.display(arguments: ["--qa-hud", "brightness:0.3"]) == HUDDisplay(kind: .brightness, level: 0.3))
        let muted = try #require(HUDQAHook.display(arguments: ["--qa-hud", "muted:1.4", "--qa-hud-fine", "--qa-hud-device"]))
        #expect(muted.isMuted && muted.level == 1 && muted.showsFineTicks && muted.deviceGlyph == "headphones")
        #expect(HUDQAHook.display(arguments: ["--qa-hud", "keyboard"])?.kind == .keyboardBacklight)
    }
}
