// CrannySettingsUI/Components/UndoBanner.swift — the 10-s Undo offer after "Reset All Settings…" (DESIGN.md §11.3),
// floating at the bottom of the window. ⌘Z works while it is visible; VoiceOver hears it once.
import CrannyCore
import Foundation
import SwiftUI

struct UndoBanner: View {
    let controller: ResetAllController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("All settings were reset.", bundle: .module, comment: "Settings: banner after Reset All Settings")
            Button {
                controller.undo()
            } label: {
                Text("Undo", bundle: .module, comment: "Settings: banner button that restores the settings before Reset All")
            }
            .keyboardShortcut("z", modifiers: .command)
            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Dismiss", bundle: .module, comment: "Settings: close button of the Reset All banner (VoiceOver)"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(
                String(localized: "All settings were reset. Undo is available for 10 seconds.", bundle: .module,
                       comment: "Settings: VoiceOver announcement after Reset All Settings")).post()
        }
    }
}

#Preview("Undo banner") {
    let services = CrannyServices.preview()
    UndoBanner(controller: ResetAllController(settings: services.settings, app: services.app))
        .padding(40)
}
