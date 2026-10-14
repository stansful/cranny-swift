// CrannyMedia/Health/AudioOutputMonitor.swift — "is any other app playing sound?" from Core Audio's process
// objects (macOS 14+, no permission, R2 §5.4), for the blocked-bridge heuristic and "Test Media Detection".
// Event-driven: listeners on the process list and on each other process's `IsRunningOutput`; no polling. Kept
// incrementally: one process's event reads only that process, and a process-list change re-reads every process's
// state (which bounds any drift). Each process's PID is read once, when its object appears; Cranny's own objects
// get no listener, so its own sounds never wake this queue.
//
// Threading: listener blocks run on `queue`, where the listener table and the running set live; `onChange` is called
// there too.
import CoreAudio
import CrannyCore
import Darwin
import Foundation

/// Reports "another app is producing sound" to its `onChange` between `start` and `stop` (the current answer right
/// after `start`). `AudioOutputMonitor` in the app; tests use a fake that never touches Core Audio.
nonisolated protocol OutputMonitoring: AnyObject, Sendable {
    func start()
    func stop()
}

nonisolated final class AudioOutputMonitor: OutputMonitoring, @unchecked Sendable {   // every `var` is confined to `queue`
    private let queue = DispatchQueue(label: "app.cranny.media.output-monitor", qos: .utility)
    private let onChange: @Sendable (Bool) -> Void
    /// Between `start` and `stop`: a listener block that runs after `stop` changes nothing.
    private var isActive = false
    private var listListener: AudioObjectPropertyListenerBlock?
    /// Every other process's object (not Cranny's), and the `IsRunningOutput` listener of those that have one.
    private var others: Set<AudioObjectID> = []
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    /// Cranny's own process objects (their PID is known, so it is never read again).
    private var own: Set<AudioObjectID> = []
    /// The other processes that are producing sound.
    private var running: Set<AudioObjectID> = []
    private var lastValue: Bool?

    init(onChange: @escaping @Sendable (Bool) -> Void) { self.onChange = onChange }

    func start() {
        queue.async { [self] in
            guard !isActive else { return }
            isActive = true
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
            isActive = false
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
            others.removeAll()
            own.removeAll()
            running.removeAll()
            lastValue = nil
        }
    }

    /// One-off answer (Settings ▸ Media ▸ Test media detection, diagnostics). Cheap property reads.
    static func isOtherProcessRunningOutput() -> Bool {
        processObjects().contains { isRunningOutput($0) && pid(of: $0) != getpid() }
    }

    // MARK: Queue-confined

    /// The process list changed (or the monitor started): forget gone processes, find out who the new ones are and
    /// listen to the others, then re-read every other process's state.
    private func processesChanged() {
        guard isActive else { return }
        let current = Set(Self.processObjects())
        for (process, block) in listeners where !current.contains(process) {
            var address = AudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
            listeners[process] = nil
        }
        others.formIntersection(current)
        own.formIntersection(current)
        let me = getpid()
        for process in current where listeners[process] == nil && !own.contains(process) {
            if !others.contains(process) {                            // new: whose is it?
                guard Self.pid(of: process) != me else { own.insert(process); continue }
                others.insert(process)
            }
            // A registration that failed is tried again at the next list change.
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged(process) }
            var address = AudioHAL.address(kAudioProcessPropertyIsRunningOutput)
            if AudioObjectAddPropertyListenerBlock(process, &address, queue, block) == noErr { listeners[process] = block }
        }
        running = others.filter(Self.isRunningOutput)
        publish()
    }

    /// One process started or stopped producing sound: only its state is read.
    private func outputChanged(_ process: AudioObjectID) {
        guard isActive, others.contains(process) else { return }
        if Self.isRunningOutput(process) { running.insert(process) } else { running.remove(process) }
        publish()
    }

    private func publish() {
        let value = !running.isEmpty
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
