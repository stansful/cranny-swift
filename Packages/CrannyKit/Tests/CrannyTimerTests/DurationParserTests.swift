import Testing
@testable import CrannyTimer

@Suite struct DurationParserTests {
    @Test(arguments: [
        ("25", 1500), ("1", 60), ("90s", 90), ("90 s", 90), ("90 sec", 90), ("45 seconds", 45),
        ("5m", 300), ("5 min", 300), ("10 minutes", 600), ("1h", 3600), ("2 hours", 7200),
        ("1h30m", 5400), ("1h 30m", 5400), ("1h30", 5400), ("1m30s", 90), ("1m30", 90), ("1h 2m 3s", 3723), ("1h30m15", 5415),
        ("2.5", 150), ("2,5", 150), (".5", 30), ("1.5h", 5400), ("0.5m", 30),
        ("1:30", 90), ("0:45", 45), ("25:00", 1500), ("1:30:00", 5400), ("23:59:59", 86399),
        ("  25  ", 1500), ("25M", 1500), ("90S", 90),
        ("90с", 90), ("90 сек", 90), ("25 мин", 1500), ("25м", 1500), ("1ч", 3600), ("1ч 30м", 5400),
        ("1 час 30 минут", 5400), ("2 минуты", 120), ("5 минут", 300), ("1 минуту", 60), ("30 секунд", 30),
        ("25 мин.", 1500),
    ])
    func parses(_ text: String, _ seconds: Int) {
        #expect(DurationParser.seconds(from: text) == seconds, "\(text)")
    }

    @Test(arguments: [
        "", " ", "abc", "0", "0s", "0:00", "-5", "25x", "1:5", "1:60", "1:30:5", "1::30", ":30", "1:", "1:2:3:4",
        "30m1h", "1m1m", "5 5", "1h30s15", "1.2.3", ".", "24:00:00", "1441", "25 lightyears", "s", "мин",
    ])
    func rejects(_ text: String) {
        #expect(DurationParser.seconds(from: text) == nil, "\(text)")
    }

    @Test func acceptsOnlyCharactersThatCanFormADuration() {
        for c in "0123456789.,: hmsHMinutesecondsчсмминсекунд" {
            #expect(DurationParser.accepts(c), "\(c)")
        }
        for c in "xyz!?/+-=qQжЖ" {
            #expect(!DurationParser.accepts(c), "\(c)")
        }
    }
}
