// CrannyAppShell/Input/HotKeyCenter.swift — system-wide shortcuts with Carbon `RegisterEventHotKey` on the
// application event target: no Accessibility permission (ARCHITECTURE.md §4.10, verified on macOS 27).
// Intra-shell interface fixed by WP0 (§10.0): `apply(_:bindings:)`, `state(_:)`; it re-applies itself when
// `CoreSettings.shortcuts` changes, so `AppControl.setShortcut` only writes the key. WP13.
import AppKit
import Carbon
import CrannyCore
import Foundation
import os

private let log = Log.logger(.input)

@MainActor final class HotKeyCenter {
    /// Carbon delivers hot keys through a C callback without context: route by id through this table.
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    private var registered: [ShortcutID: (ref: EventHotKeyRef, id: UInt32)] = [:]
    private var states: [ShortcutID: ShortcutState] = [:]
    private var token: ObservationToken?

    /// Registers the registry's shortcuts now and again whenever the user's bindings change.
    func start(registry: ModuleRegistry) {
        let settings = registry.services.settings
        apply(registry.shortcuts, bindings: settings[CoreSettings.shortcuts])
        token = observe({ settings[CoreSettings.shortcuts] }) { [weak self] bindings in
            self?.apply(registry.shortcuts, bindings: bindings)
        }
    }

    /// (Re-)registers every shortcut with its effective combination; returns the resulting states.
    @discardableResult
    func apply(_ shortcuts: [GlobalShortcut], bindings: [ShortcutID: KeyCombo?]) -> [ShortcutID: ShortcutState] {
        unregisterAll()
        guard Self.installHandler() else {
            for shortcut in shortcuts { states[shortcut.id] = .conflict }
            return states
        }
        for shortcut in shortcuts {
            guard let combo = Self.effectiveCombo(for: shortcut, bindings: bindings) else { states[shortcut.id] = .off; continue }
            let id = Self.nextID
            Self.nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
                                             EventHotKeyID(signature: OSType(0x43524E59 /* 'CRNY' */), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[shortcut.id] = (ref, id)
                Self.actions[id] = shortcut.perform
                states[shortcut.id] = .registered
            } else {
                log.info("hot key \(shortcut.id.rawValue, privacy: .public) not registered (\(status, privacy: .public))")
                states[shortcut.id] = .conflict
            }
        }
        return states
    }

    func state(_ id: ShortcutID) -> ShortcutState { states[id] ?? .off }

    func stop() {
        token?.cancel()
        unregisterAll()
    }

    // MARK: Pure helpers (unit-tested)

    /// The user's binding wins; an explicit `nil` binding means "off"; no entry means the default.
    static func effectiveCombo(for shortcut: GlobalShortcut, bindings: [ShortcutID: KeyCombo?]) -> KeyCombo? {
        if let binding = bindings[shortcut.id] { return binding }
        return shortcut.defaultCombo
    }

    static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    // MARK: Private

    private func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
            Self.actions[entry.id] = nil
        }
        registered.removeAll()
        states.removeAll()
    }

    private static func installHandler() -> Bool {
        guard !handlerInstalled else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            let id = hotKey.id
            // Carbon dispatches application-target events on the main thread; hop explicitly anyway.
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.actions[id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
        if !handlerInstalled { log.error("InstallEventHandler failed (\(status, privacy: .public))") }
        return handlerInstalled
    }
}
