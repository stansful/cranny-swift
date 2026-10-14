// CrannyAppShell/Input/HotKeyCenter.swift — system-wide shortcuts with Carbon `RegisterEventHotKey` on the
// application event target: no Accessibility permission (ARCHITECTURE.md §4.10, verified on macOS 27).
// Intra-shell interface fixed by WP0 (§10.0): `apply(_:bindings:)`, `state(_:)`. It re-applies itself when
// `CoreSettings.shortcuts` changes (Reset All, Undo, any writer); `AppControl.setShortcut` writes the key and
// calls `reapply()` so it can return the resulting state at once. `states` is observed: Settings ▸ Keyboard
// re-renders when a shortcut turns `.conflict` or `.off`. WP13.
import AppKit
import Carbon
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.input)

@MainActor @Observable final class HotKeyCenter {
    /// Carbon delivers hot keys through a C callback without context: route by id through this table.
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    /// The state of every shortcut after the last `apply` (observed by views through `state(_:)`).
    private(set) var states: [ShortcutID: ShortcutState] = [:]
    @ObservationIgnored private var registered: [ShortcutID: (ref: EventHotKeyRef, id: UInt32)] = [:]
    @ObservationIgnored private weak var registry: ModuleRegistry?
    /// What the last `apply` registered, so the settings observer skips a change `reapply()` already applied.
    @ObservationIgnored private var applied: (ids: [ShortcutID], bindings: [ShortcutID: KeyCombo?])?
    @ObservationIgnored private var token: ObservationToken?

    /// Registers the registry's shortcuts now and again whenever the user's bindings change.
    func start(registry: ModuleRegistry) {
        self.registry = registry
        let settings = registry.services.settings
        reapply()
        token = observe({ settings[CoreSettings.shortcuts] }) { [weak self] bindings in
            guard let self, let registry = self.registry else { return }
            guard self.applied?.ids != registry.shortcuts.map(\.id) || self.applied?.bindings != bindings else { return }
            self.apply(registry.shortcuts, bindings: bindings)
        }
    }

    /// Re-registers the registry's shortcuts with the current bindings right away and returns the states
    /// (`AppControl.setShortcut` returns the resulting state, §3.9).
    @discardableResult func reapply() -> [ShortcutID: ShortcutState] {
        guard let registry else { return states }
        return apply(registry.shortcuts, bindings: registry.services.settings[CoreSettings.shortcuts])
    }

    /// (Re-)registers every shortcut with its effective combination; returns the resulting states.
    @discardableResult
    func apply(_ shortcuts: [GlobalShortcut], bindings: [ShortcutID: KeyCombo?]) -> [ShortcutID: ShortcutState] {
        unregisterAll()
        applied = (shortcuts.map(\.id), bindings)
        var next: [ShortcutID: ShortcutState] = [:]
        defer { if states != next { states = next } }        // one observable change per apply
        guard Self.installHandler() else {
            for shortcut in shortcuts { next[shortcut.id] = .conflict }
            return next
        }
        for shortcut in shortcuts {
            guard let combo = Self.effectiveCombo(for: shortcut, bindings: bindings) else { next[shortcut.id] = .off; continue }
            let id = Self.nextID
            Self.nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
                                             EventHotKeyID(signature: OSType(0x43524E59 /* 'CRNY' */), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[shortcut.id] = (ref, id)
                Self.actions[id] = shortcut.perform
                next[shortcut.id] = .registered
            } else {
                log.info("hot key \(shortcut.id.rawValue, privacy: .public) not registered (\(status, privacy: .public))")
                next[shortcut.id] = .conflict
            }
        }
        return next
    }

    func state(_ id: ShortcutID) -> ShortcutState { states[id] ?? .off }

    func stop() {
        token?.cancel()
        unregisterAll()
        applied = nil
        states = [:]
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
