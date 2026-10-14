// CrannyHUD/Keys/MediaKeyInterceptor.swift — the session-level ACTIVE event tap on `NX_SYSDEFINED`
// (ARCHITECTURE.md §7.1, R3 §1.2–1.4). Consuming a volume key suppresses both the system's change and the
// macOS 27 OSD (MenuBarAgent's 352 × 149 window) [VERIFIED R3]; `MediaKeyHandler` applies the change instead.
//
// Thread: the tap lives on its own `Thread` with its own CFRunLoop, so a busy main thread never makes macOS
// disable it (`tapDisabledByTimeout`); the callback re-enables a disabled tap. The callback reads only the
// immutable handler and the port. Creating the tap needs Accessibility: without it `CGEvent.tapCreate` returns
// nil and keys stay with macOS. The controller creates a tap only when "Replace the system HUD" is on AND
// `AXIsProcessTrusted()` is true, so this file never causes a permission prompt. A crashed or stalled tap
// hands the keys back to macOS automatically.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import os

/// Something that delivers media-key events to a `MediaKeyHandler` (the real tap, or a test double).
nonisolated protocol KeyInterceptor: AnyObject, Sendable {
    /// false = the tap could not be created (Accessibility missing or revoked).
    func start() -> Bool
    func stop()
}

/// How the tap callback treats an event type (pure, tested).
nonisolated enum TapEventKind: Equatable, Sendable {
    /// macOS disabled the tap (slow callback or user input): enable it again and pass the event on.
    case reenable
    case systemDefined
    case other

    init(rawType: UInt32) {
        switch rawType {
        case CGEventType.tapDisabledByTimeout.rawValue, CGEventType.tapDisabledByUserInput.rawValue: self = .reenable
        case UInt32(MediaKeyEvent.systemDefinedType): self = .systemDefined
        default: self = .other
        }
    }
}

nonisolated final class MediaKeyInterceptor: KeyInterceptor {
    private struct Loop {
        var port: CFMachPort?
        var runLoop: CFRunLoop?
        /// Bumped by every start and stop, so a tap thread that starts late never attaches a newer tap's port.
        var generation = 0
    }

    private let handler: MediaKeyHandler
    // CFMachPort / CFRunLoop are thread-safe CF objects; the lock only orders start, stop and the thread's setup.
    private let loop = OSAllocatedUnfairLock(uncheckedState: Loop())

    init(handler: MediaKeyHandler) { self.handler = handler }

    func start() -> Bool {
        if loop.withLockUnchecked({ $0.port != nil }) { return true }
        let mask = CGEventMask(1) << CGEventMask(MediaKeyEvent.systemDefinedType)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: Self.callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.info("event tap not created (Accessibility missing); keys stay with macOS")
            return false
        }
        let generation = loop.withLockUnchecked { state -> Int in
            state.generation += 1
            state.port = port
            state.runLoop = nil
            return state.generation
        }
        // The thread keeps `self` alive until its run loop exits, so the callback's unretained pointer stays valid.
        let thread = Thread { [self] in runTapLoop(generation: generation) }
        thread.name = "Cranny.MediaKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        log.info("event tap started")
        return true
    }

    func stop() {
        let (port, runLoop) = loop.withLockUnchecked { state -> (CFMachPort?, CFRunLoop?) in
            state.generation += 1
            defer { state.port = nil; state.runLoop = nil }
            return (state.port, state.runLoop)
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop { CFRunLoopStop(runLoop) }
        log.info("event tap stopped")
    }

    /// The tap thread's body: attach the port to this thread's run loop and run it until `stop()`.
    private func runTapLoop(generation: Int) {
        let current = CFRunLoopGetCurrent()
        let attached = loop.withLockUnchecked { state -> CFMachPort? in
            guard state.generation == generation, let port = state.port else { return nil }   // stopped meanwhile
            state.runLoop = current
            return port
        }
        guard let port = attached, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return }
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        CFRunLoopRun()
        CFRunLoopRemoveSource(current, source, .commonModes)
    }

    private func reenable() {
        guard let port = loop.withLockUnchecked({ $0.port }) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        log.info("event tap re-enabled after macOS disabled it")
    }

    /// Runs on the tap thread for every system-defined event. Keep it fast.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        switch TapEventKind(rawType: type.rawValue) {
        case .reenable:
            interceptor.reenable()
            return Unmanaged.passUnretained(event)
        case .other:
            return Unmanaged.passUnretained(event)
        case .systemDefined:
            guard let nsEvent = NSEvent(cgEvent: event),
                  let key = MediaKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1,
                                                 flags: event.flags.rawValue) else { return Unmanaged.passUnretained(event) }
            return interceptor.handler.handle(key) ? nil : Unmanaged.passUnretained(event)
        }
    }
}

private nonisolated let log = Log.logger(.eventTap)
