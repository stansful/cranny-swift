// CrannyAppShell/Services/SharingPresenter.swift — AirDrop and the share picker for `NotchControl` (ARCHITECTURE.md
// §5.9, §7.7, R3 §7). The AirDrop sheet centres on its source window and inherits its level, so it gets a transparent,
// normal-level anchor window on screen just below the notch (a 400 × 300 area, so the sheet is fully visible and
// clear of the open panel). `perform` activates Cranny by itself; the share picker needs `NSApp.activate()` first.
// Either way the app that was frontmost gets activation back afterwards, and the panel is held open meanwhile.
// A session always ends: the service and picker are kept alive until it does (AppKit holds its delegate weakly
// and the service not at all), and if no callback ever comes, Cranny losing activation with no sheet left on the
// anchor, or a generous timeout, ends it, so the `share` hold and the next request can never get stuck.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.overlay)

@MainActor final class SharingPresenter: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
    /// The notch shape on the pointer's display (screen coordinates); the anchor goes below it.
    var shapeFrame: () -> CGRect? = { nil }
    /// Holds the panel open while a sheet is up (`NotchMachineState.shareHold`).
    var setHold: (Bool) -> Void = { _ in }

    nonisolated static let anchorSize = CGSize(width: 400, height: 300)
    /// The longest a sheet may stay up without telling us how it ended.
    static let sessionTimeout: Duration = .seconds(600)

    private var anchor: NSWindow?
    private var previousApp: NSRunningApplication?
    private var airDrop: CheckedContinuation<Bool, Never>?
    private(set) var isPresenting = false
    /// Kept until the session ends: nothing else retains them.
    private var service: NSSharingService?
    private var picker: NSSharingServicePicker?
    private var timeoutTask: Task<Void, Never>?
    private var resignObserver: (any NSObjectProtocol)?

    // MARK: NotchControl

    /// AirDrop from the anchor window; true when the items were sent.
    func presentAirDrop(_ urls: [URL]) async -> Bool {
        guard !isPresenting, !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        begin()
        self.service = service
        service.delegate = self
        return await withCheckedContinuation { continuation in
            airDrop = continuation
            service.perform(withItems: urls)
        }
    }

    /// The system share picker, shown from the anchor (activates Cranny first, R3 §7).
    func presentSharePicker(_ urls: [URL]) {
        guard !isPresenting, !urls.isEmpty else { return }
        begin()
        guard let view = anchor?.contentView else { finish(sent: false); return }
        NSApp.activate()
        let picker = NSSharingServicePicker(items: urls)
        self.picker = picker
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        anchor
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(sent: true) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        log.info("sharing ended without sending: \((error as NSError).code, privacy: .public)")
        finish(sent: false)
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? { self }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let service else { finish(sent: false); return }                  // dismissed without a choice
        self.service = service                                                   // its callbacks end the session
    }

    // MARK: Session

    private func begin() {
        isPresenting = true
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        setHold(true)
        anchor = makeAnchor()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.sessionTimeout)
            guard !Task.isCancelled, let self, self.isPresenting else { return }
            log.info("sharing session timed out")
            self.finish(sent: false)
        }
        // A service that never reports back (or a picker choice handled in another app): once Cranny is no longer
        // active and no sheet hangs on the anchor, the user has moved on.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appResignedActive() }               // queue: .main
        }
    }

    private func appResignedActive() {
        guard isPresenting, Self.sessionLooksOver(anchorHasSheet: anchor?.attachedSheet != nil,
                                                  anchorHasChildren: !(anchor?.childWindows ?? []).isEmpty) else { return }
        log.info("sharing ended without a callback")
        finish(sent: false)
    }

    /// Nothing of the share UI is left on the anchor (pure; unit-tested).
    nonisolated static func sessionLooksOver(anchorHasSheet: Bool, anchorHasChildren: Bool) -> Bool {
        !anchorHasSheet && !anchorHasChildren
    }

    private func finish(sent: Bool) {
        guard isPresenting else { return }
        isPresenting = false
        timeoutTask?.cancel()
        timeoutTask = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        service?.delegate = nil
        service = nil
        picker?.delegate = nil
        picker = nil
        anchor?.orderOut(nil)
        anchor = nil
        setHold(false)
        if let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
        airDrop?.resume(returning: sent)
        airDrop = nil
    }

    /// Transparent, borderless, normal level, on screen below the notch of the pointer's display.
    private func makeAnchor() -> NSWindow {
        let shape = shapeFrame()
        let screen = shape.flatMap { shape in NSScreen.screens.first { $0.frame.intersects(shape) } } ?? NSScreen.screens.first
        let window = NSWindow(contentRect: Self.anchorFrame(below: shape, on: screen?.visibleFrame),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true                                        // an anchor, never a target
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.orderFrontRegardless()
        return window
    }

    /// Centred under the shape, kept inside the visible frame (pure; unit-tested).
    nonisolated static func anchorFrame(below shape: CGRect?, on visible: CGRect?) -> CGRect {
        let visible = visible ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let shape = shape ?? CGRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
        var frame = CGRect(x: shape.midX - anchorSize.width / 2, y: shape.minY - Space.l - anchorSize.height,
                           width: anchorSize.width, height: anchorSize.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        frame.origin = CGPoint(x: frame.minX.rounded(), y: frame.minY.rounded())     // whole points, same size
        return frame
    }
}
