// CrannySystemActivities/Accessories/AudioDeviceWatcher.swift — "headphones connected", permission-free:
// Core Audio's device list, filtered to Bluetooth outputs (transport 'blue' / 'blea') [VERIFIED R3 §3].
//
// Threading: confined to `queue`. The HAL calls the device-list listener there, every HAL read happens
// there, and results leave as Sendable values through `onChange` (the caller hops to the main actor).
import AudioToolbox
import CoreAudio
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.bluetooth)

/// A Bluetooth audio output that is connected right now.
nonisolated struct AudioOutputDevice: Equatable, Sendable, Identifiable {
    /// `kAudioDevicePropertyDeviceUID`: stable while connected (contains the device address: never logged).
    var id: String
    var name: String
}

nonisolated final class AudioDeviceWatcher: @unchecked Sendable {   // confined to `queue` (see the top)
    private let queue = DispatchQueue(label: "app.cranny.system.audio-devices", qos: .utility)
    /// Called on `queue` with a report number (increasing, so the receiver can drop reports that arrive late).
    private let onChange: @Sendable (Int, [AudioOutputDevice]) -> Void
    private var listener: AudioObjectPropertyListenerBlock?
    private var sequence = 0

    init(onChange: @escaping @Sendable (Int, [AudioOutputDevice]) -> Void) { self.onChange = onChange }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            var address = Self.devicesAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            if status == noErr { listener = block } else { log.error("Core Audio device listener failed: \(status, privacy: .public)") }
            report()
        }
    }

    func stop() {
        queue.async { [self] in
            guard let listener else { return }
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            self.listener = nil
        }
    }

    private func report() {
        sequence += 1
        onChange(sequence, Self.bluetoothOutputs())
    }

    // MARK: HAL reads

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Connected Bluetooth devices with at least one output stream (headphones, earbuds, speakers).
    static func bluetoothOutputs() -> [AudioOutputDevice] {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        var seenNames = Set<String>()
        return ids.compactMap { id -> AudioOutputDevice? in
            let transport = uint32(id, kAudioDevicePropertyTransportType)
            guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  hasOutput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            // A headset can publish two devices with one name (A2DP and hands-free): keep one.
            guard seenNames.insert(name).inserted else { return nil }
            return AudioOutputDevice(id: uid, name: name)
        }
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}
