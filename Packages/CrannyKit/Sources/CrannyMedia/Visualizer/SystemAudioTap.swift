// CrannyMedia/Visualizer/SystemAudioTap.swift — the opt-in Live visualizer's audio source (ARCHITECTURE.md
// §6.6, R2 §8): a Core Audio process tap of everything that plays EXCEPT Cranny (browsers play from helper
// processes, so a per-PID tap would miss them), a private aggregate device and an IO proc that mixes to mono.
//
// Threading: `start`/`stop` are called from the main actor; the IO block runs on the HAL's real-time thread and
// touches only `SampleRing`, which never blocks it (try-lock, drops a buffer on contention).
// Permission: macOS asks for "System Audio Recording" on the first `AudioDeviceStart`. There is no query API;
// a denied tap fails with `kAudioDevicePermissionsError` or delivers silence. Never started by tests.
// Needs `NSAudioCaptureUsageDescription` in the app's hand-written Info.plist (R2 §8).
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Mono samples written by the IO thread, read by the analyzer. Every access is behind `lock`.
nonisolated final class SampleRing: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var write = 0
    private var written = 0

    init(capacity: Int = 4096) {
        self.capacity = max(capacity, 64)
        storage = .allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }
    deinit { storage.deallocate() }

    /// IO thread: interleaved stereo Float32. Drops the buffer instead of waiting for the lock.
    func pushStereo(_ samples: UnsafePointer<Float>, frames: Int) {
        _ = lock.withLockIfAvailableUnchecked {
            for i in 0..<frames { storage[(write + i) % capacity] = 0.5 * (samples[2 * i] + samples[2 * i + 1]) }
            write = (write + frames) % capacity
            written &+= frames
        }
    }

    /// Mono samples (tests, mono sources).
    func pushMono(_ samples: UnsafeBufferPointer<Float>) {
        lock.withLockUnchecked {
            for (i, s) in samples.enumerated() { storage[(write + i) % capacity] = s }
            write = (write + samples.count) % capacity
            written &+= samples.count
        }
    }

    /// Copies the latest `out.count` samples, oldest first. Returns the total written so far (0 = nothing yet).
    @discardableResult
    func latest(into out: UnsafeMutableBufferPointer<Float>) -> Int {
        lock.withLockUnchecked {
            let count = min(out.count, capacity)
            let start = (write - count + capacity) % capacity
            for i in 0..<count { out[i] = storage[(start + i) % capacity] }
            return written
        }
    }
}

nonisolated enum SystemAudioTapError: Error, Equatable, Sendable {
    /// The user denied System Audio Recording (or it is restricted).
    case permissionDenied
    /// Any other Core Audio failure, with the step and status code.
    case coreAudio(step: String, status: OSStatus)
}

@available(macOS 14.2, *)
nonisolated final class SystemAudioTap: @unchecked Sendable {   // the IDs are touched only by start/stop on the main actor
    let ring = SampleRing()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    var isRunning: Bool { ioProc != nil }

    /// Starts tapping (shows the permission prompt the first time).
    func start() throws(SystemAudioTapError) {
        guard ioProc == nil else { return }
        let own = Self.processObject(for: getpid())
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Cranny visualizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Self.failure("create tap", status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cranny Visualizer",
            kAudioAggregateDeviceUIDKey: "app.cranny.visualizer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw Self.failure("create aggregate", status) }

        let ring = self.ring
        let block: AudioDeviceIOBlock = { @Sendable _, input, _, _, _ in
            // A stereo mixdown tap delivers interleaved Float32.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let frames = Int(first.mDataByteSize) / (2 * MemoryLayout<Float>.size)
            ring.pushStereo(data.assumingMemoryBound(to: Float.self), frames: frames)
        }
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, block)
        guard status == noErr else { stop(); throw Self.failure("create IO proc", status) }
        status = AudioDeviceStart(aggregateID, ioProc)      // the permission prompt appears here the first time
        guard status == noErr else { stop(); throw Self.failure("start", status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregateID, ioProc)
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        ioProc = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    private static func failure(_ step: String, _ status: OSStatus) -> SystemAudioTapError {
        status == kAudioDevicePermissionsError ? .permissionDenied : .coreAudio(step: step, status: status)
    }

    /// Cranny's own Core Audio process object (excluded from the tap so its own sounds never feed the bars).
    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }
}
