// CrannyHUD/Audio/SystemVolume.swift — the default output's volume and mute through public CoreAudio
// (R3 §1.5, ARCHITECTURE.md §7.1). Called on the key tap's thread: CoreAudio property calls are thread-safe.
// Tests use fakes of the `SystemVolume` protocol; nothing in the test suite touches the real volume.
//
// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` is declared in AudioToolbox, not CoreAudio.
// Output scope, main element. Changing the volume through CoreAudio never shows the system HUD.
import AudioToolbox
import CoreAudio
import Foundation

/// The default output device as the HUD sees it.
nonisolated struct VolumeState: Sendable, Equatable {
    /// 0…1 (`VirtualMainVolume`).
    var level: Double
    var isMuted: Bool
    /// The device has a settable mute (most do; some HDMI sinks don't).
    var canMute: Bool
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
        guard let device = AudioOutput.defaultDevice(), AudioOutput.isSettable(device, volumeAddress),
              let level = AudioOutput.float(device, volumeAddress) else { return nil }
        let muted = AudioOutput.uint32(device, muteAddress).map { $0 != 0 } ?? false
        return VolumeState(level: Double(level), isMuted: muted, canMute: AudioOutput.isSettable(device, muteAddress))
    }

    func setLevel(_ level: Double) -> Bool {
        guard let device = AudioOutput.defaultDevice() else { return false }
        var value = Float32(min(max(level, 0), 1))
        var address = volumeAddress
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard let device = AudioOutput.defaultDevice() else { return false }
        var value: UInt32 = muted ? 1 : 0
        var address = muteAddress
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private var volumeAddress: AudioObjectPropertyAddress { AudioOutput.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) }
    private var muteAddress: AudioObjectPropertyAddress { AudioOutput.address(kAudioDevicePropertyMute) }
}

/// Thin, typed wrappers over the CoreAudio property calls the HUD uses.
nonisolated enum AudioOutput {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static var defaultDeviceAddress: AudioObjectPropertyAddress {
        address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    }

    static func defaultDevice() -> AudioObjectID? {
        var address = defaultDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func isSettable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func float(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func uint32(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// `kAudioObjectPropertyName` of a device (for the output-device glyph), nil if it has none.
    static func name(_ device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    /// `kAudioDevicePropertyTransportType` ('blue', 'hdmi', 'bltn', …), nil if unknown.
    static func transportType(_ device: AudioObjectID) -> UInt32? {
        uint32(device, address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal))
    }
}
