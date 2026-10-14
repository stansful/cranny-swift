// CrannySystemActivities/Accessories/AudioDeviceWatcher.swift — "headphones connected", permission-free:
// Core Audio's device list, filtered to Bluetooth outputs (transport 'blue' / 'blea') [VERIFIED R3 §3].
//
// Threading: confined to `queue`. The HAL calls the device-list listener there, every HAL read happens
// there, and results leave as Sendable values through `onChange` (the caller hops to the main actor).
//
// Energy: one change fires several callbacks (wake from sleep, a headset publishing its A2DP and hands-free
// devices), so they are coalesced over 50 ms into one enumeration, and a list equal to the last one reported
// is not reported again (the tracker would find nothing new in it).
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
    /// A coalesced report is scheduled.
    private var pending = false
    /// The list reported last (nil before the baseline, which is always reported).
    private var last: [AudioOutputDevice]?

    /// One burst of device-list callbacks becomes one enumeration this long after its first callback.
    static let coalescing: DispatchTimeInterval = .milliseconds(50)

    init(onChange: @escaping @Sendable (Int, [AudioOutputDevice]) -> Void) { self.onChange = onChange }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            var address = Self.devicesAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.coalesce() }
            let status = AudioObjectAddPropertyListenerBlock(AudioHAL.system, &address, queue, block)
            if status == noErr { listener = block } else { log.error("Core Audio device listener failed: \(status, privacy: .public)") }
            report()
        }
    }

    func stop() {
        queue.async { [self] in
            last = nil
            guard let listener else { return }
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioHAL.system, &address, queue, listener)
            self.listener = nil
        }
    }

    private func coalesce() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + Self.coalescing) { [self] in
            pending = false
            guard listener != nil else { return }        // stopped meanwhile
            report()
        }
    }

    private func report() {
        let devices = Self.bluetoothOutputs()
        guard devices != last else { return }
        last = devices
        sequence += 1
        onChange(sequence, devices)
    }

    // MARK: HAL reads (Core's `AudioHAL`)

    private static var devicesAddress: AudioObjectPropertyAddress { AudioHAL.address(kAudioHardwarePropertyDevices) }

    /// Connected Bluetooth devices with at least one output stream (headphones, earbuds, speakers).
    static func bluetoothOutputs() -> [AudioOutputDevice] {
        var seenNames = Set<String>()
        return AudioHAL.devices().compactMap { id -> AudioOutputDevice? in
            let transport = AudioHAL.transportType(id)
            guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  AudioHAL.hasOutputStreams(id), let uid = AudioHAL.string(id, AudioHAL.address(kAudioDevicePropertyDeviceUID)),
                  let name = AudioHAL.name(id) else { return nil }
            // A headset can publish two devices with one name (A2DP and hands-free): keep one.
            guard seenNames.insert(name).inserted else { return nil }
            return AudioOutputDevice(id: uid, name: name)
        }
    }
}
