// CrannyOnboarding/Tutorial/TutorialBubblePanel.swift — the window behind the tip (ARCHITECTURE.md §5.9): a
// small non-activating panel at the notch's level (26) whose caret sits 10 pt under
// `NotchControl.shapeFrameOnScreen()`. Clicking "Skip tour" never activates Cranny; a coach mark without a
// button is click-through. The panel follows the shape when it opens or closes and fades in and out
// (instantly under Reduce Motion).
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

    init() {}

    func show(_ content: TipContent, under anchor: CGRect?) {
        let (panel, hosting) = ensurePanel()
        let isNew = !panel.isVisible || orderOut != nil
        orderOut?.cancel()
        orderOut = nil
        model.content = content
        panel.ignoresMouseEvents = !content.isInteractive
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let frame = Self.frame(size: size, under: anchor ?? Self.fallbackAnchor())
        if isNew {
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()                         // never activates the app
            animate { panel.animator().alphaValue = 1 }
        } else if panel.frame != frame {
            animate { panel.animator().setFrame(frame, display: true) }
        }
    }

    func hide() {
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

    /// Without a notch frame: just under the main display's menu bar.
    private static func fallbackAnchor() -> CGRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        return CGRect(x: screen.frame.midX - 1, y: screen.visibleFrame.maxY, width: 2, height: 0)
    }

    // MARK: Private

    private func ensurePanel() -> (TutorialBubblePanel, TipHostingView) {
        if let panel, let hosting { return (panel, hosting) }
        let panel = TutorialBubblePanel()
        let hosting = TipHostingView(rootView: TipBubbleView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return (panel, hosting)
    }

    /// Runs `changes` animated (AppKit window animation; instant under Reduce Motion) and returns its length.
    @discardableResult private func animate(_ changes: () -> Void) -> Double {
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : CrannyMotion.Kind.contentSwapDuration
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
