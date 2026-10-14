// CrannyMedia/UI/MediaSettingsPane.swift — Settings ▸ Media (DESIGN.md §11.1, ARCHITECTURE.md §6.7): source status +
// Test media detection, visualizer mode (Live behind a why-sheet), browser media, ignored apps, artwork in
// compact, peek on track change, Apple Events fallback. System controls (`Form`, `.grouped`); a changed value
// shows a 6-pt accent dot and every row has "Reset to Default" (§11.3). No "source priority": macOS exposes only
// the system's current now-playing app (R2 §9.6).
import CrannyCore
import Foundation
import SwiftUI

struct MediaSettingsPane: View {
    let service: MediaService
    let health: BridgeHealthMonitor
    let services: CrannyServices
    @State private var askingForLive = false

    private var settings: SettingsStore { services.settings }

    var body: some View {
        Form {
            MediaSourceSection(service: service, health: health)
            Section {
                SettingRow(isDefault: settings.isDefault(MediaSettings.visualizer), reset: { settings.reset(MediaSettings.visualizer) }) {
                    Picker(selection: visualizerBinding) {
                        ForEach(MediaVisualizerMode.allCases, id: \.self) { mode in
                            Text(verbatim: mode.title).tag(mode).disabled(mode == .live && !Self.supportsLive)
                        }
                    } label: { Text(verbatim: MediaPaneStrings.visualizer) }
                    .pickerStyle(.segmented)
                }
                if settings[MediaSettings.visualizer] == .live {
                    LiveVisualizerStatusRow(engine: service.visualizer, permissions: services.permissions)
                }
            } footer: {
                Text(verbatim: settings[MediaSettings.visualizer].footnote).foregroundStyle(.secondary)
            }
            Section {
                toggle(MediaSettings.showsBrowserMedia, MediaPaneStrings.showBrowserMedia)
                IgnoredAppsRow(service: service, settings: settings)
            } footer: {
                Text(verbatim: MediaPaneStrings.ignoreFootnote).foregroundStyle(.secondary)
            }
            Section {
                toggle(MediaSettings.artworkInCompact, MediaPaneStrings.artworkInCompact)
                SettingRow(isDefault: peekOnChange == NowPlayingActivity.kind.peeksOnChangeByDefault, reset: { setPeek(nil) }) {
                    Toggle(isOn: Binding(get: { peekOnChange }, set: { setPeek($0) })) {
                        Text(verbatim: MediaPaneStrings.peekOnTrackChange)
                    }
                }
            }
            AppleEventsSection(services: services)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .controlSize(.small)
        .sheet(isPresented: $askingForLive) {
            LiveVisualizerSheet {
                askingForLive = false
                settings[MediaSettings.visualizer] = .live
                service.visualizer.requestLiveAccess()
            } cancel: { askingForLive = false }
        }
    }

    static var supportsLive: Bool {
        if #available(macOS 14.2, *) { return true } else { return false }
    }

    /// Choosing Live asks first (why-sheet); the system prompt follows from the tap.
    private var visualizerBinding: Binding<MediaVisualizerMode> {
        Binding(get: { settings[MediaSettings.visualizer] }, set: { mode in
            if mode == .live, settings[MediaSettings.visualizer] != .live { askingForLive = true } else { settings[MediaSettings.visualizer] = mode }
        })
    }

    private func toggle(_ key: SettingKey<Bool>, _ title: String) -> some View {
        SettingRow(isDefault: settings.isDefault(key), reset: { settings.reset(key) }) {
            Toggle(isOn: settings.binding(key)) { Text(verbatim: title) }
        }
    }

    // MARK: Peek on track change (a Live Activities preference, written here too)

    private var peekPreference: ActivityPreference? { settings[CoreSettings.activityPreferences][.nowPlaying] }
    private var peekOnChange: Bool { peekPreference?.peeksOnChange ?? NowPlayingActivity.kind.peeksOnChangeByDefault }

    private func setPeek(_ on: Bool?) {
        let kind = NowPlayingActivity.kind
        var all = settings[CoreSettings.activityPreferences]
        let enabled = all[.nowPlaying]?.isEnabled ?? kind.isEnabledByDefault
        let peeks = on ?? kind.peeksOnChangeByDefault
        let isDefault = enabled == kind.isEnabledByDefault && peeks == kind.peeksOnChangeByDefault
        all[.nowPlaying] = isDefault ? nil : ActivityPreference(isEnabled: enabled, peeksOnChange: peeks)
        settings[CoreSettings.activityPreferences] = all
    }
}

/// A row with the "changed" dot and a "Reset to Default" context menu (DESIGN.md §11.3).
struct SettingRow<Content: View>: View {
    let isDefault: Bool
    let reset: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .overlay(alignment: .leading) {
                if !isDefault {
                    Circle().fill(.tint).frame(width: 6, height: 6).offset(x: -Space.l).accessibilityHidden(true)
                }
            }
            .contextMenu {
                Button { reset() } label: { Text(verbatim: MediaPaneStrings.resetToDefault) }.disabled(isDefault)
            }
    }
}

extension MediaVisualizerMode {
    var title: String {
        switch self {
        case .live: String(localized: "Live visualizer mode", defaultValue: "Live", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: segment, real audio levels")
        case .ambient: String(localized: "Ambient", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: segment, a pattern made from the track")
        case .static: String(localized: "Static", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: segment, dots that never move")
        case .off: MediaStrings.off
        }
    }

    var footnote: String {
        switch self {
        case .live: String(localized: "Live listens to the sound your Mac plays and never records or saves it.", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: footnote for Live")
        case .ambient: String(localized: "Ambient is a calm pattern made from the track, not from the sound. No permission needed.", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: footnote for Ambient")
        case .static: String(localized: "Static shows that something is playing without any movement.", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: footnote for Static")
        case .off: String(localized: "No visualizer in the notch or the widget.", bundle: .module, comment: "Settings ▸ Media ▸ Visualizer: footnote for Off")
        }
    }
}

#Preview("Settings ▸ Media") {
    let services = CrannyServices.preview()
    let service = SampleMedia.service(settings: services.settings, environment: services.environment, permissions: services.permissions)
    MediaSettingsPane(service: service, health: BridgeHealthMonitor(service: service), services: services)
        .frame(width: 620, height: 640)
}
