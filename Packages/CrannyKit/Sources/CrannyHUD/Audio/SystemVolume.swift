// CrannyHUD/Audio/SystemVolume.swift — the default output's volume and mute through public CoreAudio
// (R3 §1.5, ARCHITECTURE.md §7.1). Called on the key tap's thread: CoreAudio property calls are thread-safe.
// Tests use fakes of the `SystemVolume` protocol; nothing in the test suite touches the real volume.
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
    func setLevel(_ level: Double) -> Bool
    func setMuted(_ muted: Bool) -> Bool
}

/// The real thing: `kAudioHardwarePropertyDefaultOutputDevice` → `VirtualMainVolume` / `kAudioDevicePropertyMute`.
nonisolated struct CoreAudioVolume: SystemVolume {
    init() {}

    func readState() -> VolumeState? {
        guard let device = AudioHAL.defaultOutputDevice(), AudioHAL.isSettable(device, volumeAddress),
              let level = AudioHAL.float32(device, volumeAddress) else { return nil }
        let muted = AudioHAL.uint32(device, muteAddress).map { $0 != 0 } ?? false
        return VolumeState(level: Double(level), isMuted: muted, canMute: AudioHAL.isSettable(device, muteAddress),
                           deviceID: device)
    }

    func setLevel(_ level: Double) -> Bool {
        guard let device = AudioHAL.defaultOutputDevice() else { return false }
        return AudioHAL.setFloat32(Float32(min(max(level, 0), 1)), on: device, volumeAddress)
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard let device = AudioHAL.defaultOutputDevice() else { return false }
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
