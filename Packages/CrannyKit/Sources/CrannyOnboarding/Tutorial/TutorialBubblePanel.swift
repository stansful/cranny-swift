// CrannyOnboarding/Tutorial/TutorialBubblePanel.swift — the window behind the tip (ARCHITECTURE.md §5.9): a
// small non-activating panel at the notch's level (26) whose caret sits 10 pt under
// `NotchControl.shapeFrameOnScreen()`. Clicking "Skip tour" never activates Cranny; a coach mark without a
// button is click-through. The panel fades in and out, and when the shape opens or closes it fades out, moves
// and fades back in under the new shape (instantly under Reduce Motion). It is never moved with an animated
// frame: AppKit's window-frame animation stalls while the displays sleep and would leave it behind. Its owners
// show it only under a real shape (`TipSurroundings`) and hide it otherwise. While VoiceOver runs, a new or
// changed tour bubble posts a layout change pointing at itself, so "Skip tour" can be reached.
import AppKit
import CrannyCore
import SwiftUI

/// The live `TipPresenter`.
@MainActor final class TipPanelPresenter: TipPresenter {
    var onAction: (@MainActor () -> Void)? {
        didSet { model.onAction = { [weak self] in self?.onAction?() } }
    }

    private let model = TipModel(content: TipContent(text: ""))
    private var panel: TutorialBubblePanel?
    private var hosting: TipHostingView?
    /// Orders the panel out once its fade has finished (one sleep, cancelled by the next `show`).
    private var orderOut: Task<Void, Never>?
    /// A move under a new shape: fade out, jump, fade in (one sleep, superseded by a `show` elsewhere).
    private var move: Task<Void, Never>?
    /// Where the move in flight goes (a repeated `show` for the same place lets it finish).
    private var moveTarget: CGRect?

    init() {}

    func show(_ content: TipContent, under anchor: CGRect, theme: CrannyTheme) {
        let (panel, hosting) = ensurePanel()
        let isNew = !panel.isVisible || orderOut != nil
        let isNewContent = isNew || model.content != content
        orderOut?.cancel()
        orderOut = nil
        if model.content != content { model.content = content }
        if model.theme != theme { model.theme = theme }
        panel.ignoresMouseEvents = !content.isInteractive
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.intrinsicContentSize               // the bubble's own size (see TipBubble's frame)
        let frame = Self.frame(size: size, under: anchor)
        if isNew {
            cancelMove()
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()                         // never activates the app
            animate { panel.animator().alphaValue = 1 }
        } else if let moveTarget, Self.isSamePlace(moveTarget, frame) {
            self.moveTarget = frame                              // on its way; take the latest size
        } else if !Self.isSamePlace(panel.frame, frame) {
            startMove(panel, to: frame)
        } else {
            let wasMoving = moveTarget != nil
            cancelMove()
            if panel.frame != frame { panel.setFrame(frame, display: true) }     // same place, new content size
            if wasMoving { animate { panel.animator().alphaValue = 1 } }        // back where it was: fade in again
        }
        if isNewContent, content.isInteractive { offerToVoiceOver(panel, hosting) }
    }

    /// Fades out, jumps under the new shape and fades back in.
    private func startMove(_ panel: TutorialBubblePanel, to frame: CGRect) {
        move?.cancel()
        moveTarget = frame
        let duration = animate { panel.animator().alphaValue = 0 }
        move = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, let panel else { return }
            panel.setFrame(self.moveTarget ?? frame, display: true)
            self.animate { panel.animator().alphaValue = 1 }
            self.move = nil
            self.moveTarget = nil
        }
    }

    private func cancelMove() {
        move?.cancel()
        move = nil
        moveTarget = nil
    }

    /// The caret's tip lands within a point of where it already points.
    private static func isSamePlace(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.maxY - b.maxY) <= 1 && abs(a.midX - b.midX) <= 1
    }

    func hide() {
        cancelMove()
        guard let panel, panel.isVisible, orderOut == nil else { return }
        let duration = animate { panel.animator().alphaValue = 0 }
        orderOut = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.panel?.orderOut(nil)
            self.orderOut = nil
        }
    }

    // MARK: Geometry

    /// The caret's tip sits `tipGap − caret` under the shape, centred on it, clamped inside its screen.
    static func frame(size: CGSize, under anchor: CGRect) -> CGRect {
        let size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))     // whole points
        let margin = TipBubble.shadowMargin
        let caretTipGap = WelcomeMetrics.tipGap - TipBubble.caretSize.height
        var frame = CGRect(x: (anchor.midX - size.width / 2).rounded(), y: (anchor.minY - caretTipGap + margin - size.height).rounded(),
                           width: size.width, height: size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) }) {
            let limits = screen.frame.insetBy(dx: Space.m - margin, dy: 0)
            frame.origin.x = min(max(frame.minX, limits.minX), limits.maxX - frame.width)
        }
        return frame
    }

    // MARK: Private

    private func ensurePanel() -> (TutorialBubblePanel, TipHostingView) {
        if let panel, let hosting { return (panel, hosting) }
        let panel = TutorialBubblePanel()
        let hosting = TipHostingView(rootView: TipBubbleView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]       // measured, never resizes the panel by itself
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return (panel, hosting)
    }

    /// The tour bubble is in another app's world (Cranny is not active), so VoiceOver does not find it on its own:
    /// a layout change naming the bubble lets VoiceOver users reach "Skip tour". Best effort, only while VoiceOver runs.
    private func offerToVoiceOver(_ panel: NSPanel, _ hosting: NSView) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: panel, notification: .layoutChanged, userInfo: [.uiElements: [hosting]])
    }

    /// Runs `changes` animated (AppKit window animation; instant under Reduce Motion and the Instant motion
    /// personality) and returns its length.
    @discardableResult private func animate(_ changes: () -> Void) -> Double {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.theme.motion == .instant
        let duration = still ? 0 : CrannyMotion.Kind.contentSwapDuration
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = duration
        changes()
        NSAnimationContext.endGrouping()
        return duration
    }
}

/// Borderless, non-activating, at the notch's level, on every Space and over full-screen apps (R1 §3.1).
final class TutorialBubblePanel: NSPanel {
    init() {
        // .nonactivatingPanel must be in the init style mask (R1 gotcha 4).
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true                     // resets the level: set it after (R1 gotcha 1)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                          // SwiftUI draws the bubble's elevation
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        appearance = NSAppearance(named: .darkAqua)
    }
    override var canBecomeKey: Bool { true }       // only if a control needs it (becomesKeyOnlyIfNeeded)
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The first click on "Skip tour" acts at once (R1 gotcha 6).
final class TipHostingView: NSHostingView<TipBubbleView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension CrannyMotion.Kind {
    /// Duration of the window-level fades and moves of the tip (the `contentSwap` curve's length).
    static var contentSwapDuration: Double {
        if case .smooth(let duration) = CrannyMotion.spec(.contentSwap).curve { return duration }
        return 0.3
    }
}
