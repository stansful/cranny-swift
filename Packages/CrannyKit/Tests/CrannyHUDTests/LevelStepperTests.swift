// The level grid: 1/16 and 1/64 steps, snapping, ends and Float32 noise (R3 §1.5).
import Testing
@testable import CrannyHUD

@Suite struct LevelStepperTests {
    @Test func sixteenStepsCoverTheRange() {
        var level = 0.0
        for _ in 0..<16 { level = LevelStepper.step(level, up: true, fine: false) }
        #expect(level == 1)
        for _ in 0..<16 { level = LevelStepper.step(level, up: false, fine: false) }
        #expect(level == 0)
    }

    @Test func fineStepsAreQuarterSteps() {
        #expect(LevelStepper.stepSize(fine: true) == 1.0 / 64)
        var level = 0.5
        for _ in 0..<4 { level = LevelStepper.step(level, up: true, fine: true) }
        #expect(level == 0.5625)                               // four quarter steps = one standard step
        #expect(LevelStepper.step(0.5, up: false, fine: true) == 0.484375)
    }

    @Test func offGridLevelsSnapInTheDirectionOfThePress() {
        #expect(LevelStepper.step(0.45, up: true, fine: false) == 0.5)
        #expect(LevelStepper.step(0.45, up: false, fine: false) == 0.4375)
        #expect(LevelStepper.step(0.62, up: true, fine: false) == 0.625)
        #expect(LevelStepper.step(0.62, up: false, fine: false) == 0.5625)
    }

    @Test func float32NoiseCountsAsOnTheGrid() {
        let sevenSixteenths = Double(Float32(0.43749997))          // how CoreAudio can hand back 7/16
        #expect(LevelStepper.step(sevenSixteenths, up: true, fine: false) == 0.5)
        #expect(LevelStepper.step(sevenSixteenths, up: false, fine: false) == 0.375)
        #expect(LevelStepper.step(0.4375001, up: false, fine: false) == 0.375)
    }

    @Test func staysInsideTheRange() {
        #expect(LevelStepper.step(1, up: true, fine: false) == 1)
        #expect(LevelStepper.step(0, up: false, fine: true) == 0)
        #expect(LevelStepper.step(1.2, up: true, fine: false) == 1)
        #expect(LevelStepper.step(-0.3, up: false, fine: false) == 0)
        #expect(LevelStepper.step(.nan, up: true, fine: false) == 0.0625)
    }

    @Test func limits() {
        #expect(LevelStepper.limit(from: 0.9375, to: 1, up: true) == .reached(.top))
        #expect(LevelStepper.limit(from: 1, to: 1, up: true) == .pressedPast(.top))
        #expect(LevelStepper.limit(from: 0.0625, to: 0, up: false) == .reached(.bottom))
        #expect(LevelStepper.limit(from: 0, to: 0, up: false) == .pressedPast(.bottom))
        #expect(LevelStepper.limit(from: 0.5, to: 0.5625, up: true) == nil)
        #expect(LevelStepper.limit(from: 1, to: 0.9375, up: false) == nil)
        #expect(LevelStepper.limit(from: 0.99999994, to: 1, up: true) == .pressedPast(.top))
    }

    @Test func percent() {
        #expect(LevelStepper.percent(0.62) == 62)
        #expect(LevelStepper.percent(0.625) == 63)
        #expect(LevelStepper.percent(0) == 0)
        #expect(LevelStepper.percent(1) == 100)
        #expect(LevelStepper.percent(1.5) == 100)
    }
}
