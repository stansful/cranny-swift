// CrannyAppShell/Services/FlashActivity.swift — the shell-owned transient activity behind
// `NotchControl.flash(symbol:label:)` (ARCHITECTURE.md §3.6, `ActivityID.flash`): a glyph and a short,
// already-localized label (≤ 12 characters) in the wings for 2.6 s — onboarding "Hi", "Path copied". The shell's
// own confirmations (Pause Live Activities, Resume) add a `detail` sentence, drawn in the flash's peek row, in the
// open header while the panel is open (`OpenHeaderActivity`) and read by VoiceOver, and outlast the pause they
// confirm (`outlastsPause`).
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class FlashActivity: OpenHeaderActivity {
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
    /// The whole sentence of a shell confirmation ("Live Activities paused for 1 hour"): the peek row, the open header
    /// and VoiceOver say it, the wings keep the short `label`. Nil for `NotchControl.flash`.
    private(set) var detail: String?
    /// A Pause Live Activities or Resume confirmation: shown (and peeked) although activities are paused, and not
    /// hidden when the pause it confirms begins.
    private(set) var outlastsPause = false
    @ObservationIgnored private var expiry: Task<Void, Never>?

    var slot: SlotWidth { label.count <= 4 ? .medium : .wide }
    var accessibilityLabel: String { detail ?? label }
    /// A confirmation takes the open header while the panel is open (it can neither show in the wings nor peek
    /// there); an ordinary flash waits in the lineup.
    var headerMessage: String? { detail }

    /// Shows (or refreshes) the flash; it hides itself after `duration` (one sleep, no polling).
    /// Call through `OverlayCoordinator.showFlash` (it picks the display and drops the flash while paused) or
    /// `OverlayCoordinator.confirmPause`.
    func show(symbol: String, label: String, detail: String? = nil, duration: TimeInterval, outlastsPause: Bool = false) {
        self.symbol = symbol
        self.label = label
        self.detail = detail
        self.outlastsPause = outlastsPause
        expiresAt = Date().addingTimeInterval(duration)
        revision += 1
        isActive = true
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    /// Ends the flash now (Pause Live Activities began: a paused flash never comes back stale).
    func hide() {
        expiry?.cancel()
        expiry = nil
        end()
    }

    private func end() {
        isActive = false
        expiresAt = nil
        outlastsPause = false
    }

    func compactLeading() -> some View { FlashGlyph(symbol: symbol) }
    func compactTrailing() -> some View { FlashLabel(label: label, style: .compact) }
    func minimal() -> some View { FlashGlyph(symbol: symbol) }
    /// Peek anatomy (DESIGN.md §9.3): [visual 40] [title] — no controls. A confirmation's sentence may wrap to a second
    /// line (two `title` lines fit the 52-pt row, also at the larger text sizes).
    func peekRow() -> some View {
        HStack(spacing: Space.l) {
            FlashGlyph(symbol: symbol, inPeek: true)
            FlashLabel(label: detail ?? label, style: .title, lines: detail == nil ? 1 : 2)
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
            glyph.crannySymbol(.peekVisual)
                .frame(width: NotchLayout.peekVisual, height: NotchLayout.peekVisual)
                .background(RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(theme.palette.control))
        } else {
            glyph.crannySymbol(.band)
        }
    }
}

private struct FlashLabel: View {
    @Environment(\.cranny) private var theme
    let label: String
    let style: CrannyTextStyle
    var lines = 1
    var body: some View {
        Text(verbatim: label).crannyFont(style).lineLimit(lines).foregroundStyle(theme.palette.label)
    }
}

#Preview("Flash · compact and peek row") {
    let flash = FlashActivity()
    flash.show(symbol: "doc.on.doc", label: "Path copied", duration: 3600)
    return VStack(spacing: 16) {
        HStack(spacing: 12) { flash.compactLeading(); flash.compactTrailing() }
        flash.peekRow().frame(width: 360)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Flash · pause confirmation") {
    let flash = FlashActivity()
    let confirmation = PauseConfirmation.paused(.untilTomorrow)
    flash.show(symbol: confirmation.symbol, label: confirmation.label, detail: confirmation.message, duration: 3600,
               outlastsPause: true)
    return VStack(spacing: 16) {
        HStack(spacing: 12) { flash.compactLeading(); flash.compactTrailing() }
        flash.peekRow().frame(width: 356)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
