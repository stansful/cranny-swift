// CrannySettingsUI/Panes/ShortcutRecorder.swift — one shortcut row of Settings ▸ Keyboard (DESIGN.md §11.1): the key
// caps of the effective binding, a recorder (click, press the keys; Esc cancels, Delete turns it off), a clear button
// and inline conflicts — a failed registration (`AppControl.shortcutState == .conflict`), another Cranny shortcut
// with the same keys, or an enabled macOS shortcut (best effort, `SystemShortcuts`). Bindings go through
// `AppControl.setShortcut`, which stores them and re-registers at once; "Reset to Default" removes the override.
// Recording uses a local key monitor of this window only: no Accessibility permission. At most one recorder listens at a
// time (`ShortcutRecording`): starting one stops the others.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct ShortcutRow: View {
    let shortcut: GlobalShortcut
    let settings: SettingsStore
    let app: any AppControl
    /// Effective combos of the other Cranny shortcuts (for duplicates).
    let others: [(title: String, combo: KeyCombo)]
    let system: [SystemShortcut]

    var body: some View {
        let combo = KeyboardRows.effectiveCombo(shortcut, settings: settings)
        let isDefault = settings[CoreSettings.shortcuts][shortcut.id] == nil
        LabeledContent {
            ShortcutRecorder(title: shortcut.title, combo: combo) { app.setShortcut(shortcut.id, $0) }
        } label: {
            RowLabel(title: shortcut.title, footnote: warning(for: combo), isChanged: !isDefault)
        }
        .settingRow(KeyboardRows.row(for: shortcut), isDefault: isDefault) {
            settings[CoreSettings.shortcuts][shortcut.id] = nil
        }
    }

    /// The first problem with `combo`, in order of certainty.
    private func warning(for combo: KeyCombo?) -> String? {
        guard let combo else { return nil }
        if app.shortcutState(shortcut.id) == .conflict {
            return String(localized: "Another app already uses \(combo.display). Choose other keys.", bundle: .module,
                          comment: "Settings ▸ Keyboard: the shortcut could not be registered; the argument is the keys (⌃⌥N)")
        }
        if let other = others.first(where: { $0.combo.keyCode == combo.keyCode && $0.combo.modifiers == combo.modifiers }) {
            return String(localized: "\(combo.display) is also set for \(other.title).", bundle: .module,
                          comment: "Settings ▸ Keyboard: two Cranny shortcuts share keys; arguments are the keys and the other shortcut's name")
        }
        if let clash = SystemShortcuts.conflict(for: combo, in: system) {
            if let name = SystemShortcuts.name(of: clash.id) {
                return String(localized: "macOS uses \(combo.display) for \(name).", bundle: .module,
                              comment: "Settings ▸ Keyboard: a Cranny shortcut collides with a macOS shortcut; arguments are the keys and its name")
            }
            return String(localized: "macOS also uses \(combo.display).", bundle: .module,
                          comment: "Settings ▸ Keyboard: a Cranny shortcut collides with an unnamed macOS shortcut; the argument is the keys")
        }
        return nil
    }
}

/// The recorder control: key caps (or "Record Shortcut"), recording state and a clear button.
struct ShortcutRecorder: View {
    let title: String
    let combo: KeyCombo?
    let record: (KeyCombo?) -> Void
    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: (any NSObjectProtocol)?
    @State private var keyMonitor: Any?
    @State private var recordingID = UUID()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(verbatim: label)
                    .monospacedDigit()
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help(Text(verbatim: hint ?? String(localized: "Click, then press the new keys. Esc cancels, Delete turns the shortcut off.",
                                                 bundle: .module, comment: "Settings ▸ Keyboard: tooltip of a shortcut recorder")))
            .accessibilityLabel(Text("Shortcut for \(title)", bundle: .module,
                                     comment: "Settings ▸ Keyboard: VoiceOver label of a shortcut recorder; the argument is the shortcut name"))
            .accessibilityValue(Text(verbatim: combo?.display ?? Self.offTitle))
            .accessibilityHint(Text("Press to record new keys.", bundle: .module, comment: "Settings ▸ Keyboard: VoiceOver hint of a shortcut recorder"))
            Button {
                stop()
                record(nil)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .opacity(combo == nil || isRecording ? 0 : 1)
            .disabled(combo == nil || isRecording)
            .accessibilityLabel(Text("Turn off \(title)", bundle: .module,
                                     comment: "Settings ▸ Keyboard: VoiceOver label of the clear button; the argument is the shortcut name"))
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording {
            return hint ?? String(localized: "Type shortcut", bundle: .module, comment: "Settings ▸ Keyboard: recorder while it waits for keys")
        }
        return combo?.display ?? String(localized: "Record Shortcut", bundle: .module, comment: "Settings ▸ Keyboard: recorder without a shortcut")
    }

    static var offTitle: String { String(localized: "Off", bundle: .module, comment: "Settings: option that turns something off (ambient light, a display style, a shortcut)") }

    private func start() {
        ShortcutRecording.shared.begin(recordingID) { stop() }
        hint = nil
        isRecording = true
        // A local monitor sees key presses sent to this app's windows only (no Accessibility permission).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
        // Clicking elsewhere or leaving the window ends recording.
        monitor = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { stop() }
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        let modifiers = KeyComboFormatter.modifiers(event.modifierFlags)
        switch KeyComboFormatter.outcome(keyCode: event.keyCode, modifiers: modifiers,
                                         character: KeyComboFormatter.layoutCharacter(keyCode: event.keyCode) ?? event.charactersIgnoringModifiers) {
        case .cancel: stop()
        case .clear: stop(); record(nil)
        case .combo(let combo): stop(); record(combo)
        case .needsModifier:
            hint = String(localized: "Add ⌘, ⌃ or ⌥", bundle: .module, comment: "Settings ▸ Keyboard: recorder hint after a key without modifiers")
            NSSound.beep()
        }
        return true
    }

    private func stop() {
        ShortcutRecording.shared.end(recordingID)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let monitor { NotificationCenter.default.removeObserver(monitor) }
        keyMonitor = nil
        monitor = nil
        isRecording = false
        hint = nil
    }
}

/// The recorder that is listening, if any. Each recorder installs its own key monitor, so two listening at once would
/// race for the next key press; starting one stops the one before.
@MainActor final class ShortcutRecording {
    static let shared = ShortcutRecording()
    private var active: (id: UUID, stop: @MainActor () -> Void)?

    /// The listening recorder's id.
    var activeID: UUID? { active?.id }

    /// `id` starts listening; another listening recorder is stopped first.
    func begin(_ id: UUID, stop: @escaping @MainActor () -> Void) {
        if let previous = active, previous.id != id {
            active = nil
            previous.stop()
        }
        active = (id, stop)
    }

    /// `id` stopped listening (a no-op if another recorder took over).
    func end(_ id: UUID) {
        if active?.id == id { active = nil }
    }
}

#Preview("Shortcut rows") {
    let services = CrannyServices.preview()
    let shortcut = GlobalShortcut(id: .openNook, title: "Open Cranny", defaultCombo: .openNookDefault) {}
    Form {
        ShortcutRow(shortcut: shortcut, settings: services.settings, app: services.app, others: [],
                    system: SystemShortcuts.enabled(from: nil))
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 120)
}
