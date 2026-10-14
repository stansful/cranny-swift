// Hosts a view in an off-screen, never-shown window so SwiftUI runs its real update cycle (onAppear,
// onDisappear, @State) — what ImageRenderer's single frame cannot show. No input is posted and the window is
// never ordered in, so nothing appears on the user's screen.
import AppKit
import CrannyCore
import SwiftUI
@testable import CrannyNotchUI

@MainActor final class Hosted<Root: View> {
    let host: NSHostingView<Root>
    private let window: NSWindow

    init(_ root: Root, size: CGSize) {
        host = NSHostingView(rootView: root)
        window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        settle()
    }

    /// Lets SwiftUI apply pending changes (observation, onAppear/onChange, tasks scheduled for the next turn).
    func settle(_ seconds: Double = 0.15) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
    }

    /// The view as drawn right now (mid-animation included), at the window's backing scale.
    func frame() -> ShapeProbe? {
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return ShapeProbe(image, scale: CGFloat(rep.pixelsWide) / max(host.bounds.width, 1))
    }

    /// Offers a key equivalent to the hosted view the way the window would (an in-process call: nothing is
    /// posted to the system). Returns whether a view handled it.
    @discardableResult func keyEquivalent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
        else { return false }
        let handled = host.performKeyEquivalent(with: event)
        settle(0.05)
        return handled
    }

    func tearDown() {
        window.contentView = nil
        window.close()
    }
}

/// A notch canvas with a lifecycle probe, for identity tests.
@MainActor func hostedCanvas(_ model: NotchSceneModel, _ registry: ModuleRegistry, actions: NotchUIActions = NotchUIActions(),
                             backdrop: Color = .clear) -> (Hosted<some View>, NotchLifecycleProbe) {
    let probe = NotchLifecycleProbe()
    let size = model.layout.canvasSize
    let root = NotchCanvasView(model: model, registry: registry, actions: actions)
        .environment(\.notchLifecycleProbe, probe)
        .frame(width: size.width, height: size.height)
        .background(backdrop)
    return (Hosted(root, size: size), probe)
}


/// A child that reports every new instance (for modifier identity tests).
struct InstanceCounter: View {
    let probe: NotchLifecycleProbe
    var body: some View {
        Rectangle().frame(width: 40, height: 10)
            .onAppear { probe.record("instance.appear") }
            .onDisappear { probe.record("instance.disappear") }
    }
}

/// An observable flag that a hosted root reads, so a test can flip it between updates.
@MainActor @Observable final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// Hosts `InstanceCounter` inside `modifier(flag)`, so a test can flip the flag and count instances.
struct ModifiedCounter<M: ViewModifier>: View {
    let flag: Flag
    let probe: NotchLifecycleProbe
    let modifier: (Bool) -> M
    var body: some View { InstanceCounter(probe: probe).modifier(modifier(flag.value)) }
}

/// A live activity whose VoiceOver value comes and goes; its leading wing reports every new instance.
@MainActor @Observable final class ToggleActivity: LiveActivity {
    let id: ActivityID
    let isActive = true
    let priority: ActivityPriority = .ongoing
    let slot: SlotWidth = .short
    let revision = 0
    var value: String?
    @ObservationIgnored let probe: NotchLifecycleProbe
    init(id: ActivityID, probe: NotchLifecycleProbe) { self.id = id; self.probe = probe }
    var accessibilityLabel: String { "Toggle" }
    var accessibilityValue: String? { value }
    func compactLeading() -> some View { InstanceCounter(probe: probe) }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { InstanceCounter(probe: probe) }
}

/// A widget whose body reports every new instance.
@MainActor final class ProbeWidget: NookWidget {
    let id: WidgetID
    let title = "Probe"
    let symbol = "timer"
    let summary = ""
    let sizes: WidgetSizes
    let probe: NotchLifecycleProbe
    init(_ id: WidgetID, sizes: WidgetSizes, probe: NotchLifecycleProbe) { self.id = id; self.sizes = sizes; self.probe = probe }
    func makeBody(context: WidgetContext) -> some View { InstanceCounter(probe: probe) }
}
