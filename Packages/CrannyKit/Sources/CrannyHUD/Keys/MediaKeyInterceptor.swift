// CrannyHUD/Keys/MediaKeyInterceptor.swift — the session-level ACTIVE event tap on `NX_SYSDEFINED`
// (ARCHITECTURE.md §7.1, R3 §1.2–1.4). Consuming a volume key suppresses both the system's change and the
// macOS 27 OSD (MenuBarAgent's 352 × 149 window) [VERIFIED R3]; `MediaKeyHandler` applies the change instead.
//
// Thread: the tap lives on its own `Thread` with its own CFRunLoop, so a busy main thread never makes macOS
// disable it (`tapDisabledByTimeout`); the callback re-enables a disabled tap. The callback reads only the
// immutable handler and the locked loop state. Creating the tap needs Accessibility: without it
// `CGEvent.tapCreate` returns nil and keys stay with macOS. The controller creates a tap only when "Replace the
// system HUD" is on AND `AXIsProcessTrusted()` is true, so this file never causes a permission prompt. A crashed
// or stalled tap hands the keys back to macOS automatically.
//
// Energy: while the HUD cannot be shown (locked, displays asleep, a full-screen app under "Hide everything", the
// HUD's display without it) the tap would hand every event straight back to macOS, so the controller turns it
// off (`setEnabled(false)`) and the window server stops routing system-defined events — media keys and every
// mouse-button transition — through Cranny; the tap stays installed. The switch happens on the tap thread,
// between two events, and a key whose key-down was consumed keeps the tap on until its key-up
// (`receivesEvents`): macOS never sees a key-up without its key-down.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import os

/// Something that delivers media-key events to a `MediaKeyHandler` (the real tap, or a test double).
nonisolated protocol KeyInterceptor: AnyObject, Sendable {
    /// false = the tap could not be created (Accessibility missing or revoked).
    func start() -> Bool
    /// false while the HUD cannot be shown: every event would go back to macOS, so the tap stops receiving them
    /// and stays installed; true resumes. A new interceptor receives events.
    func setEnabled(_ on: Bool)
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
        /// The controller wants events (`setEnabled`).
        var wantsEvents = true
        /// The tap is enabled as far as this class set it (macOS may also disable it: `reenable`).
        var isEnabled = false
    }

    /// Whether the tap receives events: while the controller wants them, and while a consumed key's key-up is
    /// still to come (its key-down never reached macOS, so its key-up must not either). Pure, tested.
    static func receivesEvents(wanted: Bool, holdingConsumedKey: Bool) -> Bool { wanted || holdingConsumedKey }

    private let handler: MediaKeyHandler
    // CFMachPort / CFRunLoop are thread-safe CF objects; the lock orders start, stop, the thread's setup and the
    // enabled state (set by the controller, applied on the tap thread).
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

    func setEnabled(_ on: Bool) {
        let runLoop = loop.withLockUnchecked { state -> CFRunLoop? in
            state.wantsEvents = on
            return state.port == nil ? nil : state.runLoop
        }
        // Not attached yet: `runTapLoop` reads `wantsEvents` when it attaches. Otherwise on the tap thread,
        // between two events.
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in applyEnabled() }
        CFRunLoopWakeUp(runLoop)
    }

    /// The tap thread's body: attach the port to this thread's run loop and run it until `stop()`.
    private func runTapLoop(generation: Int) {
        let current = CFRunLoopGetCurrent()
        let holding = handler.isHoldingConsumedKey
        let attached = loop.withLockUnchecked { state -> (port: CFMachPort, enabled: Bool)? in
            guard state.generation == generation, let port = state.port else { return nil }   // stopped meanwhile
            state.runLoop = current
            state.isEnabled = Self.receivesEvents(wanted: state.wantsEvents, holdingConsumedKey: holding)
            return (port, state.isEnabled)
        }
        guard let (port, enabled) = attached, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return }
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: enabled)
        CFRunLoopRun()
        CFRunLoopRemoveSource(current, source, .commonModes)
    }

    /// On the tap thread: enables or disables the tap as `receivesEvents` says (a no-op when it already is).
    private func applyEnabled() {
        let holding = handler.isHoldingConsumedKey               // changes only on this thread
        let change = loop.withLockUnchecked { state -> (port: CFMachPort, on: Bool)? in
            guard let port = state.port else { return nil }
            let on = Self.receivesEvents(wanted: state.wantsEvents, holdingConsumedKey: holding)
            guard on != state.isEnabled else { return nil }
            state.isEnabled = on
            return (port, on)
        }
        guard let (port, on) = change else { return }
        CGEvent.tapEnable(tap: port, enable: on)
        log.info("event tap \(on ? "enabled" : "disabled", privacy: .public): the HUD \(on ? "can" : "cannot", privacy: .public) be shown")
    }

    /// After each event while the controller wants none: the key-up of a consumed key turns the tap off. On this
    /// run loop once the callback has returned, so the window server has the answer for that key-up (consumed)
    /// before it hears that the tap is off.
    private func eventHandled() {
        guard !loop.withLockUnchecked({ $0.wantsEvents }) else { return }
        CFRunLoopPerformBlock(CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue) { [self] in applyEnabled() }
    }

    private func reenable() {
        let holding = handler.isHoldingConsumedKey
        let target = loop.withLockUnchecked { state -> (port: CFMachPort, on: Bool)? in
            guard let port = state.port else { return nil }
            state.isEnabled = Self.receivesEvents(wanted: state.wantsEvents, holdingConsumedKey: holding)
            return (port, state.isEnabled)
        }
        guard let target else { return }
        if target.on {                            // turned off on purpose: it stays off
            CGEvent.tapEnable(tap: target.port, enable: true)
            log.info("event tap re-enabled after macOS disabled it")
        }
        handler.tapWasDisabled()                  // the main actor re-checks the grant (revoked → tap removed)
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
            defer { interceptor.eventHandled() }
            // The tap thread's run loop drains no autorelease pool by itself, and every mouse-button press is a
            // system-defined event too: the decoding's objects are released per event, not when the thread ends.
            let key = autoreleasepool { () -> MediaKeyEvent? in
                guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
                return MediaKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1,
                                            flags: event.flags.rawValue)
            }
            guard let key else { return Unmanaged.passUnretained(event) }
            return interceptor.handler.handle(key) ? nil : Unmanaged.passUnretained(event)
        }
    }
}

private nonisolated let log = Log.logger(.eventTap)
