// CrannyTimer/Model/TimerModel.swift — the one timer of the app: deadline-based, persisted, observable.
// Energy (ARCHITECTURE.md §9.2): the model never ticks. It keeps ONE sleep to its next event (last minute, deadline,
// end of "done"); views that show seconds run their own 1-Hz clock only while they are on screen.
import AppKit
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.timer)

@MainActor @Observable final class TimerModel {
    /// The countdown (read by every view and both activities).
    private(set) var state = TimerState()
    /// Seconds of the most recent start: the "Start timer" shortcut and the set-up ring start from it.
    private(set) var lastDuration = Int(TimerLimits.defaultDuration)
    /// The idle set-up value changed by scrolling or VoiceOver (nil = the presets are shown).
    private(set) var draft: Int?
    /// The running activity's meaningful changes: a new run, the last minute (undoes a swipe-up dismissal).
    private(set) var runningRevision = 0
    /// Every time a timer finishes ("Timer done" peeks, the ember burst plays, the widget ring pulses).
    private(set) var doneRevision = 0

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let dependencies: TimerDependencies
    @ObservationIgnored private var lastMinuteSignalled = true
    @ObservationIgnored private var writeSequence = 0
    /// Set by the first user change; a slow launch restore never overwrites it.
    @ObservationIgnored private var changedSinceLaunch = false
    @ObservationIgnored private var systemObservers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(settings: SettingsStore, dependencies: TimerDependencies) {
        self.settings = settings
        self.dependencies = dependencies
    }

    // MARK: Reading

    var now: Date { dependencies.now() }
    /// The draft the set-up ring shows (the last duration until the user changes it).
    var setupDuration: Int { draft ?? lastDuration }
    /// The user's presets in seconds, sanitised (positive, within limits, at most four).
    var presets: [Int] {
        settings[TimerSettings.presets]
            .filter { $0 >= Int(TimerLimits.minimum) && $0 <= Int(TimerLimits.maximum) }
            .prefix(TimerSettings.maximumPresets).map { $0 }
    }

    /// DESIGN.md §16 (Text size): band text follows the notch unit, so at Large and Extra Large text the band shows
    /// the glyph form (ring or glyph only, a narrower slot) and the time moves to the peek.
    var bandUsesGlyphForm: Bool {
        let size = settings[CoreSettings.textSize]
        return size == .large || size == .extraLarge
    }

    // MARK: Actions

    /// Starts a new timer (replacing any other) for `seconds`, clamped to the limits.
    func start(seconds: Int) {
        let now = self.now
        state.start(duration: TimeInterval(seconds), now: now)
        lastDuration = Int(state.total)
        draft = nil
        lastMinuteSignalled = !TimerSchedule.lastMinuteIsAhead(remaining: state.total)
        runningRevision += 1
        dependencies.sound.stop()
        log.info("timer started: \(Int(self.state.total), privacy: .public) s")
        commit()
    }

    /// Starts the set-up value (↩ on an idle face, the "Start" chip, the shortcut).
    func startSetup() { start(seconds: setupDuration) }

    func pause() {
        guard state.pause(now: now) else { return }
        commit()
    }

    func resume() {
        guard state.resume(now: now) else { return }
        commit()
    }

    /// Space in the widget, ⏸/▶ buttons, VoiceOver.
    func togglePause() {
        if state.isPaused { resume() } else { pause() }
    }

    /// ⏹, ⌫, "Stop" on the done peek: back to idle and silence.
    func stop() {
        dependencies.sound.stop()
        draft = nil
        guard state.stop() else { return }
        log.info("timer stopped")
        commit()
    }

    /// "+1 min": more time on a running/paused timer; a new one-minute timer when done.
    func addMinute() {
        if state.isDone {
            start(seconds: Int(TimerLimits.step))
            return
        }
        guard state.addTime(TimerLimits.step, now: now) else { return }
        rearmLastMinute()
        commit()
    }

    /// Scroll detents and VoiceOver: ±`minutes` on a counting timer, else on the idle set-up value.
    /// Returns whether the value changed (the caller plays one `.levelChange` haptic per applied detent).
    @discardableResult func adjust(byMinutes minutes: Int) -> Bool {
        guard minutes != 0 else { return false }
        let delta = TimeInterval(minutes) * TimerLimits.step
        if state.isCounting {
            guard state.adjust(by: delta, now: now) else { return false }
            rearmLastMinute()
            commit()
            return true
        }
        guard !state.isDone else { return false }
        let base = TimeInterval(setupDuration)
        let target = min(max(base + delta, TimerLimits.step), TimerLimits.maximum)
        guard target != base else { return false }
        draft = Int(target)
        return true
    }

    /// Esc / ⌫ on an idle face, or the face going away: back to the presets.
    func clearDraft() { draft = nil }

    // MARK: Events (one sleep at a time)

    /// Handles every event that is due, then sleeps to the next one. Also called on wake and clock changes.
    func reconcile() {
        let now = self.now
        while let next = TimerSchedule.next(for: state, lastMinuteSignalled: lastMinuteSignalled), next.date <= now {
            handle(next.event, now: now)
        }
        reschedule()
    }

    private func handle(_ event: TimerEvent, now: Date) {
        switch event {
        case .lastMinute:
            lastMinuteSignalled = true
            guard let end = state.endDate, end > now else { return }   // slept past it: the finish comes next
            runningRevision += 1
            if settings[TimerSettings.peeksAtOneMinute] { dependencies.requestPeek(.timerRunning) }
        case .finish:
            state.finish()
            if let doneAt = state.doneAt, now.timeIntervalSince(doneAt) < TimerLimits.doneLinger {
                doneRevision += 1
                playDoneSound()
                log.info("timer done")
            } else {
                state.expire()                                       // ended long ago (the Mac slept): no alert
            }
            persist()
        case .expire:
            state.expire()
            dependencies.sound.stop()
            persist()
        }
    }

    private func playDoneSound() {
        guard !dependencies.isDemoMode(), let name = settings[TimerSettings.sound], !name.isEmpty else { return }
        dependencies.sound.play(named: name)
    }

    private func rearmLastMinute() {
        if TimerSchedule.lastMinuteIsAhead(remaining: state.remaining(at: now)) { lastMinuteSignalled = false }
    }

    private func reschedule() {
        guard let next = TimerSchedule.next(for: state, lastMinuteSignalled: lastMinuteSignalled) else {
            dependencies.scheduler.cancel()
            return
        }
        dependencies.scheduler.schedule(at: next.date) { [weak self] in self?.reconcile() }
    }

    /// Every user change: persist, then sleep to the next event.
    private func commit() {
        changedSinceLaunch = true
        persist()
        reschedule()
    }

    // MARK: Persistence (AppPaths/timer/state.json)

    private var snapshot: TimerSnapshot { TimerSnapshot(state: state, lastDuration: lastDuration) }

    private func persist() {
        guard let file = dependencies.file else { return }
        writeSequence += 1
        let snapshot = self.snapshot, sequence = writeSequence
        Task { await file.writeInBackground(snapshot, sequence: sequence) }
    }

    /// Launch hook: loads the saved timer (off the main actor) and applies what it means now — still running, done
    /// within the last minute, or idle. A change the user made while it loaded wins.
    func restore() async {
        guard let file = dependencies.file, let saved = await file.loadInBackground(), !changedSinceLaunch else {
            reschedule()
            return
        }
        lastDuration = min(max(saved.lastDuration, Int(TimerLimits.minimum)), Int(TimerLimits.maximum))
        let now = self.now
        let restored = saved.state.reconciled(at: now)
        state = restored
        lastMinuteSignalled = !TimerSchedule.lastMinuteIsAhead(remaining: restored.remaining(at: now))
        if restored.isDone { doneRevision += 1 }                    // shown, but no sound after a relaunch
        if restored != saved.state { persist() }
        log.info("timer restored: \(String(describing: restored.phase), privacy: .public)")
        reschedule()
    }

    /// Terminate hook: a synchronous final write (the process exits right after).
    func persistNow() {
        guard let file = dependencies.file else { return }
        writeSequence += 1
        do { try file.write(snapshot, sequence: writeSequence) } catch {
            log.error("could not save state.json on quit: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Samples

    /// Settings "Simulate", the onboarding stage and `#Preview`s only (`TimerModel.sample`): puts a sample state in
    /// place and schedules its events like a real run. Never used on the app's model.
    func showSample(_ sample: TimerState, draft: Int? = nil) {
        state = sample
        self.draft = draft
        if sample.isDone { doneRevision += 1 } else if sample.isCounting { runningRevision += 1 }
        lastMinuteSignalled = !TimerSchedule.lastMinuteIsAhead(remaining: sample.remaining(at: now))
        reschedule()
    }

    // MARK: Sleep, wake and clock changes

    /// Re-checks the deadline when the Mac wakes or the clock is changed (a sleeping Task cannot know either).
    func startObservingSystemClock() {
        guard systemObservers.isEmpty else { return }
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, .NSSystemClockDidChange),
        ]
        systemObservers = sources.map { center, name in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }      // queue: .main
            }
            return (center, token)
        }
    }

    /// Terminate hook: no observers, no pending sleep, no sound.
    func stopObservingSystemClock() {
        for (center, token) in systemObservers { center.removeObserver(token) }
        systemObservers = []
        dependencies.scheduler.cancel()
        dependencies.sound.stop()
    }
}
