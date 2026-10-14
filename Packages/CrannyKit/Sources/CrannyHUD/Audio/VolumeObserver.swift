// CrannyHUD/Audio/VolumeObserver.swift — keeps the visible volume HUD current and notices output-device
// changes (ARCHITECTURE.md §7.1, R3 §1.5). Passive CoreAudio listeners: event-driven, no polling, no permission.
//
// Thread: every listener block and all mutable state run on one private serial queue (utility: the results only
// update a visible HUD); observations reach the main actor through `onChange` (the controller hops with
// `Task { @MainActor in … }`). CoreAudio fires several callbacks per change (4 seen in R3), so they are coalesced
// over 15 ms. It runs only while Cranny replaces the system HUD.
//
// Energy: the default-device listener stays for the observer's life (a device change shows its glyph on the next
// volume HUD). The level and mute listeners are attached only while the controller follows the level
// (`setFollowsLevel`: a volume HUD is on screen, the only thing a level change updates), and move with the
// default device. The device's name and transport are read once per device, not per report.
import AudioToolbox
import CoreAudio
import CrannyCore
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
    /// true: also report level and mute changes of the default output (while a volume HUD is on screen);
    /// false (the start state): report only default-device changes.
    func setFollowsLevel(_ on: Bool)
    func stop()
}

nonisolated final class VolumeObserver: VolumeObserving, @unchecked Sendable {
    // @unchecked: every stored var below is touched only on `queue`.
    private let queue = DispatchQueue(label: "app.cranny.hud.volume-observer", qos: .utility)
    private var onChange: (@Sendable (VolumeObservation) -> Void)?
    private var device: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    /// `device`'s name and transport, read when it became the default (they only matter for a device change).
    private var deviceInfo: OutputDevice?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var levelListener: AudioObjectPropertyListenerBlock?
    /// The level and mute listeners should be attached (`setFollowsLevel`).
    private var followsLevel = false
    private var pending = false
    private var deviceChanged = false

    init() {}

    func start(onChange: @escaping @Sendable (VolumeObservation) -> Void) {
        queue.async { [self] in
            guard self.onChange == nil else { return }
            self.onChange = onChange
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice(changed: true) }
            defaultDeviceListener = listener
            var address = AudioHAL.defaultOutputDeviceAddress
            AudioObjectAddPropertyListenerBlock(AudioHAL.system, &address, queue, listener)
            attachToDefaultDevice(changed: false)
        }
    }

    func setFollowsLevel(_ on: Bool) {
        queue.async { [self] in
            guard on != followsLevel else { return }
            followsLevel = on
            guard onChange != nil else { return }                  // not started: `start` attaches if still wanted
            if on { attachLevelListeners() } else { detachLevelListeners() }
        }
    }

    func stop() {
        queue.async { [self] in
            followsLevel = false
            guard onChange != nil else { return }
            detachLevelListeners()
            if let listener = defaultDeviceListener {
                var address = AudioHAL.defaultOutputDeviceAddress
                AudioObjectRemovePropertyListenerBlock(AudioHAL.system, &address, queue, listener)
            }
            defaultDeviceListener = nil
            onChange = nil
            device = AudioObjectID(kAudioObjectUnknown)
            deviceInfo = nil
        }
    }

    // MARK: On `queue`

    private static let levelSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    private func attachToDefaultDevice(changed: Bool) {
        guard onChange != nil else { return }
        detachLevelListeners()
        guard let next = AudioHAL.defaultOutputDevice() else { return }
        if changed && next != device { deviceChanged = true }
        device = next
        if followsLevel { attachLevelListeners() }
        if changed { coalesce() }
    }

    private func attachLevelListeners() {
        guard device != kAudioObjectUnknown, levelListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.coalesce() }
        levelListener = listener
        for selector in Self.levelSelectors {
            var address = AudioHAL.address(selector, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(device, &address, queue, listener)
        }
    }

    private func detachLevelListeners() {
        guard device != kAudioObjectUnknown, let listener = levelListener else { return }
        for selector in Self.levelSelectors {
            var address = AudioHAL.address(selector, scope: kAudioDevicePropertyScopeOutput)
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
        let volume = AudioHAL.float32(device, OutputLevelAddress.volume)
        let muted = AudioHAL.uint32(device, OutputLevelAddress.mute).map { $0 != 0 } ?? false
        let changed = deviceChanged
        deviceChanged = false
        let info: OutputDevice
        if !changed, let cached = deviceInfo, cached.id == device {
            info = cached
        } else {
            info = OutputDevice(id: device, name: AudioHAL.name(device) ?? "", transport: AudioHAL.transportType(device))
            deviceInfo = info
        }
        onChange(VolumeObservation(level: volume.map(Double.init), isMuted: muted, device: info, deviceChanged: changed))
    }
}
