// CrannyMedia/Audio/OutputDevices.swift — the Mac's audio outputs for the widget's ⌁ route menu (DESIGN.md §7.1).
// Reading the list needs no permission; switching sets the system default output device, and only on the user's
// choice in the menu. Read when the menu is built (no listeners, no polling).
import CoreAudio
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

nonisolated struct OutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let name: String
}

nonisolated enum OutputDevices {
    /// Every device with output streams, in Core Audio's order.
    static func all() -> [OutputDevice] {
        AudioHAL.devices().filter(AudioHAL.hasOutputStreams).compactMap { id in
            AudioHAL.name(id).map { OutputDevice(id: id, name: $0) }
        }
    }

    static var defaultOutput: AudioObjectID? { AudioHAL.defaultOutputDevice() }

    /// The user picked a device in the ⌁ menu.
    static func setDefaultOutput(_ id: AudioObjectID) {
        let status = AudioHAL.setDefaultOutputDevice(id)
        if status != noErr { log.error("media: cannot switch the output device (\(status, privacy: .public))") }
    }
}
