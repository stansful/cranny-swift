import Testing
@testable import CrannyTimer

@Suite struct TimerKeyMapTests {
    func press(_ keys: [TimerKey], phase: TimerKeyMap.Phase = .idle, hasDraft: Bool = false)
        -> (entry: String, commands: [TimerKeyCommand], handled: [Bool]) {
        var entry = "", commands: [TimerKeyCommand] = [], handled: [Bool] = []
        for key in keys {
            let r = TimerKeyMap.handle(key, entry: entry, phase: phase, hasDraft: hasDraft)
            entry = r.entry
            handled.append(r.handled)
            if r.command != .none { commands.append(r.command) }
        }
        return (entry, commands, handled)
    }

    func typed(_ text: String) -> [TimerKey] { text.map { $0 == " " ? .space : .character($0) } }

    @Test func digitsThenReturnStartThatDuration() {
        #expect(press(typed("25") + [.returnKey]).commands == [.start(seconds: 1500)])
        #expect(press(typed("90s") + [.returnKey]).commands == [.start(seconds: 90)])
        #expect(press(typed("1h 30m") + [.returnKey]).commands == [.start(seconds: 5400)])   // space inside an entry
        #expect(press(typed("90с") + [.returnKey]).commands == [.start(seconds: 90)])        // Russian unit
        #expect(press(typed("25") + [.returnKey]).entry.isEmpty)
    }

    @Test func anInvalidEntryStaysForCorrection() {
        let r = press(typed("9") + [.character("x")])
        #expect(r.entry == "9")                                                  // "x" is not a duration character
        #expect(r.handled == [true, false])
        let bad = press(typed("1:5") + [.returnKey])
        #expect(bad.commands.isEmpty)
        #expect(bad.entry == "1:5")
    }

    @Test func deleteErasesThenResets() {
        #expect(press(typed("25") + [.delete]).entry == "2")
        #expect(press([.delete], phase: .counting).commands == [.stop])
        #expect(press([.delete], phase: .done).commands == [.stop])
        #expect(press([.delete], hasDraft: true).commands == [.clearDraft])
        #expect(press([.delete]).handled == [false])                             // nothing to reset: not ours
    }

    @Test func spaceAndReturnWithoutAnEntry() {
        #expect(press([.space], phase: .counting).commands == [.togglePause])
        #expect(press([.space]).handled == [false])                              // idle: Space is the panel's
        #expect(press([.returnKey]).commands == [.startSetup])
        #expect(press([.returnKey], phase: .counting).commands == [.togglePause])
        #expect(press([.returnKey], phase: .done).commands == [.stop])
        #expect(press([.space]).entry.isEmpty)                                   // no leading space
    }

    @Test func escapeDropsTheEntryFirstThenLetsThePanelClose() {
        let r = press(typed("12") + [.escape, .escape])
        #expect(r.entry.isEmpty)
        #expect(r.handled.suffix(2) == [true, false])
    }

    @Test func arrowsAdjustByAMinute() {
        #expect(press([.up, .down, .down], phase: .counting).commands
                == [.adjust(minutes: 1), .adjust(minutes: -1), .adjust(minutes: -1)])
    }

    @Test func entryLengthIsCapped() {
        let r = press(Array(repeating: .character("1"), count: 40))
        #expect(r.entry.count == DurationParser.maximumLength)
    }

    @Test func otherCharactersAreNotOurs() {
        #expect(press([.character("q")]).handled == [false])
        #expect(press([.character("/")]).handled == [false])
    }

    @Test func aWordTypedOverTheFaceIsNotCaptured() {
        for word in ["note", "test", "hello", "мин", "сон"] {
            let r = press(typed(word))
            #expect(r.entry.isEmpty, "\(word)")
            #expect(r.handled.allSatisfy { !$0 }, "\(word)")                    // every key goes to the panel
        }
        #expect(press([.character(":")]).handled == [false])                    // separators only after a number
        #expect(press([.character(",")]).handled == [false])
        #expect(press(typed("m5")).entry == "5")                                // the unit was not taken first
    }

    @Test func anEntryStartsWithADigitOrAPoint() {
        #expect(press(typed(".5") + [.returnKey]).commands == [.start(seconds: 30)])
        #expect(press(typed("1:30") + [.returnKey]).commands == [.start(seconds: 90)])
        #expect(press(typed("2,5") + [.returnKey]).commands == [.start(seconds: 150)])
        #expect(press(typed("25 мин") + [.returnKey]).commands == [.start(seconds: 1500)])
        #expect(press(typed(". ")).entry == ".")                                // no space before a number
    }

    @Test func canAppendFollowsTheEntry() {
        #expect(DurationParser.canAppend("7", to: ""))
        #expect(DurationParser.canAppend(".", to: ""))
        #expect(!DurationParser.canAppend("m", to: ""))
        #expect(!DurationParser.canAppend("m", to: "."))
        #expect(DurationParser.canAppend("m", to: "5"))
        #expect(DurationParser.canAppend("M", to: "5"))
        #expect(DurationParser.canAppend("с", to: "90"))
        #expect(!DurationParser.canAppend("x", to: "90"))
    }
}
