// CrannyOnboarding/Components/ProgressDots.swift — where you are in the Welcome window: one dot per visible
// step, the current one stretched into a capsule. VoiceOver reads "Step 2 of 6" (DESIGN.md §12.1).
import CrannyCore
import Foundation
import SwiftUI

struct ProgressDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 1-based.
    let current: Int
    let count: Int

    private static let dot: CGFloat = Space.s
    private static let currentWidth: CGFloat = Space.xxl

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(1...max(count, 1), id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? Self.currentWidth : Self.dot, height: Self.dot)
            }
        }
        .animation(CrannyMotion.animation(.tabIndicator, reduceMotion: reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(current: current, count: count)))
    }

    /// "Step 2 of 6" (DESIGN.md §12.1); `bundle` picks a localization in tests.
    static func label(current: Int, count: Int, bundle: Bundle = .module) -> String {
        String(localized: "Step \(current) of \(count)", bundle: bundle, comment: "Welcome: VoiceOver label of the progress dots")
    }
}

#Preview("Progress · 2 of 6") {
    VStack(spacing: Space.l) {
        ProgressDots(current: 2, count: 6)
        ProgressDots(current: 5, count: 5)
    }
    .padding(Space.xxl)
}
