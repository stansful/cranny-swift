// CrannyCore/Platform/AudioHAL.swift
// Typed, memory-safe reads of Core Audio's hardware objects (the HAL), written once: the HUD (volume, mute, output
// glyph), Media (output menu, the "other app is playing" monitor) and System Activities (Bluetooth outputs) keep only
// their own policy. Core Audio property calls are thread-safe; nothing here touches the main actor.
import CoreAudio
import Foundation

/// Core Audio HAL property access. Every read returns nil (or empty) on any error; nothing here prompts or changes
/// state except the explicit setters.
public nonisolated enum AudioHAL {
    /// The HAL's system object (device lists, the default devices, the process list).
    public static let system = AudioObjectID(kAudioObjectSystemObject)

    /// A property address on the main element. Device properties such as volume and mute need
    /// `kAudioDevicePropertyScopeOutput`; object-wide ones (name, transport, lists) use the global scope.
    public static func address(_ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// `kAudioHardwarePropertyDefaultOutputDevice` on the system object (also what listeners watch).
    public static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        address(kAudioHardwarePropertyDefaultOutputDevice)
    }

    // MARK: Reading

    /// An array of object IDs (`kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyProcessObjectList`), in Core
    /// Audio's order.
    public static func objectIDs(_ selector: AudioObjectPropertySelector, of object: AudioObjectID = system) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// A `UInt32` property (mute, transport type, "is running output"), nil if absent or unreadable.
    public static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        scalar(object, address, initial: UInt32(0))
    }

    /// An `Int32` property (`kAudioProcessPropertyPID`), nil if absent or unreadable.
    public static func int32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Int32? {
        scalar(object, address, initial: Int32(0))
    }

    /// A `Float32` property (`VirtualMainVolume`), nil if absent or unreadable.
    public static func float32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        scalar(object, address, initial: Float32(0))
    }

    /// A CFString property (`kAudioObjectPropertyName`, `kAudioDevicePropertyDeviceUID`), nil if absent, unreadable
    /// or empty. The HAL returns the string retained: it is released exactly once here.
    public static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    /// Whether the property exists on the object and can be set (a device's volume or mute).
    public static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    // MARK: Devices

    /// Every audio device, in Core Audio's order.
    public static func devices() -> [AudioObjectID] { objectIDs(kAudioHardwarePropertyDevices) }

    /// The current default output device, nil if there is none.
    public static func defaultOutputDevice() -> AudioObjectID? {
        uint32(system, defaultOutputDeviceAddress).map { AudioObjectID($0) }.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    /// Whether the device has at least one output stream (speakers, headphones, not a microphone).
    public static func hasOutputStreams(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// The device's name (`kAudioObjectPropertyName`).
    public static func name(_ device: AudioObjectID) -> String? { string(device, address(kAudioObjectPropertyName)) }

    /// `kAudioDevicePropertyTransportType` ('blue', 'blea', 'hdmi', 'bltn', …).
    public static func transportType(_ device: AudioObjectID) -> UInt32? {
        uint32(device, address(kAudioDevicePropertyTransportType))
    }

    // MARK: Writing (only on the user's explicit action)

    /// Sets a `Float32` property; true on success.
    @discardableResult
    public static func setFloat32(_ value: Float32, on object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var value = value, address = address
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// Sets a `UInt32` property; true on success.
    @discardableResult
    public static func setUInt32(_ value: UInt32, on object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var value = value, address = address
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Makes `device` the system's default output (the user picked it in a menu). Returns the HAL status.
    @discardableResult
    public static func setDefaultOutputDevice(_ device: AudioObjectID) -> OSStatus {
        var value = device, address = defaultOutputDeviceAddress
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    // MARK: Private

    private static func scalar<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr && size == UInt32(MemoryLayout<T>.size) ? value : nil
    }
}
