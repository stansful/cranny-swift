import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTimer

@MainActor @Suite struct TimerModuleTests {
    @Test func registersEveryContributionWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(TimerModule.self)
        #expect(registry.registeringModule == nil)
        #expect(registry.widget(.timer)?.sizes == WidgetSizes(minimum: 2, preferred: 2, maximum: 3))
        #expect(registry.widget(.timer)?.hasOptions == true)
        #expect(registry.activities.map(\.id) == [.timerRunning, .timerDone])
        #expect(registry.activity(.timerRunning)?.activity.isActive == false)   // nothing runs at launch
        #expect(registry.activity(.timerDone)?.activity.isActive == false)
        #expect(registry.activity(.timerRunning)?.makeOptions != nil)
        #expect(registry.shortcuts.map(\.id) == [.startTimer])
        #expect(registry.shortcuts.first?.defaultCombo == nil)                  // off until the user sets one
        #expect(registry.commandProviders.count == 1)
        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)
        // register(in:) does no file I/O: the timer directory does not exist yet.
        let directory = registry.services.paths.root.appending(path: "timer")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func activityKindsMatchTheDesign() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(TimerModule.self)
        let running = try #require(registry.activity(.timerRunning)).kind
        #expect(running.defaultPriority == .ongoing)
        #expect(!running.canPeekOnChange)                                       // its peek is "Peek at one minute left"
        let done = try #require(registry.activity(.timerDone)).kind
        #expect(done.defaultPriority == .alert)
        #expect(done.module == .timer)
    }

    @Test func samplesAreActiveAndIndependentOfTheRealModel() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(TimerModule.self)
        let runningSample = try #require(registry.activity(.timerRunning)?.makeSample?())
        let doneSample = try #require(registry.activity(.timerDone)?.makeSample?())
        #expect(runningSample.isActive)
        #expect(doneSample.isActive)
        #expect(doneSample.delight == .emberBurst)
        #expect(registry.activity(.timerRunning)?.activity.isActive == false)   // the real timer is untouched
    }

    @Test func runningActivityFollowsTheModel() {
        let h = TimerHarness()
        let activity = TimerRunningActivity(model: h.model)
        #expect(!activity.isActive)
        h.model.start(seconds: 300)
        #expect(activity.isActive)
        #expect(activity.priority == .ongoing)
        #expect(activity.slot == .medium)
        #expect(activity.palette == .timer)
        #expect(activity.opensWidget == .timer)
        #expect(activity.revision == 1)
        #expect(activity.actions.map(\.id) == ["pause", "stop", "addMinute"])
        h.model.pause()
        #expect(activity.isActive)
        #expect(activity.actions.first?.id == "resume")
        activity.actions.first?.perform()
        #expect(h.model.state.isRunning)
        activity.actions[1].perform()
        #expect(!activity.isActive)
    }

    @Test func doneActivityIsATransientAlertWithTheEmberBurst() {
        let h = TimerHarness()
        let activity = TimerDoneActivity(model: h.model)
        h.model.start(seconds: 20)
        h.scheduler.fire(advancing: h.clock)
        #expect(activity.isActive)
        #expect(activity.priority == .alert)
        #expect(activity.revision == 1)
        #expect(activity.expiresAt == t0.addingTimeInterval(20 + TimerLimits.doneLinger))
        #expect(activity.delight == .emberBurst)
        #expect(activity.actions.map(\.id) == ["stop", "addMinute"])
        activity.actions[1].perform()                                           // +1 min = a new 1-minute timer
        #expect(!activity.isActive)
        #expect(h.model.state.isRunning)
    }

    @Test func largeTextSwitchesTheBandToItsGlyphForm() {
        let h = TimerHarness()
        let running = TimerRunningActivity(model: h.model), done = TimerDoneActivity(model: h.model)
        #expect(running.slot == .medium && done.slot == .medium)
        for size in [CrannyTextSize.large, .extraLarge] {
            h.services.settings[CoreSettings.textSize] = size
            #expect(running.slot == .glyph && done.slot == .glyph)
        }
        h.services.settings[CoreSettings.textSize] = .small
        #expect(running.slot == .medium)
    }

    @Test func everyPlacementDraws() throws {
        let running = TimerHarness()
        running.model.start(seconds: 300)
        let done = TimerHarness()
        done.model.start(seconds: 20)
        done.scheduler.fire(advancing: done.clock)
        let activities: [any LiveActivity] = [TimerRunningActivity(model: running.model), TimerDoneActivity(model: done.model)]
        for activity in activities {
            for placement in ActivityPlacement.allCases {
                let renderer = ImageRenderer(content: activity.view(for: placement)
                    .foregroundStyle(.white)
                    .frame(width: 400, height: NotchLayout.peekRow)
                    .crannyThemeRoot(CrannyTheme()))
                renderer.scale = 2
                let image = try #require(renderer.cgImage, "\(activity.id) \(placement) did not render")
                #expect(drawnPixels(image) > 50, "\(activity.id) \(placement) drew nothing")
            }
        }
    }

    /// Pixels with any coverage (the renderer's background is transparent).
    private func drawnPixels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return 0 }
        return stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] > 0 }
    }
}
