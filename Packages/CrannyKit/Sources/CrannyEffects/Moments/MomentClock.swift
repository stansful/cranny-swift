// CrannyEffects/Moments/MomentClock.swift — the clock of a one-shot delight moment (DESIGN.md §5.5, §5.6 rule 6):
// frames at 1/30 s on AC or 1/20 s on battery from `EffectClock`, only for the moment's lifetime; then the clock
// stops, the last frame stays, and `onFinished` tells the caller to remove the view.
import CrannyCore
import Foundation
import SwiftUI

struct MomentClock<Content: View>: View {
    let duration: Double
    let interval: Double
    let onFinished: (() -> Void)?
    @ViewBuilder let content: (_ elapsed: Double) -> Content

    @State private var start = Date()
    @State private var isFinished = false

    var body: some View {
        EffectClock(minimumInterval: isFinished ? nil : interval) { date in
            content(isFinished ? duration : Self.elapsed(from: start, to: date, duration: duration))
        }
        .task {
            start = Date()
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return                                                      // removed early: nothing to report
            }
            isFinished = true
            onFinished?()
        }
    }

    /// Seconds since `start`, clamped to 0…duration.
    nonisolated static func elapsed(from start: Date, to date: Date, duration: Double) -> Double {
        min(max(date.timeIntervalSince(start), 0), duration)
    }
}

/// A static Reduce Motion variant: shows `content` for the moment's lifetime, fading in and out with the light's
/// `ambientIn` / `ambientOut` tokens (opacity only, no movement), then reports the end.
struct ReducedMoment<Content: View>: View {
    let duration: Double
    let onFinished: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.cranny) private var theme
    @State private var isShown = false

    var body: some View {
        content()
            .opacity(isShown ? 1 : 0)
            .task {
                withAnimation(theme.animation(.ambientIn)) { isShown = true }
                do {
                    try await Task.sleep(for: .seconds(max(duration - Self.fadeOut, 0)))
                    withAnimation(theme.animation(.ambientOut)) { isShown = false }
                    try await Task.sleep(for: .seconds(Self.fadeOut))
                } catch {
                    return
                }
                onFinished?()
            }
    }

    /// `ambientOut` lasts 0.2 s with and without Reduce Motion (DESIGN.md §4.1–§4.2).
    private static var fadeOut: Double { 0.2 }
}
