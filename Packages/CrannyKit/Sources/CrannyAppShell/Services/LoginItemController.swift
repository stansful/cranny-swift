// CrannyAppShell/Services/LoginItemController.swift — Launch at login (ARCHITECTURE.md §7.9, D15), WP16.
// `SMAppService.mainApp` only. The status is read again whenever the app becomes active (Settings and the
// welcome window activate it), never cached as a Bool: the user can change it in System Settings at any time.
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
    /// `AppControl.loginItem`.
    private(set) var state: LoginItemState = .disabled
    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let bundleURL: URL
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(service: any LoginItemService = MainAppLoginItem(), bundleURL: URL = Bundle.main.bundleURL) {
        self.service = service; self.bundleURL = bundleURL
    }

    /// Reads the status now and again every time Cranny becomes active.
    func start() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }                       // queue: .main
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func refresh() {
        let next = Self.isTranslocated(bundleURL) ? .unavailable(Self.moveToApplicationsMessage) : Self.state(for: service.status)
        if next != state { state = next }
    }

    /// `AppControl.setLaunchAtLogin`. Turning it on while approval is pending, or again after macOS refused it,
    /// opens Login Items in System Settings, where the user finishes the job (Settings' "Open Login Items…").
    func setEnabled(_ enabled: Bool) {
        guard !Self.isTranslocated(bundleURL) else { refresh(); return }
        let current = Self.state(for: service.status)
        if enabled {
            switch current {
            case .enabled:
                state = .enabled
                return
            case .requiresApproval:
                state = .requiresApproval
                service.openSystemSettingsLoginItems()
                return
            case .disabled, .unavailable:
                if state == .unavailable(Self.refusedMessage) { service.openSystemSettingsLoginItems(); return }
            }
            do {
                try service.register()
                log.info("login item registered")
            } catch {
                log.error("login item not registered: \(error.localizedDescription, privacy: .public)")
            }
            switch Self.state(for: service.status) {
            case .enabled:
                state = .enabled
            case .requiresApproval:
                state = .requiresApproval
                service.openSystemSettingsLoginItems()
            case .disabled, .unavailable:
                state = .unavailable(Self.refusedMessage)
            }
        } else {
            guard current != .disabled else { state = .disabled; return }
            do {
                try service.unregister()
                log.info("login item unregistered")
            } catch {
                log.error("login item not unregistered: \(error.localizedDescription, privacy: .public)")
            }
            state = Self.state(for: service.status)
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
        String(localized: "macOS didn't add Cranny to your login items. Open Login Items in System Settings to add it.",
               bundle: .module, comment: "Settings ▸ General ▸ Launch at login: footnote when registration failed")
    }
}
