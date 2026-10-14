// CrannyTodos/UI/TodoMotes.swift — Lively's six motes around a freshly checked circle (DESIGN.md §5.5), drawn
// in a local Canvas from `TodoMote` (stateless: position, size and opacity are functions of progress). The
// keyframe animation runs only for 0.6 s after a check; at rest nothing is drawn and nothing ticks.
import CrannyCore
import SwiftUI

struct TodoMotesBurst: View {
    /// Changes once per completion; each change plays the burst from the start.
    let trigger: Int
    let color: Color
    let seed: UInt64
    /// The circle's radius: motes start at its edge.
    let startRadius: CGFloat

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: 1.0, trigger: trigger) { _, progress in
                TodoMotes(progress: progress, color: color, seed: seed, startRadius: startRadius)
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: TodoDelightTiming.motes)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TodoMotes: View {
    let progress: Double
    let color: Color
    let seed: UInt64
    let startRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            guard progress > 0, progress < 1 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<TodoMote.count {
                let mote = TodoMote(index: index, seed: seed)
                let offset = mote.offset(at: progress, startRadius: startRadius)
                let r = mote.radius(at: progress)
                let rect = CGRect(x: center.x + offset.width - r, y: center.y + offset.height - r, width: 2 * r, height: 2 * r)
                context.opacity = mote.opacity(at: progress)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}

#Preview("Motes · mid-burst") {
    HStack(spacing: Space.xxl) {
        ForEach([0.1, 0.3, 0.6], id: \.self) { progress in
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 16, height: 16)
                TodoMotes(progress: progress, color: .accentColor, seed: 42, startRadius: 8).frame(width: 48, height: 48)
            }
        }
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
