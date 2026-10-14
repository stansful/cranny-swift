// CrannyHUD/Private/KeyboardBacklight.swift — the built-in keyboard backlight through the PRIVATE
// `CoreBrightness.KeyboardBrightnessClient` (ARCHITECTURE.md §7.1, §7.12; R3 §1.6). Read [VERIFIED],
// write [UNVERIFIED], so `HUDSettings.keyboardBacklight` defaults to off until the hardware checklist confirms it.
// Low priority: Apple Silicon keyboards have no illumination keys.
//
// Resolved at runtime (NSClassFromString + responds(to:)); every call is guarded and a missing piece makes
// `readLevel()` nil, so the illumination keys go to macOS. A write that reports failure also passes the key
// through (`MediaKeyHandler`). Called on the key tap's thread; the client is created once, under a lock.
import CrannyCore
import Foundation
import ObjectiveC
import os

/// Level of the keyboard backlight the illumination keys drive. nil = none: pass the key through.
nonisolated protocol KeyboardBacklight: Sendable {
    func readLevel() -> Double?
    func setLevel(_ level: Double) -> Bool
}

nonisolated final class CoreBrightnessKeyboard: KeyboardBacklight {
    private typealias GetFunction = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetFunction = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool

    private struct Client: @unchecked Sendable {   // used only under `client`'s lock
        let object: NSObject
        let keyboard: UInt64
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private let client = OSAllocatedUnfairLock<Client??>(initialState: nil)

    init() {}

    func readLevel() -> Double? {
        withClient { client in
            guard client.object.responds(to: Self.getSelector) else { return nil }
            let get = unsafeBitCast(client.object.method(for: Self.getSelector), to: GetFunction.self)
            let value = get(client.object, Self.getSelector, client.keyboard)
            return value.isFinite && value >= 0 ? Double(value) : nil
        }
    }

    func setLevel(_ level: Double) -> Bool {
        withClient { client in
            guard client.object.responds(to: Self.setSelector) else { return false }
            let set = unsafeBitCast(client.object.method(for: Self.setSelector), to: SetFunction.self)
            return set(client.object, Self.setSelector, Float(min(max(level, 0), 1)), client.keyboard)
        } ?? false
    }

    private func withClient<T: Sendable>(_ body: @Sendable (Client) -> T?) -> T? {
        client.withLock { cached -> T? in
            let resolved: Client?
            if let cached {
                resolved = cached
            } else {
                resolved = Self.makeClient()
                cached = .some(resolved)
                if resolved == nil { log.info("keyboard backlight client unavailable; illumination keys pass through") }
            }
            guard let resolved else { return nil }
            return body(resolved)
        }
    }

    private static func makeClient() -> Client? {
        guard dlopen(frameworkPath, RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let object = type.init()
        let copyIDs = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard object.responds(to: copyIDs),
              let ids = object.perform(copyIDs)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first else { return nil }
        return Client(object: object, keyboard: first.uint64Value)
    }
}

private nonisolated let log = Log.logger(.hud)
