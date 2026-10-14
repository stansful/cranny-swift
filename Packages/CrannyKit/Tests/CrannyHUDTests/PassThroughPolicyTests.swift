// The pass-through policy table and the config snapshot it reads (ARCHITECTURE.md §7.1, §10.10).
import CrannyCore
import Testing
@testable import CrannyHUD

@Suite struct PassThroughPolicyTests {
    private func route(_ key: MediaKey, _ modifiers: MediaKeyModifiers = [], config: HUDTapConfig = .all) -> KeyRoute {
        PassThroughPolicy.route(MediaKeyEvent(key: key, isDown: true, modifiers: modifiers), config: config)
    }

    @Test func routesEveryOwnedKey() {
        #expect(route(.soundUp) == .handle(.volume, .up))
        #expect(route(.soundDown) == .handle(.volume, .down))
        #expect(route(.mute) == .handle(.volume, .toggle))
        #expect(route(.brightnessUp) == .handle(.brightness, .up))
        #expect(route(.brightnessDown) == .handle(.brightness, .down))
        #expect(route(.illuminationUp) == .handle(.keyboardBacklight, .up))
        #expect(route(.illuminationDown) == .handle(.keyboardBacklight, .down))
        #expect(route(.illuminationToggle) == .handle(.keyboardBacklight, .toggle))
    }

    @Test func leavesMediaTransportToMacOS() {
        for key in [MediaKey.play, .next, .previous, .fast, .rewind] {
            #expect(route(key) == .passThrough(.notOurKey))
        }
    }

    @Test func passesEverythingWhenNotReplacing() {
        for key in MediaKey.allCases {
            #expect(route(key, config: .off) == .passThrough(.notReplacing))
        }
    }

    @Test func passesDisabledKinds() {
        var config = HUDTapConfig.all
        config.handlesVolume = false
        #expect(route(.soundUp, config: config) == .passThrough(.kindDisabled))
        #expect(route(.mute, config: config) == .passThrough(.kindDisabled))
        #expect(route(.brightnessUp, config: config) == .handle(.brightness, .up))
        config = .all
        config.handlesBrightness = false
        #expect(route(.brightnessDown, config: config) == .passThrough(.kindDisabled))
        config = .all
        config.handlesKeyboardBacklight = false
        #expect(route(.illuminationToggle, config: config) == .passThrough(.kindDisabled))
    }

    @Test func passesWhileTheHUDCannotBeShown() {
        var config = HUDTapConfig.all
        config.isPresentable = false
        #expect(route(.soundUp, config: config) == .passThrough(.notPresentable))
        #expect(route(.brightnessUp, config: config) == .passThrough(.notPresentable))
    }

    @Test func optionAloneOpensSettingsButOptionShiftIsFine() {
        #expect(route(.soundUp, .option) == .passThrough(.optionOpensSettings))
        #expect(route(.brightnessDown, .option) == .passThrough(.optionOpensSettings))
        #expect(route(.mute, .option) == .passThrough(.optionOpensSettings))
        #expect(route(.soundUp, [.option, .shift]) == .handle(.volume, .up))
        #expect(route(.soundUp, .shift) == .handle(.volume, .up))
        #expect(route(.soundUp, [.option, .command]) == .passThrough(.optionOpensSettings))
    }
}

@Suite struct HUDTapConfigTests {
    private func inputs(_ change: (inout HUDTapConfig.Inputs) -> Void = { _ in }) -> HUDTapConfig.Inputs {
        var inputs = HUDTapConfig.Inputs(replaceSystemHUD: true, volume: true, brightness: true, keyboardBacklight: true,
                                         activityEnabled: true, accessibilityGranted: true, screenLocked: false,
                                         displaysAsleep: false, fullScreenInFront: false, fullScreenPolicy: .alertsAndHUD,
                                         shellCanPresentHUD: true)
        change(&inputs)
        return inputs
    }

    @Test func everythingOnInstallsTheTap() {
        let config = HUDTapConfig(inputs())
        #expect(config == .all)
        #expect(config.wantsTap)
    }

    @Test func neverTwoHUDsNeverNone() {
        // Without any of the three, there is no tap: macOS keeps its HUD and Cranny draws none.
        #expect(!HUDTapConfig(inputs { $0.replaceSystemHUD = false }).wantsTap)
        #expect(!HUDTapConfig(inputs { $0.accessibilityGranted = false }).wantsTap)
        #expect(!HUDTapConfig(inputs { $0.activityEnabled = false }).wantsTap)
        #expect(HUDTapConfig(inputs { $0.accessibilityGranted = false }) == HUDTapConfig(
            isReplacing: false, handlesVolume: false, handlesBrightness: false, handlesKeyboardBacklight: false, isPresentable: true))
    }

    @Test func noKindsMeansNoTap() {
        let config = HUDTapConfig(inputs { $0.volume = false; $0.brightness = false; $0.keyboardBacklight = false })
        #expect(config.isReplacing)
        #expect(!config.wantsTap)
    }

    @Test func presentability() {
        #expect(!HUDTapConfig(inputs { $0.screenLocked = true }).isPresentable)
        #expect(!HUDTapConfig(inputs { $0.displaysAsleep = true }).isPresentable)
        #expect(!HUDTapConfig(inputs { $0.fullScreenInFront = true; $0.fullScreenPolicy = .hideAll }).isPresentable)
        #expect(HUDTapConfig(inputs { $0.fullScreenInFront = true; $0.fullScreenPolicy = .alertsAndHUD }).isPresentable)
        #expect(HUDTapConfig(inputs { $0.fullScreenInFront = true; $0.fullScreenPolicy = .showAll }).isPresentable)
        #expect(HUDTapConfig(inputs { $0.fullScreenPolicy = .hideAll }).isPresentable)
        // A locked screen keeps the tap (it only passes keys through), so unlocking needs no re-creation.
        #expect(HUDTapConfig(inputs { $0.screenLocked = true }).wantsTap)
    }

    @Test func aDisplayThatWouldNotDrawTheHUDGetsNoKeys() {
        // The pointer's display has General ▸ Displays ▸ HUD off (or no visible panel): the shell says so, and the
        // keys go to macOS, so its HUD shows instead of none (D10).
        let hidden = HUDTapConfig(inputs { $0.shellCanPresentHUD = false })
        #expect(!hidden.isPresentable)
        #expect(hidden.wantsTap)                                    // moving back to a HUD display needs no new tap
        #expect(PassThroughPolicy.route(MediaKeyEvent(key: .soundUp, isDown: true), config: hidden)
                == .passThrough(.notPresentable))
        #expect(PassThroughPolicy.route(MediaKeyEvent(key: .brightnessDown, isDown: true), config: hidden)
                == .passThrough(.notPresentable))
        let shown = HUDTapConfig(inputs { $0.shellCanPresentHUD = true })
        #expect(shown.isPresentable)
        #expect(PassThroughPolicy.route(MediaKeyEvent(key: .soundUp, isDown: true), config: shown) == .handle(.volume, .up))
    }

    @Test func boxHoldsTheLatestSnapshot() {
        let box = HUDTapConfigBox()
        #expect(box.current == .off)
        box.update(.all)
        #expect(box.current == .all)
    }
}
