// CrannyTimer/TimerModule.swift — reference skeleton showing every contract (ARCHITECTURE.md §3.17).
import CrannyCore
import Foundation
import Observation
import SwiftUI

public enum TimerModule: FeatureModule {
    public static var id: ModuleID { .timer }

    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let model = TimerModel(settings: services.settings, haptics: services.haptics)
        registry.add(widget: TimerWidget(model: model))
        registry.add(activity: TimerRunningActivity(model: model), kind: ActivityKind(
            id: .timerRunning, module: .timer,
            title: String(localized: "Timer", bundle: .module, comment: "Timer: module name (widget, live activity, ⌘K result kind)"),
            symbol: "timer", defaultPriority: .ongoing, canPeekOnChange: true, peeksOnChangeByDefault: true),
            options: { AnyView(Toggle(isOn: services.settings.binding(TimerSettings.peeksAtOneMinute)) {
                Text("Peek at one minute left", bundle: .module, comment: "Live Activities pane: timer option") }) })
        registry.add(commands: TimerCommands(model: model))
        registry.add(shortcut: GlobalShortcut(
            id: .startTimer, title: String(localized: "Start timer", bundle: .module, comment: "Settings ▸ Keyboard: shortcut name")) {
                model.start(seconds: services.settings[TimerSettings.presets].first ?? 300)
                services.notch.open(page: .nook, focus: .timer, reason: .keyboard)
            })
        registry.onLaunch { await model.restore() }
        registry.onTerminate { model.persistNow() }
    }
}

public enum TimerSettings {
    public static let presets = SettingKey<[Int]>(.timer, "presets", default: [60, 300, 600, 1500])
    public static let sound = SettingKey<String?>(.timer, "sound", default: "Glass")
    public static let peeksAtOneMinute = SettingKey<Bool>(.timer, "peeksAtOneMinute", default: true)
}

@MainActor @Observable final class TimerModel {
    private(set) var endDate: Date?
    private(set) var total: TimeInterval = 0
    private(set) var revision = 0
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private var finish: Task<Void, Never>?

    init(settings: SettingsStore, haptics: Haptics) { self.settings = settings; self.haptics = haptics }

    var isRunning: Bool { endDate != nil }
    func remaining(at now: Date = .now) -> TimeInterval { max((endDate ?? now).timeIntervalSince(now), 0) }

    func start(seconds: Int) {
        total = TimeInterval(seconds)
        endDate = .now.addingTimeInterval(total)
        revision += 1
        scheduleFinish()
    }
    func stop() { endDate = nil; finish?.cancel(); revision += 1 }

    /// One sleep to the deadline — no ticking timer (energy rule: zero timers while closed).
    private func scheduleFinish() {
        finish?.cancel()
        guard let endDate else { return }
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
    func restore() async {}
    func persistNow() {}
}

final class TimerWidget: NookWidget {
    let model: TimerModel
    init(model: TimerModel) { self.model = model }
    let id: WidgetID = .timer
    var title: String { String(localized: "Timer", bundle: .module, comment: "Timer: module name (widget, live activity, ⌘K result kind)") }
    let symbol = "timer"
    var summary: String { String(localized: "Countdowns with presets", bundle: .module, comment: "Widget library: Timer description") }
    let sizes = WidgetSizes(minimum: 2, preferred: 2, maximum: 3)

    func makeBody(context: WidgetContext) -> some View { TimerFace(model: model, context: context) }
}

struct TimerFace: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    let context: WidgetContext
    var body: some View {
        // Ticks only while visible AND running; paused it costs nothing (energy budget, DESIGN.md §4.7).
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            let left = model.remaining(at: tl.date)
            ZStack {
                ProgressRing(progress: model.total > 0 ? left / model.total : 0, color: theme.palette.warning, lineWidth: StrokeWidth.ring)
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                    .crannyFont(.numeral)
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 88, height: 88)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

@MainActor @Observable final class TimerRunningActivity: LiveActivity {
    @ObservationIgnored let model: TimerModel
    init(model: TimerModel) { self.model = model }
    let id: ActivityID = .timerRunning
    var isActive: Bool { model.isRunning }
    let priority: ActivityPriority = .ongoing
    let slot: SlotWidth = .medium
    var revision: Int { model.revision }
    var palette: AmbientPalette? { .timer }
    var opensWidget: WidgetID? { .timer }
    var accessibilityLabel: String { String(localized: "Timer running", bundle: .module, comment: "Timer activity: VoiceOver label") }
    var actions: [ActivityAction] {
        [ActivityAction(id: "stop", title: String(localized: "Stop timer", bundle: .module, comment: "Timer activity: VoiceOver action"),
                        symbol: "stop.fill") { [model] in model.stop() }]
    }

    func compactLeading() -> some View { TimerCompactRing(model: model) }
    func compactTrailing() -> some View { TimerCompactValue(model: model) }
    func minimal() -> some View { TimerCompactRing(model: model) }
    func peekRow() -> some View { TimerCompactValue(model: model) }   // WP7: ring 40 · label · ⏸ ⏹ · +1 min
}

/// Views read tokens from the environment — activities never hard-code colours.
struct TimerCompactRing: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            ProgressRing(progress: model.total > 0 ? model.remaining(at: tl.date) / model.total : 0,
                         color: theme.palette.warning, lineWidth: StrokeWidth.ringCompact)
        }
        .frame(width: 16 * theme.notchUnit, height: 16 * theme.notchUnit)
        .accessibilityHidden(true)
    }
}

struct TimerCompactValue: View {
    let model: TimerModel
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            Text(Duration.seconds(model.remaining(at: tl.date)).formatted(.time(pattern: .minuteSecond)))
                .crannyFont(.compact)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

final class TimerCommands: PaletteCommandProvider {
    let model: TimerModel
    init(model: TimerModel) { self.model = model }
    func commands(matching query: String) -> [PaletteCommand] {
        [PaletteCommand(id: "timer.start25", title: String(localized: "Start 25-minute timer", bundle: .module, comment: "Command palette: Timer command"),
                        kind: String(localized: "Timer", bundle: .module, comment: "Timer: module name (widget, live activity, ⌘K result kind)"),
                        symbol: "timer") { [model] in model.start(seconds: 1500) }]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
}

#Preview("Timer widget") {
    let services = CrannyServices.preview()
    let model = TimerModel(settings: services.settings, haptics: services.haptics)
    TimerWidget(model: model).makeBody(context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96)))
        .crannyCard(cells: 2)
        .crannyThemeRoot(CrannyTheme())
        .padding()
        .background(.black)
}
