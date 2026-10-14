// CrannyAppShell/Services/FlashActivity.swift — the shell-owned transient activity behind
// `NotchControl.flash(symbol:label:)` (ARCHITECTURE.md §3.6, `ActivityID.flash`): a glyph and a short,
// already-localized label (≤ 12 characters) in the wings for 2.6 s — onboarding "Hi", "Path copied". WP13.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class FlashActivity: LiveActivity {
    static let kind = ActivityKind(id: .flash, module: .shell,
                                   title: String(localized: "Confirmations", bundle: .module,
                                                 comment: "Live Activities pane: the shell's short confirmations (e.g. \"Path copied\")"),
                                   symbol: "checkmark.circle.fill", defaultPriority: .alert)

    let id: ActivityID = .flash
    private(set) var isActive = false
    let priority: ActivityPriority = .alert
    private(set) var revision = 0
    private(set) var expiresAt: Date?
    private(set) var symbol = "hand.wave.fill"
    private(set) var label = ""
    @ObservationIgnored private var expiry: Task<Void, Never>?

    var slot: SlotWidth { label.count <= 4 ? .medium : .wide }
    var accessibilityLabel: String { label }

    /// Shows (or refreshes) the flash; it hides itself after `duration` (one sleep, no polling).
    func show(symbol: String, label: String, duration: TimeInterval) {
        self.symbol = symbol
        self.label = label
        expiresAt = Date().addingTimeInterval(duration)
        revision += 1
        isActive = true
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.isActive = false
            self?.expiresAt = nil
        }
    }

    func compactLeading() -> some View { FlashGlyph(symbol: symbol) }
    func compactTrailing() -> some View { FlashLabel(label: label, style: .compact) }
    func minimal() -> some View { FlashGlyph(symbol: symbol) }
    /// Peek anatomy (DESIGN.md §9.3): [visual 40] [title] — no controls.
    func peekRow() -> some View {
        HStack(spacing: Space.l) {
            FlashGlyph(symbol: symbol, inPeek: true)
            FlashLabel(label: label, style: .title)
            Spacer(minLength: 0)
        }
    }
}

private struct FlashGlyph: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    var inPeek = false
    var body: some View {
        let glyph = Image(systemName: symbol).foregroundStyle(theme.palette.label).accessibilityHidden(true)
        if inPeek {
            glyph.font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(theme.palette.control))
        } else {
            glyph.font(.system(size: 13 * theme.notchUnit, weight: .semibold))
        }
    }
}

private struct FlashLabel: View {
    @Environment(\.cranny) private var theme
    let label: String
    let style: CrannyTextStyle
    var body: some View {
        Text(verbatim: label).crannyFont(style).lineLimit(1).foregroundStyle(theme.palette.label)
    }
}
