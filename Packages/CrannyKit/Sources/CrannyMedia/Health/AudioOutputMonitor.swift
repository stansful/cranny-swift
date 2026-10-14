// CrannyMedia/Health/AudioOutputMonitor.swift — "is any other app playing sound?" from Core Audio's process
// objects (macOS 14+, no permission, R2 §5.4), for the blocked-bridge heuristic and "Test media detection".
// Event-driven: listeners on the process list and on each process's `IsRunningOutput`; no polling.
//
// Threading: listener blocks run on `queue`, where the listener table lives; `onChange` is called there too.
import CoreAudio
import CrannyCore
import Darwin
import Foundation

nonisolated final class AudioOutputMonitor: @unchecked Sendable {   // `listeners`/`lastValue` are confined to `queue`
    private let queue = DispatchQueue(label: "app.cranny.media.output-monitor", qos: .utility)
    private let onChange: @Sendable (Bool) -> Void
    private var listListener: AudioObjectPropertyListenerBlock?
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var lastValue: Bool?

    init(onChange: @escaping @Sendable (Bool) -> Void) { self.onChange = onChange }

    func start() {
        queue.async { [self] in
            guard listListener == nil else { return }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processesChanged() }
            var address = Self.propertyAddress(kAudioHardwarePropertyProcessObjectList)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
                listListener = block
            }
            processesChanged()
        }
    }

    func stop() {
        queue.async { [self] in
            if let block = listListener {
                var address = Self.propertyAddress(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            }
            listListener = nil
            for (process, block) in listeners {
                var address = Self.propertyAddress(kAudioProcessPropertyIsRunningOutput)
                AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
            }
            listeners.removeAll()
            lastValue = nil
        }
    }

    /// One-off answer (Settings ▸ Media ▸ Test media detection). Cheap property reads.
    static func isOtherProcessRunningOutput() -> Bool {
        processObjects().contains { isRunningOutput($0) && pid(of: $0) != getpid() }
    }

    // MARK: Queue-confined

    private func processesChanged() {
        let current = Set(Self.processObjects())
        for (process, block) in listeners where !current.contains(process) {
            var address = Self.propertyAddress(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
            listeners[process] = nil
        }
        for process in current where listeners[process] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.publish() }
            var address = Self.propertyAddress(kAudioProcessPropertyIsRunningOutput)
            if AudioObjectAddPropertyListenerBlock(process, &address, queue, block) == noErr { listeners[process] = block }
        }
        publish()
    }

    private func publish() {
        let value = Self.isOtherProcessRunningOutput()
        guard value != lastValue else { return }
        lastValue = value
        onChange(value)
    }

    // MARK: Core Audio reads

    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t {
        var address = propertyAddress(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr ? value : -1
    }
}
