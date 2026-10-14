// CrannyCore/Services/Announcer.swift
// The app's VoiceOver announcements, through one rate limit (DESIGN.md §16: P1 alerts and results, at most one per
// 10 s for the whole app — not per module).
import Foundation
import SwiftUI

/// Posts VoiceOver announcements (`services.announcer`). Alerts and results share ONE limit of one per
/// `interval`, whichever module posts them, so a pipeline result, a shortcut result and a P1 alert can never be
/// announced back to back. Feedback the user just asked for (a layout edit, Settings' Undo) bypasses the limit. The HUD
/// keeps its own rule (announced on settle, DESIGN.md §16) and does not use this.
@MainActor public final class Announcer {
    /// What an announcement reports.
    public nonisolated enum Kind: Sendable {
        /// A P1 activity arrived (timer done, meeting in 1 minute, device connected, low battery).
        case alert
        /// Work the user started elsewhere finished (a Tray pipeline, a shortcut run from ⌘K or a hidden tile).
        case result
        /// The direct answer to the user's own action, which VoiceOver users need every time: never rate-limited.
        case feedback
    }

    /// The shared limit for `.alert` and `.result` (DESIGN.md §16).
    public static let interval: TimeInterval = 10

    private let post: @MainActor (String) -> Void
    private let now: @MainActor () -> TimeInterval
    private var lastLimited: TimeInterval?

    /// `post` delivers the text (tests record it); `now` is a monotonic clock in seconds.
    public init(post: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() },
                now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.post = post
        self.now = now
    }

    /// Posts `text` unless it is empty or, for an alert or result, another alert or result was posted less than
    /// `interval` ago (it is dropped, not queued: the notch still shows it). Returns whether it was posted.
    @discardableResult
    public func announce(_ text: String, kind: Kind) -> Bool {
        guard !text.isEmpty else { return false }
        if kind != .feedback {
            let time = now()
            if let lastLimited, time - lastLimited < Self.interval { return false }
            lastLimited = time
        }
        post(text)
        return true
    }
}
