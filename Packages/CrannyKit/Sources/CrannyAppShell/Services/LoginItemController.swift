// CrannyAppShell/Services/LoginItemController.swift — Launch at login (ARCHITECTURE.md §7.9, D15).
// `SMAppService.mainApp` only. The status (an XPC round trip) is read on first use, not at launch: only Settings and
// the welcome show it. After that it is read again whenever the app becomes active (Settings and the welcome window
// activate it), never cached as a Bool: the user can change it in System Settings at any time.
// `.requiresApproval` and a refused registration lead to System Settings ▸ General ▸ Login Items; a translocated
// copy (run from Downloads) cannot register at all, so it asks to be moved to Applications.
import AppKit
import CrannyCore
import Foundation
import Observation
import os
import ServiceManagement

private let log = Log.logger(.app)

/// The slice of `SMAppService` the controller uses; tests inject a fake so nothing touches real login items.
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// The app itself as a login item.
final class MainAppLoginItem: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor @Observable final class LoginItemController {
    /// `AppControl.loginItem`. The first read asks `SMAppService` (so whoever shows it first, Settings ▸ General or the
    /// welcome, sees the real status); later reads return what the last refresh found.
    var state: LoginItemState {
        if !hasRead { refresh() }
        return current
    }
    /// The status as last read or set (observed: views reading `state` follow it).
    private var current: LoginItemState = .disabled
    /// Whether the status was read (or set) at least once; until then nothing shows it.
    @ObservationIgnored private var hasRead = false
    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let bundleURL: URL
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(service: any LoginItemService = MainAppLoginItem(), bundleURL: URL = Bundle.main.bundleURL) {
        self.service = service; self.bundleURL = bundleURL
    }

    /// Reads the status again every time Cranny becomes active, once something has read it (the first read is lazy:
    /// a launch at login, which shows neither Settings nor the welcome, makes no XPC call for it).
    func start() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.hasRead { self.refresh() } }      // queue: .main
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Reads the status now.
    func refresh() {
        hasRead = true
        let next = Self.isTranslocated(bundleURL) ? .unavailable(Self.moveToApplicationsMessage) : Self.state(for: service.status)
        if next != current { current = next }
    }

    /// `AppControl.setLaunchAtLogin`. Turning it on while approval is pending, or again after macOS refused it,
    /// opens Login Items in System Settings, where the user finishes the job (Settings' "Open Login Items…").
    func setEnabled(_ enabled: Bool) {
        guard !Self.isTranslocated(bundleURL) else { refresh(); return }
        hasRead = true                                         // every path below reads the status and sets `current`
        let status = Self.state(for: service.status)
        if enabled {
            switch status {
            case .enabled:
                current = .enabled
                return
            case .requiresApproval:
                current = .requiresApproval
                service.openSystemSettingsLoginItems()
                return
            case .disabled, .unavailable:
                if current == .unavailable(Self.refusedMessage) { service.openSystemSettingsLoginItems(); return }
            }
            do {
                try service.register()
                log.info("login item registered")
            } catch {
                log.error("login item not registered: \(error.localizedDescription, privacy: .public)")
            }
            switch Self.state(for: service.status) {
            case .enabled:
                current = .enabled
            case .requiresApproval:
                current = .requiresApproval
                service.openSystemSettingsLoginItems()
            case .disabled, .unavailable:
                current = .unavailable(Self.refusedMessage)
            }
        } else {
            guard status != .disabled else { current = .disabled; return }
            do {
                try service.unregister()
                log.info("login item unregistered")
            } catch {
                log.error("login item not unregistered: \(error.localizedDescription, privacy: .public)")
            }
            current = Self.state(for: service.status)
        }
    }

    // MARK: Pure helpers (unit-tested)

    /// `.notRegistered` and `.notFound` (an app macOS has never seen as a login item) are both "off" (R3 §9).
    nonisolated static func state(for status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// App Translocation runs a quarantined app from a random read-only path, which breaks login items.
    nonisolated static func isTranslocated(_ url: URL) -> Bool {
        url.standardizedFileURL.path(percentEncoded: false).contains("/AppTranslocation/")
    }

    nonisolated static var moveToApplicationsMessage: String {
        String(localized: "Launch at login needs Cranny in the Applications folder. Move it there, then open it again.",
               bundle: .module, comment: "Settings ▸ General ▸ Launch at login: footnote when the app runs from a translocated copy")
    }

    nonisolated static var refusedMessage: String {
        String(localized: "macOS didn’t add Cranny to your login items. Open Login Items in System Settings to add it.",
               bundle: .module, comment: "Settings ▸ General ▸ Launch at login: footnote when registration failed")
    }
}
