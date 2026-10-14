// CrannyTimer/Model/TimerState.swift — the timer as a pure, deadline-based value (DESIGN.md §7.7, ARCHITECTURE.md §10.8).
// Nothing here ticks: a running timer is an end date, a paused one is the time it had left. Every transition takes
// `now` explicitly, so the whole lifecycle is unit-tested without clocks, sleeps or windows.
import Foundation

/// Limits and fixed intervals of the timer.
nonisolated enum TimerLimits {
    /// Shortest timer (1 s) and longest (23:59:59). Typed or adjusted durations are clamped to this range.
    static let minimum: TimeInterval = 1
    static let maximum: TimeInterval = 24 * 3600 - 1
    /// One scroll detent, VoiceOver adjustment or "+1 min".
    static let step: TimeInterval = 60
    /// "Timer done" stays for one minute unless it is dismissed (DESIGN.md §9.2), and a timer that ended while
    /// Cranny was not running is only reported as done when it ended at most this long ago.
    static let doneLinger: TimeInterval = 60
    /// The running activity's meaningful change "last minute of a timer" (DESIGN.md §9.2).
    static let lastMinute: TimeInterval = 60
    /// The digits pulse during the last 10 s (DESIGN.md §7.7).
    static let pulseWindow: TimeInterval = 10
    /// Used when nothing was started yet (the "Start timer" shortcut, the 3-cell set-up ring).
    static let defaultDuration: TimeInterval = 300
}

/// Where a timer is in its lifecycle.
nonisolated enum TimerPhase: Codable, Equatable, Sendable {
    case idle
    /// Counting down to `endDate`.
    case running(endDate: Date)
    /// Frozen with `remaining` seconds left.
    case paused(remaining: TimeInterval)
    /// Reached zero at `at` (the end date, not the moment Cranny noticed).
    case done(at: Date)
}

/// One countdown. `total` is the length of the current run, including added minutes: it is the denominator of the
/// ring's progress, so "+1 min" grows the ring instead of overfilling it.
nonisolated struct TimerState: Codable, Equatable, Sendable {
    var phase: TimerPhase = .idle
    var total: TimeInterval = 0

    init(phase: TimerPhase = .idle, total: TimeInterval = 0) {
        self.phase = phase
        self.total = total
    }

    // MARK: Queries

    var isRunning: Bool { if case .running = phase { true } else { false } }
    var isPaused: Bool { if case .paused = phase { true } else { false } }
    var isDone: Bool { if case .done = phase { true } else { false } }
    /// Running or paused: the "Timer" live activity is shown.
    var isCounting: Bool { isRunning || isPaused }

    /// The end date while running, else nil (paused timers have no deadline).
    var endDate: Date? { if case .running(let end) = phase { end } else { nil } }
    /// When the timer reached zero, while it is done.
    var doneAt: Date? { if case .done(let at) = phase { at } else { nil } }

    /// Seconds left (0 when idle or done).
    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .done: 0
        case .running(let end): max(end.timeIntervalSince(now), 0)
        case .paused(let left): max(left, 0)
        }
    }

    /// Ring fill, 1 = full, 0 = empty. A done timer shows a full ring (DESIGN.md §7.7: it pulses twice).
    func progress(at now: Date) -> Double {
        switch phase {
        case .idle: 0
        case .done: 1
        case .running, .paused: total > 0 ? min(max(remaining(at: now) / total, 0), 1) : 0
        }
    }

    /// The whole seconds shown by the digits: rounded UP, so a fresh 5-minute timer reads "5:00" and the display
    /// reaches "0:00" exactly at the deadline.
    func displayedSeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    /// The last minute (warning colour in the band, the one-minute peek).
    func isInLastMinute(at now: Date) -> Bool {
        isCounting && remaining(at: now) <= TimerLimits.lastMinute
    }

    /// The last 10 s of a RUNNING timer: the digits pulse once per second.
    func isInPulseWindow(at now: Date) -> Bool {
        isRunning && remaining(at: now) <= TimerLimits.pulseWindow && remaining(at: now) > 0
    }

    // MARK: Transitions (each returns whether anything changed)

    /// Starts a new run of `duration` seconds, replacing whatever was there.
    mutating func start(duration: TimeInterval, now: Date) {
        let d = Self.clamp(duration)
        phase = .running(endDate: now.addingTimeInterval(d))
        total = d
    }

    @discardableResult mutating func pause(now: Date) -> Bool {
        guard case .running(let end) = phase else { return false }
        let left = end.timeIntervalSince(now)
        guard left > 0 else { return false }          // already over: `finish` handles it
        phase = .paused(remaining: left)
        return true
    }

    @discardableResult mutating func resume(now: Date) -> Bool {
        guard case .paused(let left) = phase else { return false }
        phase = .running(endDate: now.addingTimeInterval(left))
        return true
    }

    @discardableResult mutating func stop() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        total = 0
        return true
    }

    /// "+1 min". Running/paused: adds to the time left and to `total`. Done: starts a new 1-minute timer.
    @discardableResult mutating func addTime(_ seconds: TimeInterval, now: Date) -> Bool {
        switch phase {
        case .idle:
            return false
        case .done:
            start(duration: seconds, now: now)
            return true
        case .running, .paused:
            return adjust(by: seconds, now: now)
        }
    }

    /// Scroll / VoiceOver ±1 min on a running or paused timer. A decrease that would leave less than one second is
    /// refused (no detent haptic); an increase past the maximum is clamped, and refused when nothing changes.
    @discardableResult mutating func adjust(by delta: TimeInterval, now: Date) -> Bool {
        let left = remaining(at: now)
        guard isCounting, left > 0 else { return false }
        let target = min(left + delta, TimerLimits.maximum)
        guard target >= TimerLimits.minimum, target != left else { return false }
        total = min(max(total + (target - left), target), TimerLimits.maximum)
        switch phase {
        case .running: phase = .running(endDate: now.addingTimeInterval(target))
        case .paused: phase = .paused(remaining: target)
        case .idle, .done: break
        }
        return true
    }

    /// The deadline passed: a running timer becomes done at its end date.
    @discardableResult mutating func finish() -> Bool {
        guard case .running(let end) = phase else { return false }
        phase = .done(at: end)
        return true
    }

    /// "Timer done" ran its minute (or was stopped): back to idle.
    @discardableResult mutating func expire() -> Bool {
        guard isDone else { return false }
        phase = .idle
        total = 0
        return true
    }

    // MARK: Launch, wake and clock changes

    /// What a persisted (or long-asleep) timer means at `now`: a passed deadline becomes "done" only if it passed at
    /// most `doneLinger` ago; older endings, and done states older than that, fall back to idle.
    func reconciled(at now: Date) -> TimerState {
        var copy = self
        if case .running(let end) = phase, end <= now { copy.finish() }
        if case .done(let at) = copy.phase, now.timeIntervalSince(at) >= TimerLimits.doneLinger { copy.expire() }
        if case .paused(let left) = copy.phase, left <= 0 { copy.stop() }
        return copy
    }

    static func clamp(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration.rounded(), TimerLimits.minimum), TimerLimits.maximum)
    }
}
