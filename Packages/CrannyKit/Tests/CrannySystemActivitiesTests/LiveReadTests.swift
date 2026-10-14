// Read-only calls into the real APIs (no TCC prompt, no state change): they must not crash and must return
// sane values on any Mac, including CI runners without a battery or Bluetooth accessories.
import Foundation
import Testing
@testable import CrannySystemActivities

@Suite struct LiveReadTests {
    @Test func internalBattery() async {
        let state = await PowerSources.snapshot()
        #expect((0...100).contains(state.percent))
        if !state.hasBattery { #expect(state.percent == 0) }
    }

    @Test func accessoryBatteries() async {
        let reports = await AccessoryPowerSources.snapshot()
        #expect(reports.allSatisfy { report in
            [report.batteries.main, report.batteries.left, report.batteries.right, report.batteries.chargingCase]
                .compactMap { $0 }.allSatisfy { (0...100).contains($0.percent) }
        })
    }

    @Test func hidPeripheralsAreExternalOnly() async {
        let peripherals = await HIDPeripheralWatcher.snapshot()
        #expect(peripherals.allSatisfy { !$0.name.localizedCaseInsensitiveContains("internal") })
    }

    @Test func bluetoothAudioOutputs() {
        #expect(AudioDeviceWatcher.bluetoothOutputs().allSatisfy { !$0.id.isEmpty })
    }

    /// Subscribing changes nothing on the Mac: the IOPS run-loop sources attach and detach cleanly.
    @Test @MainActor func powerObserverAttachesTheDetailOnlyWhileFollowed() {
        let observer = PowerObserver()
        observer.setFollowsDetail(true)                    // stopped: ignored
        #expect(!observer.isFollowingDetail)
        observer.start {}
        #expect(observer.isFollowingDetail)                // until the model knows better
        observer.setFollowsDetail(false)
        #expect(!observer.isFollowingDetail)
        observer.setFollowsDetail(true)
        observer.setFollowsDetail(true)                    // idempotent
        #expect(observer.isFollowingDetail)
        observer.start {}                                  // a restart replaces everything
        #expect(observer.isFollowingDetail)
        observer.stop()
        #expect(!observer.isFollowingDetail)
        observer.stop()
    }
}
