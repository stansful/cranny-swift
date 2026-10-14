// The pure reducer behind Charging and Low battery: one event per meaningful change, nothing at launch.
import Testing
@testable import CrannySystemActivities

@Suite struct PowerTransitionsTests {
    private let thresholds = LowBatteryThresholds([20, 10])

    private func onBattery(_ percent: Int) -> BatteryState { BatteryState(hasBattery: true, percent: percent, isPluggedIn: false) }
    private func onPower(_ percent: Int, charging: Bool = true) -> BatteryState {
        BatteryState(hasBattery: true, percent: percent, isPluggedIn: true, isCharging: charging)
    }

    /// Feeds snapshots in order and returns every event.
    private func events(_ states: [BatteryState], thresholds: LowBatteryThresholds? = nil) -> [[PowerEvent]] {
        var reducer = PowerTransitions()
        return states.map { reducer.update($0, thresholds: thresholds ?? self.thresholds) }
    }

    @Test func launchNeverAlerts() {
        #expect(events([onBattery(8)]) == [[]])
        #expect(events([onPower(50)]) == [[]])
    }

    @Test func plugAndUnplugAreOneEventEach() {
        #expect(events([onBattery(50), onPower(50), onPower(51), onBattery(51)])
                == [[], [.powerConnected], [], [.powerDisconnected]])
    }

    @Test func notChargingStillCountsAsConnected() {
        #expect(events([onBattery(80), onPower(80, charging: false)]) == [[], [.powerConnected]])
    }

    @Test func eachThresholdAlertsOnce() {
        let result = events([onBattery(22), onBattery(21), onBattery(20), onBattery(19), onBattery(11), onBattery(10), onBattery(9)])
        #expect(result == [[], [], [.lowBattery(threshold: 20, isFinal: false)], [], [], [.lowBattery(threshold: 10, isFinal: true)], []])
    }

    @Test func skippingThresholdsAlertsForTheLowestOnly() {
        // Asleep from 25 % to 8 %: one alert, the final one.
        #expect(events([onBattery(25), onBattery(8)]) == [[], [.lowBattery(threshold: 10, isFinal: true)]])
    }

    @Test func wobbleAroundAThresholdDoesNotRepeat() {
        let result = events([onBattery(21), onBattery(20), onBattery(21), onBattery(20), onBattery(22), onBattery(20)])
        #expect(result.flatMap { $0 } == [.lowBattery(threshold: 20, isFinal: false)])
    }

    @Test func risingWellAboveRearms() {
        let result = events([onBattery(21), onBattery(20), onBattery(23), onBattery(20)])
        #expect(result.flatMap { $0 } == [.lowBattery(threshold: 20, isFinal: false), .lowBattery(threshold: 20, isFinal: false)])
    }

    @Test func chargingRearmsEveryWarning() {
        let result = events([onBattery(21), onBattery(20), onPower(20), onBattery(21), onBattery(20)])
        #expect(result == [[], [.lowBattery(threshold: 20, isFinal: false)], [.powerConnected], [.powerDisconnected],
                           [.lowBattery(threshold: 20, isFinal: false)]])
    }

    @Test func unpluggingBelowAFirstWarningIsQuiet() {
        #expect(events([onPower(15), onBattery(15), onBattery(14)]) == [[], [.powerDisconnected], []])
    }

    @Test func unpluggingBelowTheFinalWarningAlerts() {
        #expect(events([onPower(8), onBattery(8)]) == [[], [.powerDisconnected, .lowBattery(threshold: 10, isFinal: true)]])
    }

    @Test func desktopMacsNeverAlert() {
        let desktop = BatteryState.noBattery()
        #expect(events([desktop, BatteryState.noBattery(isPluggedIn: false), desktop]).flatMap { $0 }.isEmpty)
    }

    @Test func noThresholdsNoAlerts() {
        #expect(events([onBattery(30), onBattery(5)], thresholds: LowBatteryThresholds([])).flatMap { $0 }.isEmpty)
    }

    @Test func changingThresholdsKeepsPassedOnesQuiet() {
        var reducer = PowerTransitions()
        _ = reducer.update(onBattery(25), thresholds: thresholds)
        let raised = LowBatteryThresholds([30, 10])
        reducer.reset(thresholds: raised)
        #expect(reducer.update(onBattery(24), thresholds: raised).isEmpty)       // 30 % is already behind us
        #expect(reducer.update(onBattery(10), thresholds: raised) == [.lowBattery(threshold: 10, isFinal: true)])
    }

    // MARK: Thresholds setting

    @Test func thresholdsAreCleanedUp() {
        #expect(LowBatteryThresholds([10, 20, 20, 0, 150, -3]).values == [20, 10])
        #expect(LowBatteryThresholds([10, 20]).final == 10)
        #expect(LowBatteryThresholds([10, 20]).firstWarning == 20)
        #expect(LowBatteryThresholds([10]).firstWarning == nil)
        #expect(LowBatteryThresholds([]).final == nil)
    }

    @Test func settingsEditsKeepTheFinalWarningLowest() {
        let base = LowBatteryThresholds([20, 10])
        #expect(base.replacingFirstWarning(30).values == [30, 10])
        #expect(base.replacingFirstWarning(nil).values == [10])
        #expect(base.replacingFirstWarning(5).values == [10])          // at or below the final one: dropped
        #expect(base.replacingFinal(5).values == [20, 5])
        #expect(base.replacingFinal(20).values == [20])
        #expect(LowBatteryThresholds([40, 20, 10]).replacingFirstWarning(50).values == [50, 20, 10])
    }

    @Test func eachSettingsRowResetsOnlyItsOwnValue() {
        #expect(LowBatteryThresholds.defaults.values == [20, 10])
        let edited = LowBatteryThresholds([30, 5])
        #expect(edited.resettingFirstWarning().values == [20, 5])
        #expect(edited.resettingFinal().values == [30, 10])
        #expect(LowBatteryThresholds([10]).resettingFirstWarning().values == [20, 10])   // from "Off"
        #expect(LowBatteryThresholds([20, 15]).resettingFinal().values == [20, 10])
        // A final warning at 20 % leaves no room for a first warning at 20 %: it stays off.
        #expect(LowBatteryThresholds([20]).resettingFirstWarning().values == [20])
    }

    @Test func criticalOnlyOnBatteryAtOrBelowTheFinalWarning() {
        #expect(thresholds.isCritical(onBattery(10)))
        #expect(!thresholds.isCritical(onBattery(11)))
        #expect(!thresholds.isCritical(onPower(5)))
        #expect(!thresholds.isCritical(BatteryState.noBattery(isPluggedIn: false)))
    }

    @Test func shownFinalWarningKeepsTheRearmHysteresis() {
        // Shown for the current final threshold: stays until the level could alert again (10 + 3 = 13 %).
        #expect(thresholds.isCritical(onBattery(11), shownFor: 10))
        #expect(thresholds.isCritical(onBattery(12), shownFor: 10))
        #expect(!thresholds.isCritical(onBattery(10 + PowerTransitions.rearmMargin), shownFor: 10))
        #expect(!thresholds.isCritical(onPower(10), shownFor: 10))          // connecting power always ends it
        // Shown for a threshold that is no longer the final one (Settings changed it): judged afresh.
        #expect(!thresholds.isCritical(onBattery(11), shownFor: 15))
        #expect(thresholds.isCritical(onBattery(10), shownFor: 15))
    }
}
