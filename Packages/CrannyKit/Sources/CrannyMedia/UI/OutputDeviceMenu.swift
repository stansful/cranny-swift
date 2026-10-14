// CrannyMedia/UI/OutputDeviceMenu.swift — the ⌁ route menu in the widget's title row (DESIGN.md §7.1:
// `airplayaudio`, tertiary, 12): lists the Mac's outputs with a check on the current one. The list is read when
// the widget appears and when the pointer enters the icon, so it is current when the menu opens (an NSMenu tracking
// session also holds the panel open, ARCHITECTURE.md §4.5). The reads (Core Audio IPC, ≈ 3 per device) run off the
// main actor, one at a time: a request during a read reads once more after it.
import AppKit
import CoreAudio
import CrannyCore
import SwiftUI

struct OutputDeviceMenu: View {
    @Environment(\.cranny) private var theme
    @State private var devices: [OutputDevice] = []
    @State private var current: AudioObjectID?
    /// A read is on its way …
    @State private var isReading = false
    /// … and another was asked for meanwhile (the list may have changed since that read began).
    @State private var readsAgain = false

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Toggle(isOn: Binding(get: { device.id == current },
                                     set: { if $0 { OutputDevices.setDefaultOutput(device.id); current = device.id } })) {
                    Text(verbatim: device.name)
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.palette.tertiaryLabel)
                .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Self.title)
        .accessibilityLabel(Text(verbatim: Self.title))
        .onAppear(perform: reload)
        .onHover { if $0 { reload() } }
    }

    private func reload() {
        guard !isReading else { readsAgain = true; return }
        isReading = true
        Task {
            repeat {
                readsAgain = false
                let read = await OutputDevices.read()
                if devices != read.devices { devices = read.devices }
                if current != read.current { current = read.current }
            } while readsAgain
            isReading = false
        }
    }

    static var title: String {
        String(localized: "Sound output", bundle: .module, comment: "Media widget: tooltip and VoiceOver label of the output device menu")
    }
}

#Preview("Output menu") {
    OutputDeviceMenu()
        .padding(Space.xxl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
