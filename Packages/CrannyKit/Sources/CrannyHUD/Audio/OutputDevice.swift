// CrannyHUD/Audio/OutputDevice.swift — which glyph stands for the default output device (DESIGN.md §10:
// "When the output device changes, the glyph becomes the device glyph with one .bounce"). Pure mapping.
//
// Symbols come from DESIGN.md §14.1 only. The restricted `airpods*` / `beats.headphones` glyphs are used only
// when the device says it is that product (its name, which macOS sets from the product unless renamed).
import CoreAudio
import Foundation

nonisolated struct OutputDevice: Sendable, Equatable {
    /// CoreAudio object ID (changes when a device reconnects; only used to detect a change).
    var id: UInt32
    var name: String
    /// `kAudioDevicePropertyTransportType`.
    var transport: UInt32?

    /// The HUD glyph for this device, or nil to keep the speaker (built-in speakers, unknown transports).
    var glyph: String? {
        guard let transport else { return nil }
        return switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            Self.headphonesGlyph(named: name)
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            "display"
        case kAudioDeviceTransportTypeAirPlay:
            "airplayaudio"
        case kAudioDeviceTransportTypeUSB:
            name.localizedCaseInsensitiveContains("headphone") || name.localizedCaseInsensitiveContains("headset")
                ? "headphones" : nil
        default:
            nil
        }
    }

    private static func headphonesGlyph(named name: String) -> String {
        if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
        if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
        if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
        if name.localizedCaseInsensitiveContains("Beats") { return "beats.headphones" }
        return "headphones"
    }
}
