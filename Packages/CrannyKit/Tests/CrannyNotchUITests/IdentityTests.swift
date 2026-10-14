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
