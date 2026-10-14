// CrannyOnboarding/Steps/OpenItStep.swift — step 2 (DESIGN.md §12.1): Hover (with delay presets), Click or
// Shortcut only. Choosing writes `CoreSettings.openMode` at once; a ✓ appears on a card only when the REAL notch
// opened that way (the coach mark under the notch says where to aim).
import CrannyCore
import Foundation
import SwiftUI

struct OpenItStep: View {
    let flow: WelcomeFlow

    static let cardHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "Open it your way", bundle: .module, comment: "Welcome step 2: headline"),
                       message: String(localized: "Choose how Cranny opens, then try it on the real notch at the top of your screen.",
                                       bundle: .module, comment: "Welcome step 2: sentence under the headline"))
            HStack(spacing: Space.m) {
                ForEach(OpenMethod.allCases, id: \.self) { method in
                    OpenMethodCard(method: method, isSelected: flow.openMethod == method,
                                   isDetected: flow.detected.contains(method)) { flow.choose(method) }
                        .overlay(alignment: .bottomLeading) { accessory(for: method) }
                }
            }
            .frame(height: Self.cardHeight)
        }
    }

    /// The bottom line of a card: Hover's delay, Shortcut only's key cap. Outside the card's button, so each
    /// is its own control.
    @ViewBuilder private func accessory(for method: OpenMethod) -> some View {
        switch method {
        case .hover:
            Picker(selection: Binding(get: { flow.hoverDelay }, set: { flow.setHoverDelay($0) })) {
                ForEach(HoverIntent.Delay.allCases, id: \.self) { delay in
                    Text(verbatim: Self.title(delay)).tag(delay)
                }
            } label: {
                Text("Delay", bundle: .module, comment: "Welcome step 2: hover delay picker label")
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .padding(Space.l)
        case .click:
            EmptyView()
        case .shortcut:
            if let keys = flow.openShortcut {
                WindowKeyCap(keys).padding(Space.l)
            }
        }
    }

    /// Delay names with their values (DESIGN.md §11.1: Instant 0 · Short 120 ms · Standard 220 · Long 450).
    static func title(_ delay: HoverIntent.Delay) -> String {
        let milliseconds = Measurement(value: delay.seconds * 1000, unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return switch delay {
        case .instant: String(localized: "Instant", bundle: .module, comment: "Welcome step 2: hover delay preset (no delay)")
        case .short: String(localized: "Short, \(milliseconds)", bundle: .module, comment: "Welcome step 2: hover delay preset; argument is a duration such as 120 ms")
        case .standard: String(localized: "Standard, \(milliseconds)", bundle: .module, comment: "Welcome step 2: hover delay preset; argument is a duration such as 220 ms")
        case .long: String(localized: "Long, \(milliseconds)", bundle: .module, comment: "Welcome step 2: hover delay preset; argument is a duration such as 450 ms")
        }
    }
}

/// One way in: glyph, name, one line, and a ✓ once the real notch opened that way.
private struct OpenMethodCard: View {
    let method: OpenMethod
    let isSelected: Bool
    let isDetected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(height: Space.xxxl, alignment: .leading)
                    Spacer(minLength: 0)
                    CheckBadge(isDone: isDetected)
                }
                Text(verbatim: title).font(.headline)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
        }
        .buttonStyle(SelectableCardStyle(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: isDetected
            ? String(localized: "Tried on the notch", bundle: .module, comment: "Welcome step 2: VoiceOver value of a card whose way in was used")
            : ""))
        .accessibilityHint(Text(verbatim: subtitle))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// DESIGN.md §14.1 (+ `cursorarrow.click`, macOS 11; listed as a §14.1 addition in the WP15 report).
    private var symbol: String {
        switch method {
        case .hover: "cursorarrow.motionlines"
        case .click: "cursorarrow.click"
        case .shortcut: "keyboard"
        }
    }

    private var title: String {
        switch method {
        case .hover: String(localized: "Hover", bundle: .module, comment: "Welcome step 2: way to open Cranny (rest the pointer on the notch)")
        case .click: String(localized: "Click", bundle: .module, comment: "Welcome step 2: way to open Cranny")
        case .shortcut: String(localized: "Shortcut only", bundle: .module, comment: "Welcome step 2: way to open Cranny (only the keyboard shortcut)")
        }
    }

    private var subtitle: String {
        switch method {
        case .hover: String(localized: "Rest the pointer on the notch", bundle: .module, comment: "Welcome step 2: Hover card description")
        case .click: String(localized: "Click the notch to open it", bundle: .module, comment: "Welcome step 2: Click card description")
        case .shortcut: String(localized: "Opens only with the keys", bundle: .module, comment: "Welcome step 2: Shortcut only card description")
        }
    }
}

#Preview("Step 2 · Open it your way") {
    WelcomePreview(step: .openIt, detected: [.hover])
}
