import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyCore

// MARK: - Hover intent (DESIGN.md §4.6)

@Test func hoverIntentOpensOnlyOnDeliberateDwell() {
    func open(_ dwell: Double, speed: CGFloat = 0, delay: HoverIntent.Delay = .short, button: Bool = false,
              option: Bool = false, drag: Bool = false, fullScreen: Bool = false) -> Bool {
        HoverIntent.shouldOpen(dwell: dwell, pointerSpeed: speed, delay: delay, mouseButtonDown: button,
                               optionHeld: option, isFileDrag: drag, fullScreenSpace: fullScreen)
    }
    #expect(HoverIntent.defaultDelay == .short && HoverIntent.Delay.short.seconds == 0.12)
    #expect(HoverIntent.Delay.allCases.map(\.seconds) == [0, 0.12, 0.22, 0.45])
    #expect(open(0.12))
    #expect(!open(0.11))
    #expect(open(0, delay: .instant))
    #expect(!open(0.3, speed: 1300))                         // passing through toward a menu or another display
    #expect(open(0.3, speed: 1200))
    #expect(!open(0.3, button: true))                        // never while a mouse button is down
    #expect(!open(0.3, option: true))                        // hold ⌥ to pass over
    #expect(open(0, speed: 5000, button: true, drag: true))  // a file drag opens without dwell
    #expect(!open(0.3, fullScreen: true))                    // full-screen Space: ≥ 0.40 s
    #expect(open(0.40, fullScreen: true))
    #expect(open(0.45, delay: .long, fullScreen: true))
    #expect(!open(0.42, delay: .long, fullScreen: true))
}

// MARK: - Swipes (DESIGN.md §4.4)

private func sample(_ phase: SwipePhase, dx: CGFloat = 0, dy: CGFloat = 0, at t: TimeInterval,
                    momentum: Bool = false, precise: Bool = true) -> ScrollSample {
    ScrollSample(phase: phase, isMomentum: momentum, deltaX: dx, deltaY: dy, isPrecise: precise,
                 isInvertedFromDevice: true, timestamp: t)
}

@Test func swipeReleasedShortSnapsBack() {
    var t = SwipeTracker(axis: .any)
    _ = t.handle(sample(.began, at: 0))
    #expect(t.handle(sample(.changed, dy: 5, at: 0.016)) == .tracking(.vertical, translation: 5))
    #expect(t.handle(sample(.changed, dy: 5, at: 0.4)) == .tracking(.vertical, translation: 10))
    #expect(t.handle(sample(.ended, at: 0.5)) == .cancelled)               // 10 pt < 24, slow: snap back
}

@Test func swipeDownCommitsAtPullOpenDistance() {
    var t = SwipeTracker(axis: .any)
    _ = t.handle(sample(.began, at: 0))
    var updates: [SwipeUpdate] = []
    for i in 1...6 { if let u = t.handle(sample(.changed, dy: 5, at: Double(i) * 0.016)) { updates.append(u) } }
    #expect(updates.contains { if case .committed(.down, _) = $0 { true } else { false } })   // 25 ≥ 24
    #expect(t.handle(sample(.ended, at: 0.2)) == nil)                       // already committed once
}

@Test func swipeIgnoresMomentumWheelsAndLocksTheAxis() {
    var t = SwipeTracker(axis: .horizontal)
    #expect(t.handle(sample(.changed, dx: 50, at: 0, momentum: true)) == nil)  // fingers already lifted
    #expect(t.handle(sample(.changed, dx: 50, at: 0, precise: false)) == nil)  // a mouse wheel never forms a gesture
    _ = t.handle(sample(.began, at: 0))
    #expect(t.handle(sample(.changed, dx: 3, dy: 3, at: 0.016)) == nil)        // no axis yet (diagonal)
    #expect(t.handle(sample(.changed, dy: 30, at: 0.032)) == nil)              // vertical never locks a horizontal tracker
}

// MARK: - Zones (ARCHITECTURE.md §3.10)

@MainActor @Test func dropZonesHitTestInnermostAcceptingZone() async {
    let zones = NotchZones()
    var received: [DropZoneID] = []
    func zone(_ id: DropZoneID, _ frame: CGRect, _ types: [UTType]) -> NotchZones.DropZone {
        .init(id: id, frame: frame, accepts: types, perform: { _ in received.append(id); return true })
    }
    zones.setDropZone(zone(.trayKeep, CGRect(x: 0, y: 0, width: 600, height: 200), [.item]))
    zones.setDropZone(zone(.airDrop, CGRect(x: 10, y: 10, width: 100, height: 100), [.fileURL]))
    zones.setDropZone(zone("pipeline.images", CGRect(x: 120, y: 10, width: 100, height: 100), [.image]))

    zones.dragUpdated(at: CGPoint(x: 50, y: 50), types: [.fileURL])
    #expect(zones.armedDropZone == .airDrop)                                    // innermost wins
    zones.dragUpdated(at: CGPoint(x: 150, y: 50), types: [.fileURL])
    #expect(zones.armedDropZone == .trayKeep)                                   // pipeline does not accept plain files
    zones.dragUpdated(at: CGPoint(x: 150, y: 50), types: [.png])
    #expect(zones.armedDropZone == "pipeline.images")                          // .png conforms to .image
    zones.dragUpdated(at: CGPoint(x: 900, y: 50), types: [.png])
    #expect(zones.armedDropZone == nil)

    let payload = DropPayload(fileURLs: [URL(fileURLWithPath: "/tmp/a.png")], contentTypes: [.png])
    #expect(await zones.performDrop(payload))                                   // nothing armed → fallback .trayKeep
    #expect(received == [.trayKeep])
    #expect(zones.draggedTypes.isEmpty && zones.armedDropZone == nil)
    zones.removeDropZone(.trayKeep)
    #expect(await zones.performDrop(payload) == false)                          // nobody took it: shell asks TrayIntake
}

@MainActor @Test func scrollZonesConsumeOnlyUnderThePointer() {
    let zones = NotchZones()
    var updates: [SwipeUpdate] = []
    zones.setScrollZone(.init(id: "timer.scroll", frame: CGRect(x: 0, y: 0, width: 100, height: 100), axis: .vertical,
                              onUpdate: { updates.append($0) }))
    #expect(zones.scroll(sample(.began, at: 0), at: CGPoint(x: 300, y: 10)) == false)
    #expect(zones.scroll(sample(.began, at: 0), at: CGPoint(x: 50, y: 50)))
    #expect(zones.scroll(sample(.changed, dy: 6, at: 0.016), at: CGPoint(x: 50, y: 50)))
    #expect(updates == [.tracking(.vertical, translation: 6)])
    zones.removeScrollZone("timer.scroll")
    #expect(zones.scroll(sample(.began, at: 1), at: CGPoint(x: 50, y: 50)) == false)
}
