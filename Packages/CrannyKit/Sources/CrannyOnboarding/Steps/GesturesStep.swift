// CrannyOnboarding/Steps/GesturesStep.swift — step 3 (DESIGN.md §12.1), shown only with a trackpad: a practice
// notch on the stage with live rubber-banding and haptics. Pull down to open; swipe sideways to change the
// track, practised only while something plays. Practice never reaches real media.
import CrannyCore
import Foundation
import SwiftUI

struct GesturesStep: View {
    let flow: WelcomeFlow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "Try a gesture", bundle: .module, comment: "Welcome step 3: headline"),
                       message: String(localized: "Put two fingers on the trackpad and swipe over the notch above. It’s only practice.",
                                       bundle: .module, comment: "Welcome step 3: sentence under the headline"))
            VStack(alignment: .leading, spacing: Space.m) {
                PracticeRow(isDone: flow.pulledDown,
                            text: String(localized: "Pull down to open", bundle: .module, comment: "Welcome step 3: practice task (two-finger swipe down)"))
                if flow.practisesTrackSwipe {
                    PracticeRow(isDone: flow.swipedSideways,
                                text: String(localized: "Swipe sideways to change the track", bundle: .module,
                                             comment: "Welcome step 3: practice task (two-finger swipe left or right)"))
                }
                PracticeRow(isDone: nil,
                            text: String(localized: "Push up to close it again", bundle: .module, comment: "Welcome step 3: optional practice hint (two-finger swipe up)"))
            }
        }
    }
}

/// A practice task with its ✓ (nil = a hint without a check).
private struct PracticeRow: View {
    let isDone: Bool?
    let text: String

    var body: some View {
        HStack(spacing: Space.m) {
            if let isDone {
                CheckBadge(isDone: isDone)
            } else {
                Image(systemName: "circle").font(.system(size: Space.xl, weight: .medium)).foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text).foregroundStyle(isDone == nil ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: isDone == true
            ? OnboardingCopy.done : ""))
    }
}

#Preview("Step 3 · Gestures") {
    WelcomePreview(step: .gestures)
}
