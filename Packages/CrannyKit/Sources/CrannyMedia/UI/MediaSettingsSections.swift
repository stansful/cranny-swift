// CrannyMedia/UI/MediaSettingsSections.swift — the larger rows of Settings ▸ Media: source status with
// "Test Media Detection", the Live visualizer's permission row and why-sheet, and the Apple Events fallback with
// its per-player Automation rows. Permission prompts happen only on a click here (ARCHITECTURE.md §3.12).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

/// Which helper reads Now Playing, its health and the last error; Test media detection; Retry. Status colours are
/// the theme's semantic tokens (success / warning / danger, DESIGN.md §2.1), never literal colours; the text says
/// the same thing (Differentiate Without Color).
struct MediaSourceSection: View {
    @Environment(\.cranny) private var theme
    let service: MediaService
    let health: BridgeHealthMonitor
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Space.s) {
                    Circle().fill(statusColor).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(verbatim: statusText).foregroundStyle(.secondary)
                }
            } label: {
                Text(verbatim: service.activeKind?.title ?? MediaPaneStrings.noSource)
            }
            if health.isDegraded {
                Label { Text(verbatim: MediaPaneStrings.degraded) } icon: { Image(systemName: "exclamationmark") }
                    .foregroundStyle(theme.palette.warning)
            }
            HStack {
                Button { Task { await test() } } label: { Text(verbatim: MediaPaneStrings.testDetection) }
                    .disabled(testing)
                if service.status == .unavailable {
                    Button { service.restart() } label: { Text(verbatim: MediaStrings.retry) }
                }
                Spacer()
            }
            if let testResult {
                Text(verbatim: testResult).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: MediaPaneStrings.source)
        } footer: {
            if let error = service.lastError?.errorDescription {
                Text(verbatim: error).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch service.status {
        case .idle: MediaPaneStrings.statusIdle
        case .starting: MediaPaneStrings.statusStarting
        case .running: health.isDegraded ? MediaPaneStrings.statusDegraded : MediaPaneStrings.statusWorking
        case .restarting: MediaPaneStrings.statusRestarting
        case .unavailable: MediaPaneStrings.statusUnavailable
        }
    }

    /// In-between states (not started, starting, restarting) are neutral: no semantic colour fits them.
    private var statusColor: AnyShapeStyle {
        switch service.status {
        case .running: AnyShapeStyle(health.isDegraded ? theme.palette.warning : theme.palette.success)
        case .starting, .restarting, .idle: AnyShapeStyle(.tertiary)
        case .unavailable: AnyShapeStyle(theme.palette.danger)
        }
    }

    /// The helper answers `ping`; while sound plays, a session must be visible (R2 §5.4).
    private func test() async {
        testing = true
        defer { testing = false }
        guard service.activeKind == .perl || service.activeKind == .ruby else {
            testResult = service.status == .running(.sample) ? MediaPaneStrings.testSample : MediaPaneStrings.testNoHelper
            return
        }
        guard let roundTrip = await service.ping() else { testResult = MediaPaneStrings.testNoAnswer; return }
        let milliseconds = Int((roundTrip.timeInterval * 1000).rounded())
        // What the helper sees, before Ignore apps / browser filters and untitled sessions are applied.
        if let np = service.nowPlaying {
            let app = (np.bundleID ?? np.parentBundleID).flatMap { PlayerApps.name(for: $0, fallback: np.appName) } ?? np.appName
            testResult = app.map { MediaPaneStrings.testSeesPlayer($0, milliseconds) } ?? MediaPaneStrings.testSeesUnnamedPlayer(milliseconds)
        } else if let pid = service.reportedPlayerPID, pid > 0 {
            testResult = service.reportedPlayerBundleID.flatMap { PlayerApps.name(for: $0) }
                .map { MediaPaneStrings.testSeesPlayer($0, milliseconds) } ?? MediaPaneStrings.testSeesUnnamedPlayer(milliseconds)
        } else if AudioOutputMonitor.isOtherProcessRunningOutput() {
            testResult = MediaPaneStrings.testBlind(milliseconds)
        } else {
            testResult = MediaPaneStrings.testIdle(milliseconds)
        }
    }
}

/// Live mode: what the tap observed (System Audio Recording has no query API).
struct LiveVisualizerStatusRow: View {
    let engine: VisualizerEngine
    let permissions: PermissionsCenter

    var body: some View {
        LabeledContent {
            HStack(spacing: Space.m) {
                Text(verbatim: statusText).foregroundStyle(.secondary)
                if engine.liveStatus == .denied || engine.liveStatus == .silent {
                    Button { permissions.openSystemSettings(.systemAudioRecording) } label: {
                        Text(verbatim: MediaPaneStrings.openPrivacySettings)
                    }
                }
            }
        } label: {
            Text(verbatim: PermissionKind.systemAudioRecording.title)
        }
    }

    private var statusText: String {
        switch engine.liveStatus {
        case .receiving: MediaPaneStrings.liveReceiving
        case .waiting, .off: MediaPaneStrings.liveWaiting
        case .silent: MediaPaneStrings.liveSilent
        case .denied: MediaPaneStrings.liveDenied
        case .failed: MediaPaneStrings.liveFailed
        case .unsupported: MediaPaneStrings.liveUnsupported
        }
    }
}

/// The why-sheet shown before Live is turned on (DESIGN.md §11.1).
struct LiveVisualizerSheet: View {
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
            Text(verbatim: MediaPaneStrings.liveSheetTitle).font(.title3.weight(.semibold))
            Text(verbatim: MediaPaneStrings.liveSheetBody).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .cancel) { cancel() } label: { Text(verbatim: MediaPaneStrings.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { confirm() } label: { Text(verbatim: MediaPaneStrings.continueTitle) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 380)
    }
}

/// Apple Events fallback for Music and Spotify (off by default: it asks for Automation per app). One row per player
/// that is installed (`AppIdentityResolver`; looked up again when the section appears, so a player installed meanwhile
/// shows), named by Finder. Statuses come from `PermissionsCenter`'s cache: no view body runs an Apple Events query.
struct AppleEventsSection: View {
    let services: CrannyServices

    var body: some View {
        let settings = services.settings
        Section {
            SettingRow(isDefault: settings.isDefault(MediaSettings.allowAppleEvents), reset: { settings.reset(MediaSettings.allowAppleEvents) }) {
                Toggle(isOn: settings.binding(MediaSettings.allowAppleEvents)) { Text(verbatim: MediaPaneStrings.appleEvents) }
            }
            if settings[MediaSettings.allowAppleEvents] {
                ForEach(ScriptablePlayer.all, id: \.bundleID) { player in
                    let identity = PlayerApps.identity(player.bundleID)
                    if let name = identity.name {
                        AutomationRow(bundleID: player.bundleID, name: name, icon: identity.icon, permissions: services.permissions)
                    }
                }
            }
        } footer: {
            Text(verbatim: MediaPaneStrings.appleEventsFootnote).foregroundStyle(.secondary)
        }
        .onAppear {
            AppIdentityResolver.shared.refresh()           // a player installed or removed meanwhile
            services.permissions.refreshInBackground()     // a grant changed in System Settings meanwhile
        }
    }
}

private struct AutomationRow: View {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let permissions: PermissionsCenter

    var body: some View {
        let kind = PermissionKind.automation(bundleID: bundleID)
        LabeledContent {
            switch permissions.knownStatus(kind) {
            case nil:
                ProgressView().controlSize(.small)          // the first answer is on its way (off the main actor)
            case .granted?:
                Text(verbatim: MediaPaneStrings.allowed).foregroundStyle(.secondary)
            case .denied?, .restricted?:
                Button { permissions.openSystemSettings(kind) } label: { Text(verbatim: MediaPaneStrings.openPrivacySettings) }
            case .notDetermined?:
                Button { Task { await permissions.request(kind) } } label: { Text(verbatim: MediaPaneStrings.allow) }
            case .unknown?:
                Text(verbatim: MediaPaneStrings.openToAllow).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: Space.s) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                Text(verbatim: name)
            }
        }
    }
}

#Preview("Live why-sheet") {
    LiveVisualizerSheet(confirm: {}, cancel: {})
}

#Preview("Source and fallback sections") {
    let services = CrannyServices.preview()
    let service = SampleMedia.service(settings: services.settings, environment: services.environment, permissions: services.permissions)
    Form {
        MediaSourceSection(service: service, health: BridgeHealthMonitor(service: service))
        AppleEventsSection(services: services)
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 360)
}
