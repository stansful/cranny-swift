import Foundation
import Testing
@testable import CrannyTimer

@Suite struct TimerFormatTests {
    let en = Locale(identifier: "en_US")
    let ru = Locale(identifier: "ru_RU")

    @Test func clockSwitchesToHoursFromAnHourOn() {
        #expect(TimerFormat.clock(0, locale: en) == "0:00")
        #expect(TimerFormat.clock(299, locale: en) == "4:59")
        #expect(TimerFormat.clock(1500, locale: en) == "25:00")
        #expect(TimerFormat.clock(3599, locale: en) == "59:59")
        #expect(TimerFormat.clock(3600, locale: en) == "1:00:00")
        #expect(TimerFormat.clock(-5, locale: en) == "0:00")
        #expect(TimerFormat.clock(299, locale: ru) == "4:59")
    }

    @Test func spokenAndShortAreLocalizedByFoundation() {
        #expect(TimerFormat.spoken(299, locale: en) == "4 minutes, 59 seconds")
        #expect(TimerFormat.spoken(299, locale: ru) == "4 минуты 59 секунд")
        #expect(TimerFormat.short(1500, locale: en) == "25 min")
        #expect(TimerFormat.short(1500, locale: ru) == "25 мин")
        #expect(TimerFormat.short(90, locale: en) == "1m 30s")                    // two units: the narrow form
        #expect(TimerFormat.short(3600, locale: en) == "1 hr")
    }

    @Test func presetFacesSplitNumberAndUnit() {
        #expect(TimerFormat.presetFace(60, locale: en) == ("1", .minutes))
        #expect(TimerFormat.presetFace(1500, locale: en) == ("25", .minutes))
        #expect(TimerFormat.presetFace(7200, locale: en) == ("2", .hours))
        #expect(TimerFormat.presetFace(5400, locale: en) == ("90", .minutes))
        #expect(TimerFormat.presetFace(45, locale: en) == ("45", .seconds))
        #expect(TimerFormat.presetFace(90, locale: en) == ("1:30", .clock))
    }

    @Test func endTimeFollowsTheLocaleClock() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)                    // 08:53:20 UTC
        let utcEN = TimerFormat.time(date, locale: en)
        let utcRU = TimerFormat.time(date, locale: ru)
        #expect(utcEN.contains(":"))
        #expect(utcRU.contains(":"))
        #expect(!utcRU.contains("AM") && !utcRU.contains("PM"))                  // 24-hour in Russian
    }
}
