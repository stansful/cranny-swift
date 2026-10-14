// View identity across changes of presentation (DESIGN.md §3.4 "the first frame of any morph grows out of the
// camera", §4.3, §16). A view that is re-created instead of updated cannot morph (the new instance starts at its
// final size) and drops its @State, focus and VoiceOver cursor. ImageRenderer's single frame cannot see this, so
// these tests host the canvas in an off-screen window and count appearances. They spin the main run loop, so
// they run one at a time, under one serialized parent suite.
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

/// Every test that hosts a view in a window (one at a time).
@MainActor @Suite("Hosted views", .serialized) struct HostedTests {}

extension HostedTests {
    @MainActor @Suite("View identity (hosted, off-screen)") struct IdentityTests {
        @Test func theSurfaceMorphsThroughEveryPhase() {
            let (model, registry) = previewScene(.idle)
            let (hosted, probe) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            #expect(probe.appearances(of: "surface") == 1)
            // Hover open, close, the drop, peek, open from a peek, close to compact, activity out.
            let steps: [(NotchPhase, (NotchSceneModel) -> Void)] = [
                (.breath, { _ in }),
                (.open, { $0.open = OpenState(page: .nook, reason: .hover) }),
                (.idle, { $0.open = nil }),
                (.compact, { $0.primary = .nowPlaying; $0.primarySlot = .short }),
                (.peek, { $0.peekRows = [.nowPlaying] }),
                (.open, { $0.open = OpenState(page: .nook, reason: .click) }),
                (.compact, { $0.open = nil }),
                (.idle, { $0.primary = nil }),
            ]
            for (phase, configure) in steps {
                configure(model)
                model.phase = phase
                hosted.settle()
                #expect(probe.appearances(of: "surface") == 1, "surface re-created on → \(phase)")
            }
            #expect(probe.disappearances(of: "surface") == 0)
            #expect(probe.appearances(of: "light") == 1, "the light's frame moves with the shape in every phase")
        }

        /// Reduce Motion: a resize does not travel, but the open panel stays the same view, so keyboard focus, a
        /// handle drag and the VoiceOver cursor survive every ⌥⇧← / ⌥⇧→, tab of another width and Notes focus.
        @Test(arguments: [false, true]) func theOpenPanelSurvivesResizes(reduceMotion: Bool) {
            let (model, registry) = previewScene(.open)
            var theme = model.theme
            theme.reduceMotion = reduceMotion
            model.theme = theme
            let (hosted, probe) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            #expect(probe.appearances(of: "nook") == 1)
            model.open?.mode = .editLayout
            hosted.settle()
            for columns in [11, 12, 9, 10] {
                model.openColumns = columns                                   // the owner follows commitLayout
                hosted.settle()
            }
            model.open?.mode = .focus(.notes)
            hosted.settle()
            model.open?.mode = .grid
            hosted.settle()
            #expect(probe.appearances(of: "nook") == 1, "the open panel was re-created by a resize")
            #expect(probe.appearances(of: "surface") == 1)
        }
    }

    /// Accessibility modifiers whose input comes and goes are applied in every state, so the view they wrap
    /// is updated, never re-created (review: the band row replayed its entrance when a value appeared, the Tray
    /// tab lost its hover state when the count went from 0 to 1).
    @MainActor @Suite("Conditional accessibility keeps identity") struct ModifierIdentityTests {
        private func flips<M: ViewModifier>(_ modifier: @escaping (Bool) -> M) -> Int {
            let flag = Flag(false)
            let probe = NotchLifecycleProbe()
            let hosted = Hosted(ModifiedCounter(flag: flag, probe: probe, modifier: modifier), size: CGSize(width: 100, height: 40))
            defer { hosted.tearDown() }
            for value in [true, false, true] {
                flag.value = value
                hosted.settle(0.05)
            }
            return probe.appearances(of: "instance")
        }

        @Test func collapsedNotch() {
            #expect(flips { CollapsedAccessibility(isCollapsed: $0, open: {}) } == 1)
        }

        @Test func tabBadge() {
            #expect(flips { BadgeValue(count: $0 ? 3 : nil) } == 1)
        }

        @Test func shortcutHint() {
            #expect(flips { ShortcutHint(shortcut: $0 ? NookKeyMap.palette : nil) } == 1)
        }

        @Test func wiggleOnAndOff() {
            #expect(flips { Wiggle(index: 2, isActive: $0) } == 1)
        }

        @Test(arguments: [NotchPhase.compact, .peek]) func activityValueComesAndGoes(phase: NotchPhase) {
            let (model, registry) = previewScene(phase)
            let probe = NotchLifecycleProbe()
            let activity = ToggleActivity(id: .nowPlaying, probe: probe)
            model.sampleActivities[.nowPlaying] = activity
            let (hosted, _) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            let initial = probe.appearances(of: "instance")
            #expect(initial >= 1)
            for value in ["2 minutes left", nil, "1 minute left", ""] {
                activity.value = value
                hosted.settle(0.05)
            }
            #expect(probe.appearances(of: "instance") == initial, "the activity's views were re-created")
        }
    }

    /// The layout editor's cards are not re-created by the wiggle's clock, by the clock pausing (occluded) or
    /// resuming, so a drag in flight survives (review: the first handle event re-created every card).
    @MainActor @Suite("Layout editor identity") struct EditorIdentityTests {
        @Test func cardsSurviveTheWiggleClock() {
            let (model, registry) = previewScene(.open, mode: .editLayout)
            let probe = NotchLifecycleProbe()
            registry.add(widget: ProbeWidget(.media, sizes: WidgetSizes(minimum: 4, preferred: 5, maximum: 6), probe: probe))
            let (hosted, _) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            hosted.settle(0.3)                                             // ~9 wiggle frames at 30 fps
            #expect(probe.appearances(of: "instance") == 1)
            model.isVisibleOnScreen = false                                // occluded: the clock pauses
            hosted.settle(0.1)
            model.isVisibleOnScreen = true
            hosted.settle(0.2)
            #expect(probe.appearances(of: "instance") == 1, "a wiggle frame or pause re-created the card")
        }
    }

    @MainActor @Suite("Morph frames (hosted, off-screen)") struct MorphFrameTests {
        /// While the shape grows out of the camera, nothing of the open panel may be drawn below the shape's current
        /// bottom edge: no keyline, no underglow layer, no surface instance at its final size (DESIGN.md §3.4, §4.3).
        @Test func nothingOfTheOpenShapeIsDrawnAheadOfTheMorph() throws {
            let (model, registry) = previewScene(.idle)
            var theme = model.theme
            theme.ambience = .off                                   // only the shape, its keyline and its shadow
            model.theme = theme
            let backdrop = 0.25
            let (hosted, _) = hostedCanvas(model, registry, backdrop: Color(white: backdrop))
            defer { hosted.tearDown() }
            model.open = OpenState(page: .nook, reason: .click)
            model.phase = .open
            var frames = 0
            var ghosts: [String] = []
            let start = Date()
            // As many frames as the machine allows through the open spring (0.42 s), at least four.
            while Date().timeIntervalSince(start) < 5, frames < 4 || Date().timeIntervalSince(start) < 0.9 {
                guard let rep = hosted.frame() else { continue }
                frames += 1
                let centre = rep.width / 2
                // The fill's bottom edge on the centre column (the shape is pure black there).
                guard let bottom = (0..<rep.height).last(where: { rep.luminance(x: centre, y: $0) < 0.05 }) else { continue }
                let below = bottom + Int(3 * rep.scale)
                for y in stride(from: below, to: rep.height, by: 2) {
                    if let x = (0..<rep.width).first(where: { rep.luminance(x: $0, y: y) > backdrop + 0.04 }) {
                        ghosts.append("light pixel at (\(x), \(y)) below the bottom edge \(bottom)")
                        break
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            #expect(ghosts.isEmpty, "\(ghosts.prefix(3))")
        }
    }
}
