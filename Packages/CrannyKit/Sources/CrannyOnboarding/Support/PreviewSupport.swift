// CrannyOnboarding/Support/PreviewSupport.swift — stand-ins for `#Preview`s and tests: permissions that never
// prompt, a tip presenter that never opens a window, and the Welcome window at any step on
// `CrannyServices.preview()` data. Not used by the app.
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI

/// Permissions with fixed statuses; `request` grants (or answers `answers[kind]`) without any system prompt.
@MainActor @Observable final class StaticPermissionGateway: PermissionGateway {
    var statuses: [PermissionKind: PermissionStatus]
    var answers: [PermissionKind: PermissionStatus] = [:]
    private(set) var requested: [PermissionKind] = []
    private(set) var openedSettings: [PermissionKind] = []
    private(set) var refreshCount = 0

    init(_ statuses: [PermissionKind: PermissionStatus] = [:]) { self.statuses = statuses }

    func status(_ kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .notDetermined }
    func request(_ kind: PermissionKind) async -> PermissionStatus {
        requested.append(kind)
        let answer = answers[kind] ?? .granted
        statuses[kind] = answer
        return answer
    }
    func openSystemSettings(_ kind: PermissionKind) { openedSettings.append(kind) }
    func refresh() { refreshCount += 1 }
}

/// Records what would be shown; never creates a window.
@MainActor final class RecordingTipPresenter: TipPresenter {
    var onAction: (@MainActor () -> Void)?
    private(set) var shown: [TipContent] = []
    private(set) var anchors: [CGRect] = []
    private(set) var themes: [CrannyTheme] = []
    private(set) var hideCount = 0
    private(set) var isVisible = false

    init() {}

    func show(_ content: TipContent, under anchor: CGRect, theme: CrannyTheme) {
        shown.append(content)
        anchors.append(anchor)
        themes.append(theme)
        isVisible = true
    }
    func hide() {
        hideCount += 1
        isVisible = false
    }
    /// Tests: press the bubble's button.
    func pressAction() { onAction?() }
}

extension Bundle {
    /// Tests: this module's strings in one language (`"ru"`), or nil when the catalog has no such localization.
    static func onboardingStrings(_ language: String) -> Bundle? {
        Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

/// Uses declared the way the feature modules declare them (calendar, HUD, media, devices), for previews.
@MainActor func registerSamplePermissionUses(in registry: ModuleRegistry) {
    struct Calendar: FeatureModule {
        static var id: ModuleID { .calendar }
        static func register(in registry: ModuleRegistry) {
            registry.declare(.calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them.")
        }
    }
    struct HUD: FeatureModule {
        static var id: ModuleID { .hud }
        static func register(in registry: ModuleRegistry) {
            registry.declare(.accessibility, reason: "Replace the system volume and brightness HUD. Cranny reads no other keys.")
        }
    }
    struct Media: FeatureModule {
        static var id: ModuleID { .media }
        static func register(in registry: ModuleRegistry) {
            registry.declare(.automation(bundleID: "com.apple.Music"), reason: "Control Music when other ways fail. Cranny sends only playback commands.")
            registry.declare(.automation(bundleID: "com.spotify.client"), reason: "Control Music when other ways fail. Cranny sends only playback commands.")
            registry.declare(.systemAudioRecording, reason: "Draw the live visualizer.")
        }
    }
    struct System: FeatureModule {
        static var id: ModuleID { .system }
        static func register(in registry: ModuleRegistry) {
            registry.declare(.bluetooth, reason: "Show the battery of every Bluetooth device. Cranny never connects to them.")
        }
    }
    for module in [Calendar.self, HUD.self, Media.self, System.self] as [any FeatureModule.Type] { registry.register(module) }
}

/// The Welcome window at `step` with sample data and no side effects outside the preview.
struct WelcomePreview: View {
    let flow: WelcomeFlow

    init(step: WelcomeStep, detected: [OpenMethod] = []) {
        let registry = ModuleRegistry(services: .preview())
        registerSamplePermissionUses(in: registry)
        let stage = StageScene(registry: registry, layout: NotchLayout(metrics: .reference), theme: CrannyTheme(),
                               ambient: .afterglow, greeting: WelcomeFlow.greeting)
        let flow = WelcomeFlow(registry: registry, permissions: StaticPermissionGateway([.calendar: .granted]),
                               coach: RecordingTipPresenter(), stage: stage, initialStep: step, version: "0.1.0") { _ in }
        flow.start(reduceMotion: true)
        let notch = registry.services.notch as? PreviewNotchControl
        for method in detected {
            notch?.emit(.opened(method == .hover ? .hover : method == .click ? .click : .keyboard))
            notch?.emit(.closed)
        }
        self.flow = flow
    }

    var body: some View {
        WelcomeView(flow: flow)
    }
}
