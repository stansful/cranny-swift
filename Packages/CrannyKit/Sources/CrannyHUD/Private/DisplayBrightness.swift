// CrannyHUD/Private/DisplayBrightness.swift — built-in display brightness through the PRIVATE DisplayServices
// framework (ARCHITECTURE.md §7.1, §7.12; R3 §1.6). There is no public brightness API on Apple Silicon.
//
// Resolved at runtime with dlopen/dlsym (never linked); loads under the hardened runtime without
// `disable-library-validation` [VERIFIED R3]. Capability probe: the three symbols resolve, a built-in display
// is online and awake, and `DisplayServicesCanChangeBrightness` says yes. Otherwise `readLevel()` is nil and the
// brightness keys go to macOS (external non-Apple displays, clamshell mode). Built-in get/set and real
// brightness keys on Apple Silicon are [UNVERIFIED]: the hardware checklist (§11.2 item 6) confirms them before
// `HUDSettings.brightness` defaults to on. Called on the key tap's thread (and by the 2-Hz poll of a visible
// brightness HUD). Finding the built-in display enumerates every online display, so a press, which reads and then
// writes within microseconds, resolves it once: the write reuses the display its read just found.
import CoreGraphics
import CrannyCore
import Foundation
import os

/// Brightness of the display the brightness keys drive. nil = no controllable display: pass the key through.
nonisolated protocol DisplayBrightness: Sendable {
    func readLevel() -> Double?
    func setLevel(_ level: Double) -> Bool
}

nonisolated final class DisplayServicesBrightness: DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private struct Symbols: @unchecked Sendable {   // C function pointers: immutable once resolved
        let get: GetFunction
        let set: SetFunction
        let canChange: CanChangeFunction
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    /// Resolved on first use (never in `register(in:)`), then cached; nil = the framework or a symbol is missing.
    private let symbols = OSAllocatedUnfairLock<Symbols??>(initialState: nil)
    /// The display the latest read found, and when (`systemUptime`).
    private let lastTarget = OSAllocatedUnfairLock<(display: CGDirectDisplayID, uptime: TimeInterval)?>(initialState: nil)

    /// A write this soon after a read goes to the display the read found (a press reads, then writes at once).
    static let targetReuse: TimeInterval = 0.1

    init() {}

    func readLevel() -> Double? {
        guard let symbols = resolved(), let display = Self.targetDisplay() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        lastTarget.withLock { $0 = (display, now) }
        guard symbols.canChange(display) else { return nil }
        var value: Float = -1
        guard symbols.get(display, &value) == 0, value >= 0 else { return nil }
        return Double(value)
    }

    func setLevel(_ level: Double) -> Bool {
        guard let symbols = resolved() else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let justRead = lastTarget.withLock { target in
            target.flatMap { now - $0.uptime < Self.targetReuse ? $0.display : nil }
        }
        guard let display = justRead ?? Self.targetDisplay() else { return false }
        return symbols.set(display, Float(min(max(level, 0), 1))) == 0
    }

    /// The built-in display when it is online and awake; anything else keeps the system's control.
    static func targetDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    private func resolved() -> Symbols? {
        symbols.withLock { cached -> Symbols? in
            if let cached { return cached }
            let found = Self.resolve()
            cached = .some(found)
            if found == nil { log.info("DisplayServices brightness unavailable; brightness keys pass through") }
            return found
        }
    }

    private static func resolve() -> Symbols? {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness"),
              let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness") else { return nil }
        return Symbols(get: unsafeBitCast(get, to: GetFunction.self), set: unsafeBitCast(set, to: SetFunction.self),
                       canChange: unsafeBitCast(canChange, to: CanChangeFunction.self))
    }
}

private nonisolated let log = Log.logger(.hud)
