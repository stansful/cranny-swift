// WP16: Pause Live Activities (`PauseController`, `PauseStatus`, the menu's status line) and Demo mode.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell

private func berlinCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
}

private func date(_ calendar: Calendar, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
}

@Test func pauseDeadlinesFollowTheMenuChoices() {
    let calendar = berlinCalendar()
    let now = date(calendar, 14, 14, 42)
    #expect(PauseDuration.oneHour.deadline(from: now, calendar: calendar) == date(calendar, 14, 15, 42))
    #expect(PauseDuration.untilTomorrow.deadline(from: now, calendar: calendar) == date(calendar, 15, 0))
    #expect(PauseDuration.untilResumed.deadline(from: now, calendar: calendar) == .distantFuture)
    // Across the end of daylight saving time (25 October 2026 in Berlin) "tomorrow" is still local midnight.
    let beforeDST = date(calendar, 25, 1)
    #expect(PauseDuration.untilTomorrow.deadline(from: beforeDST, calendar: calendar) == date(calendar, 26, 0))
}

@Test func pauseStatusSaysWhenItEnds() {
    let calendar = berlinCalendar()
    let now = date(calendar, 14, 14, 42)
    #expect(PauseStatus(pausedUntil: nil, now: now, calendar: calendar) == .notPaused)
    #expect(PauseStatus(pausedUntil: date(calendar, 14, 14), now: now, calendar: calendar) == .notPaused)        // ended
    #expect(PauseStatus(pausedUntil: date(calendar, 14, 15, 42), now: now, calendar: calendar) == .untilLaterToday(date(calendar, 14, 15, 42)))
    #expect(PauseStatus(pausedUntil: date(calendar, 15, 0), now: now, calendar: calendar) == .untilTomorrow)
    let lateNight = date(calendar, 14, 23, 30)
    #expect(PauseStatus(pausedUntil: date(calendar, 15, 0, 30), now: lateNight, calendar: calendar) == .untilDate(date(calendar, 15, 0, 30)))
    #expect(PauseStatus(pausedUntil: .distantFuture, now: now, calendar: calendar) == .untilResumed)
    #expect(!PauseStatus.notPaused.isPaused && PauseStatus.untilResumed.isPaused)
}

@Test func pauseStatusLinesAreLocalizedSentences() {
    let calendar = berlinCalendar()
    let laterToday = date(calendar, 14, 15, 42)
    let later = PauseMenu.caption(.untilLaterToday(laterToday))
    #expect(later.contains(laterToday.formatted(date: .omitted, time: .shortened)))
    // A one-hour pause started at 23:30 ends on the next day: the line names the weekday and the time.
    let nextDay = date(calendar, 15, 0, 30)
    let other = PauseMenu.caption(.untilDate(nextDay))
    #expect(other.contains(nextDay.formatted(.dateTime.weekday(.abbreviated))))
    #expect(other.contains(nextDay.formatted(date: .omitted, time: .shortened)))
    #expect(other != PauseMenu.caption(.untilLaterToday(nextDay)))
    #expect(!PauseMenu.caption(.untilTomorrow).isEmpty && !PauseMenu.caption(.untilResumed).isEmpty)
    #expect(PauseMenu.caption(.untilTomorrow) != PauseMenu.caption(.untilResumed))
    #expect(PauseMenu.caption(.notPaused).isEmpty)
}

@Test func pauseAndResumeWriteTheOnlyKey() {
    let settings = CrannyServices.preview().settings
    let now = Date()
    let pause = PauseController(settings: settings, now: { now })
    #expect(!pause.isPaused && pause.status == .notPaused)
    pause.pause(.oneHour)
    #expect(settings[CoreSettings.pausedUntil] == now.addingTimeInterval(3600) && pause.isPaused)
    pause.resume()
    #expect(settings[CoreSettings.pausedUntil] == nil && settings.isDefault(CoreSettings.pausedUntil))
    pause.toggle()                                                                  // the shortcut: pause for 1 hour …
    #expect(pause.pausedUntil == now.addingTimeInterval(3600))
    pause.toggle()                                                                  // … or resume
    #expect(!pause.isPaused)
    pause.pause(.untilResumed)
    #expect(pause.status == .untilResumed)
}

@Test func anEndedPauseIsClearedAtLaunchAndWhenItEnds() async throws {
    let settings = CrannyServices.preview().settings
    settings[CoreSettings.pausedUntil] = Date().addingTimeInterval(-60)          // ended while Cranny was not running
    let pause = PauseController(settings: settings)
    pause.start()
    defer { pause.stop() }
    #expect(settings[CoreSettings.pausedUntil] == nil)

    settings[CoreSettings.pausedUntil] = Date().addingTimeInterval(0.1)
    #expect(pause.isPaused)
    for _ in 0..<60 where settings[CoreSettings.pausedUntil] != nil { try await Task.sleep(for: .milliseconds(50)) }
    #expect(settings[CoreSettings.pausedUntil] == nil)                             // one sleep to the deadline
}

@Test func demoModeWritesItsKeyAndBadgesTheIcon() async throws {
    final class Badge { var shown: Bool? }
    let settings = CrannyServices.preview().settings
    let demo = DemoMode(settings: settings)
    let badge = Badge()
    demo.start { badge.shown = $0 }
    defer { demo.stop() }
    #expect(!demo.isOn && badge.shown == false)
    demo.toggle()
    #expect(settings[CoreSettings.demoMode] && demo.isOn)
    for _ in 0..<40 where badge.shown != true { try await Task.sleep(for: .milliseconds(25)) }
    #expect(badge.shown == true)
    settings.resetAll()                                                             // Reset All turns it off too
    for _ in 0..<40 where badge.shown != false { try await Task.sleep(for: .milliseconds(25)) }
    #expect(!demo.isOn && badge.shown == false)
}

/// The label reads the shared badge state (no suspension between the writes and the reads below).
@Test func theMenuBarIconFollowsTheBadgeState() {
    let before = MenuBarIcon.showsDemoBadge
    defer { MenuBarIcon.showsDemoBadge = before }
    MenuBarIcon.showsDemoBadge = true
    #expect(MenuBarIcon.image === MenuBarIcon.badged && MenuBarIcon.accessibilityLabel != "Cranny")
    MenuBarIcon.showsDemoBadge = false
    #expect(MenuBarIcon.image === MenuBarIcon.plain && MenuBarIcon.accessibilityLabel == "Cranny")
}

@Test func theDemoBadgeIsADotCutOutOfTheCorner() throws {
    let plain = try #require(MenuBarIcon.plain.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let badged = try #require(MenuBarIcon.badged.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(MenuBarIcon.badged.isTemplate && MenuBarIcon.badged.size == MenuBarIcon.size)
    func alpha(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> UInt8 {
        // Sample one point (top-left origin, in points) of the rendered template.
        let scale = CGFloat(image.width) / MenuBarIcon.size.width
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.translateBy(x: -x * scale, y: -(CGFloat(image.height) - y * scale))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.data?.load(fromByteOffset: 3, as: UInt8.self) ?? 0
    }
    #expect(alpha(badged, 16, 2) > 200)                    // the dot …
    #expect(alpha(badged, 15.2, 2.8) > 200 && alpha(plain, 15.2, 2.8) < 30)        // … inside the corner
    #expect(alpha(badged, 13.4, 0.75) < 60)                // the 1-pt gap cuts the outline next to the dot
    #expect(alpha(plain, 13.4, 0.75) > 120)
    #expect(alpha(badged, 1, 7) == alpha(plain, 1, 7))     // the rest is unchanged
}
