// CrannySettingsUI/Stage/SimulateChips.swift — the Simulate chips (DESIGN.md §11.2): Song change · Timer · Meeting ·
// Volume · Drop file. Each plays a short script on the stage once; the playing chip is drawn prominent.
import CrannyCore
import Foundation
import SwiftUI

struct SimulateChips: View {
    let controller: StageController

    var body: some View {
        HStack(spacing: 6) {
            Text("Simulate", bundle: .module, comment: "Settings preview stage: label before the Simulate chips")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(controller.availableChips) { chip in
                let label = Label {
                    Text(verbatim: chip.title)
                } icon: {
                    Image(systemName: chip.symbol)
                }
                Button { controller.simulate(chip) } label: { label }
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .modifier(ChipStyle(isPlaying: controller.playing == chip))
                    .accessibilityLabel(Text("Simulate \(chip.title)", bundle: .module,
                                             comment: "Settings preview stage: VoiceOver label of a Simulate chip; the argument is the chip name"))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The same chips folded into a menu when the row is too narrow.
struct SimulateMenu: View {
    let controller: StageController

    var body: some View {
        Menu {
            ForEach(controller.availableChips) { chip in
                Button { controller.simulate(chip) } label: {
                    Label { Text(verbatim: chip.title) } icon: { Image(systemName: chip.symbol) }
                }
            }
        } label: {
            Text("Simulate", bundle: .module, comment: "Settings preview stage: label before the Simulate chips")
        }
        .controlSize(.small)
        .fixedSize()
    }
}

private struct ChipStyle: ViewModifier {
    let isPlaying: Bool
    func body(content: Content) -> some View {
        if isPlaying {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension SimulateChip {
    var title: String {
        switch self {
        case .songChange: String(localized: "Song change", bundle: .module, comment: "Settings preview stage: Simulate chip")
        case .timer: String(localized: "Timer", bundle: .module, comment: "Settings: the Timer feature (widget, Simulate chip; glossary: Таймер)")
        case .meeting: String(localized: "Meeting", bundle: .module, comment: "Settings preview stage: Simulate chip")
        case .volume: String(localized: "Volume", bundle: .module, comment: "Settings preview stage: Simulate chip")
        case .dropFile: String(localized: "Drop file", bundle: .module, comment: "Settings preview stage: Simulate chip")
        }
    }

    /// DESIGN.md §14.1 symbols.
    var symbol: String {
        switch self {
        case .songChange: "music.note"
        case .timer: "timer"
        case .meeting: "calendar"
        case .volume: "speaker.wave.3.fill"
        case .dropFile: "tray.and.arrow.down.fill"
        }
    }
}

#Preview("Simulate chips") {
    let registry = ModuleRegistry(services: .preview())
    SimulateChips(controller: StageController(registry: registry, state: .closed))
        .padding()
}
