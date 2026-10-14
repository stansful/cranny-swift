import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

/// The options look like every other widget's (DESIGN.md §11.3): "Hide completed" is a small switch, not the
/// default checkbox, in both places the options appear — the card's ⋯ popover (padded, no form) and Settings ▸
/// Layout & Widgets (a grouped form, where the default style would be a mini switch). The hosts below mirror those
/// two popovers. Windows are never ordered in and sit far outside every screen.
@MainActor
struct TodosOptionsTests {
    /// The AppKit controls SwiftUI draws for `view`, in an offscreen window.
    private func controls(_ view: some View) async throws -> [NSControl] {
        let host = NSHostingView(rootView: view.crannyThemeRoot(CrannyTheme()))
        host.frame = CGRect(origin: .zero, size: CGSize(width: 340, height: 200))
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 340, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))            // one turn for the platform controls to appear
        host.layoutSubtreeIfNeeded()
        func walk(_ view: NSView) -> [NSControl] {
            ((view as? NSControl).map { [$0] } ?? []) + view.subviews.flatMap(walk)
        }
        return walk(host)
    }

    private func model() -> TodosModel {
        TodosModel.testing([Todo(title: "a", isDone: true), Todo(title: "b")])
    }

    /// A checkbox draws no `NSSwitch` at all; a switch with the default size is `.mini` inside a grouped form.
    private func expectSmallSwitch(in controls: [NSControl]) {
        let switches = controls.compactMap { $0 as? NSSwitch }
        #expect(switches.count == 1)
        #expect(switches.allSatisfy { $0.controlSize == .small })
    }

    @Test func hideCompletedIsASmallSwitchInTheCardPopover() async throws {
        let options = TodosOptions(model: model()).padding(Space.l).frame(minWidth: 220)
        expectSmallSwitch(in: try await controls(options))
    }

    @Test func hideCompletedIsASmallSwitchInSettings() async throws {
        let options = Form {
            Section { TodosOptions(model: model()) } header: { Text(verbatim: "To-dos") }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        expectSmallSwitch(in: try await controls(options))
    }
}
