// CrannyHUD/Audio/SystemVolume.swift — the default output's volume and mute through public CoreAudio
// (R3 §1.5, ARCHITECTURE.md §7.1). Called on the key tap's thread: CoreAudio property calls are thread-safe.
// Tests use fakes of the `SystemVolume` protocol; nothing in the test suite touches the real volume.
//
// Each helper is a property call or two, and the tap waits for all of them, so a press reads only what it uses:
// within `MediaKeyHandler.recentVolumeWindow` it steps from the values Cranny applied and reads just the device
// and what it can set (`readState(includingLevels: false)`), and it writes to the device it read (`on:`), with
// no second default-device lookup.
//
// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` is declared in AudioToolbox, not CoreAudio.
// Output scope, main element. Changing the volume through CoreAudio never shows the system HUD.
import AudioToolbox
import CoreAudio
import CrannyCore
import Foundation

/// The default output device as the HUD sees it.
nonisolated struct VolumeState: Sendable, Equatable {
    /// 0…1 (`VirtualMainVolume`).
    var level: Double
    var isMuted: Bool
    /// The device has a settable mute (most do; some HDMI sinks don't).
    var canMute: Bool
    /// The CoreAudio device the values belong to (nil = unknown).
    var deviceID: UInt32? = nil
}

/// Volume and mute of the current default output. `readState()` is nil when the device's volume cannot be set
/// (HDMI/DisplayPort sinks): the key then goes to macOS, which shows its "not adjustable" HUD.
nonisolated protocol SystemVolume: Sendable {
    func readState() -> VolumeState?
    /// `includingLevels: false` reads only the device and whether it can set its volume and mute (nil exactly
    /// like `readState()` for an unsettable volume); `level` and `isMuted` are then 0 and false, not readings.
    func readState(includingLevels: Bool) -> VolumeState?
    func setLevel(_ level: Double) -> Bool
    func setMuted(_ muted: Bool) -> Bool
    /// Writes to `device` (a `VolumeState.deviceID` just read); nil = the current default output.
    func setLevel(_ level: Double, on device: UInt32?) -> Bool
    func setMuted(_ muted: Bool, on device: UInt32?) -> Bool
}

nonisolated extension SystemVolume {
    func readState(includingLevels: Bool) -> VolumeState? { readState() }
    func setLevel(_ level: Double, on device: UInt32?) -> Bool { setLevel(level) }
    func setMuted(_ muted: Bool, on device: UInt32?) -> Bool { setMuted(muted) }
}

/// The real thing: `kAudioHardwarePropertyDefaultOutputDevice` → `VirtualMainVolume` / `kAudioDevicePropertyMute`.
nonisolated struct CoreAudioVolume: SystemVolume {
    init() {}

    func readState() -> VolumeState? { readState(includingLevels: true) }

    func readState(includingLevels: Bool) -> VolumeState? {
        guard let device = AudioHAL.defaultOutputDevice(), AudioHAL.isSettable(device, volumeAddress) else { return nil }
        var state = VolumeState(level: 0, isMuted: false, canMute: AudioHAL.isSettable(device, muteAddress), deviceID: device)
        guard includingLevels else { return state }
        guard let level = AudioHAL.float32(device, volumeAddress) else { return nil }
        state.level = Double(level)
        state.isMuted = AudioHAL.uint32(device, muteAddress).map { $0 != 0 } ?? false
        return state
    }

    func setLevel(_ level: Double) -> Bool { setLevel(level, on: nil) }

    func setMuted(_ muted: Bool) -> Bool { setMuted(muted, on: nil) }

    func setLevel(_ level: Double, on device: UInt32?) -> Bool {
        guard let device = device ?? AudioHAL.defaultOutputDevice() else { return false }
        return AudioHAL.setFloat32(Float32(min(max(level, 0), 1)), on: device, volumeAddress)
    }

    func setMuted(_ muted: Bool, on device: UInt32?) -> Bool {
        guard let device = device ?? AudioHAL.defaultOutputDevice() else { return false }
        return AudioHAL.setUInt32(muted ? 1 : 0, on: device, muteAddress)
    }

    private var volumeAddress: AudioObjectPropertyAddress { OutputLevelAddress.volume }
    private var muteAddress: AudioObjectPropertyAddress { OutputLevelAddress.mute }
}

/// The default output's level properties (output scope, main element). Core's `AudioHAL` reads and writes them.
nonisolated enum OutputLevelAddress {
    static let volume = AudioHAL.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                         scope: kAudioDevicePropertyScopeOutput)
    static let mute = AudioHAL.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
}
