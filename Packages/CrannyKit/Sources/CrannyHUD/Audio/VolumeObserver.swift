// CrannyHUD/Audio/VolumeObserver.swift — keeps the visible volume HUD current and notices output-device
// changes (ARCHITECTURE.md §7.1, R3 §1.5). Passive CoreAudio listeners: event-driven, no polling, no permission.
//
// Thread: every listener block and all mutable state run on one private serial queue; observations reach the
// main actor through `onChange` (the controller hops with `Task { @MainActor in … }`). CoreAudio fires several
// callbacks per change (4 seen in R3), so they are coalesced over 15 ms. The level listeners are re-attached
// when the default output device changes. It runs only while Cranny replaces the system HUD.
import AudioToolbox
import CoreAudio
import Foundation

/// What the observer reports. `deviceChanged` is set when the default output switched to another device.
nonisolated struct VolumeObservation: Sendable, Equatable {
    /// nil when the device has no readable volume (HDMI / DisplayPort sinks).
    var level: Double?
    var isMuted: Bool
    var device: OutputDevice
    var deviceChanged: Bool
}

/// Something that reports default-output changes (the real CoreAudio observer, or a test double).
nonisolated protocol VolumeObserving: AnyObject, Sendable {
    func start(onChange: @escaping @Sendable (VolumeObservation) -> Void)
    func stop()
}

nonisolated final class VolumeObserver: VolumeObserving, @unchecked Sendable {
    // @unchecked: every stored var below is touched only on `queue`.
    private let queue = DispatchQueue(label: "app.cranny.hud.volume-observer")
    private var onChange: (@Sendable (VolumeObservation) -> Void)?
    private var device: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var levelListener: AudioObjectPropertyListenerBlock?
    private var pending = false
    private var deviceChanged = false

    init() {}

    func start(onChange: @escaping @Sendable (VolumeObservation) -> Void) {
        queue.async { [self] in
            guard self.onChange == nil else { return }
            self.onChange = onChange
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice(changed: true) }
            defaultDeviceListener = listener
            var address = AudioOutput.defaultDeviceAddress
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            attachToDefaultDevice(changed: false)
        }
    }

    func stop() {
        queue.async { [self] in
            guard onChange != nil else { return }
            detachLevelListeners()
            if let listener = defaultDeviceListener {
                var address = AudioOutput.defaultDeviceAddress
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            }
            defaultDeviceListener = nil
            onChange = nil
            device = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: On `queue`

    private static let levelSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    private func attachToDefaultDevice(changed: Bool) {
        guard onChange != nil else { return }
        detachLevelListeners()
        guard let next = AudioOutput.defaultDevice() else { return }
        if changed && next != device { deviceChanged = true }
        device = next
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.coalesce() }
        levelListener = listener
        for selector in Self.levelSelectors {
            var address = AudioOutput.address(selector)
            AudioObjectAddPropertyListenerBlock(next, &address, queue, listener)
        }
        if changed { coalesce() }
    }

    private func detachLevelListeners() {
        guard device != kAudioObjectUnknown, let listener = levelListener else { return }
        for selector in Self.levelSelectors {
            var address = AudioOutput.address(selector)
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, listener)
        }
        levelListener = nil
    }

    private func coalesce() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + .milliseconds(15)) { [self] in
            pending = false
            report()
        }
    }

    private func report() {
        guard let onChange, device != kAudioObjectUnknown else { return }
        let volume = AudioOutput.float(device, AudioOutput.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
        let muted = AudioOutput.uint32(device, AudioOutput.address(kAudioDevicePropertyMute)).map { $0 != 0 } ?? false
        let info = OutputDevice(id: device, name: AudioOutput.name(device) ?? "", transport: AudioOutput.transportType(device))
        let changed = deviceChanged
        deviceChanged = false
        onChange(VolumeObservation(level: volume.map(Double.init), isMuted: muted, device: info, deviceChanged: changed))
    }
}
