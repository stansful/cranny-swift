// CrannyTodos/UI/TodoCheckbox.swift — the 16-pt circle (1.5-pt `stroke`); checked = accent fill with a black
// check that draws itself (DESIGN.md §7.6, §5.5). Lively adds six motes. Decorative for VoiceOver: the row is
// the toggle.
import CrannyCore
import SwiftUI

struct TodoCheckbox: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    @State private var burst = 0
    let isDone: Bool
    let style: TodoCheckStyle
    let metrics: TodoMetrics
    /// Seeds the motes, so the same to-do always bursts the same way.
    let seed: UInt64
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(hovered ? p.tertiaryLabel : p.stroke, lineWidth: metrics.circleLine)
                    .opacity(isDone ? 0 : 1)
                Circle()
                    .fill(theme.accentColor)
                    .scaleEffect(isDone || theme.reduceMotion ? 1 : 0.5)
                    .opacity(isDone ? 1 : 0)
                TodoCheckmark()
                    .trim(from: 0, to: isDone ? 1 : 0)
                    .stroke(theme.accent.onColor.color,
                            style: StrokeStyle(lineWidth: metrics.checkLine, lineCap: .round, lineJoin: .round))
            }
            .frame(width: metrics.circle, height: metrics.circle)
            .overlay {
                if style == .drawWithMotes {
                    TodoMotesBurst(trigger: burst, color: theme.accentColor, seed: seed, startRadius: metrics.circle / 2)
                        .frame(width: metrics.circle * 3, height: metrics.circle * 3)
                }
            }
            .todoHitArea(CGSize(width: metrics.circle, height: metrics.circle))
        }
        .buttonStyle(TodoCheckboxButtonStyle())
        .onHover { hovered = $0 }
        .animation(style.animation, value: isDone)
        .animation(theme.animation(.hover), value: hovered)
        .onChange(of: isDone) { wasDone, done in
            if done && !wasDone && style == .drawWithMotes { burst += 1 }
        }
        .accessibilityHidden(true)
    }
}

/// No chrome: the circle is the control. Pressed = scale 0.94 (`press`), opacity under Reduce Motion.
private struct TodoCheckboxButtonStyle: ButtonStyle {
    @Environment(\.cranny) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed && theme.reduceMotion ? 0.7 : 1)
            .animation(theme.animation(.press), value: configuration.isPressed)
    }
}

/// The check inside the circle, as one open path so `trim` draws it from the short stroke to the long one. A check
/// mark is not mirrored right to left (like the `checkmark` symbol); a custom `Shape` would be.
nonisolated struct TodoCheckmark: Shape {
    var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.35))
        return path
    }
}

#Preview("Checkbox · states") {
    @Previewable @State var done = false
    let metrics = TodoMetrics(textSize: .standard)
    HStack(spacing: Space.l) {
        TodoCheckbox(isDone: false, style: .draw, metrics: metrics, seed: 1) {}
        TodoCheckbox(isDone: true, style: .draw, metrics: metrics, seed: 2) {}
        TodoCheckbox(isDone: done, style: .drawWithMotes, metrics: metrics, seed: 3) { done.toggle() }
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
