// CrannyMedia/Health/AudioOutputMonitor.swift — "is any other app playing sound?" from Core Audio's process
// objects (macOS 14+, no permission, R2 §5.4), for the blocked-bridge heuristic and "Test Media Detection".
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
            var address = AudioHAL.address(kAudioHardwarePropertyProcessObjectList)
            if AudioObjectAddPropertyListenerBlock(AudioHAL.system, &address, queue, block) == noErr {
                listListener = block
            }
            processesChanged()
        }
    }

    func stop() {
        queue.async { [self] in
            if let block = listListener {
                var address = AudioHAL.address(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioHAL.system, &address, queue, block)
            }
            listListener = nil
            for (process, block) in listeners {
                var address = AudioHAL.address(kAudioProcessPropertyIsRunningOutput)
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
            var address = AudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
            listeners[process] = nil
        }
        for process in current where listeners[process] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.publish() }
            var address = AudioHAL.address(kAudioProcessPropertyIsRunningOutput)
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

    // MARK: Core Audio reads (Core's `AudioHAL`)

    private static func processObjects() -> [AudioObjectID] {
        AudioHAL.objectIDs(kAudioHardwarePropertyProcessObjectList)
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        (AudioHAL.uint32(process, AudioHAL.address(kAudioProcessPropertyIsRunningOutput)) ?? 0) != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t {
        AudioHAL.int32(process, AudioHAL.address(kAudioProcessPropertyPID)) ?? -1
    }
}
