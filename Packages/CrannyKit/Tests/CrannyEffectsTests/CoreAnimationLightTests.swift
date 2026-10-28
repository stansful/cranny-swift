// Appearance ▸ Quality ▸ Efficient (DESIGN.md §5.7): the Core Animation light. Which path draws what; the layers it
// builds; its clock (paused with the budget, resting under Reduce Motion, resuming where it stopped); palette and level
// changes under the alpha cap; the band; the song-change swell; and that Efficient never builds a renderer, asks Metal
// for a device or gives the process GPU memory.
import AppKit
import CrannyCore
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import CrannyEffects

private func budget(lowPower: Bool = false, reduceMotion: Bool = false, isOpen: Bool = true,
                    onBattery: Bool = false) -> EffectBudget {
    EffectBudget(isOpen: isOpen, onScreen: true, lowPower: lowPower, fullScreenFront: false, reduceMotion: reduceMotion,
                 onBattery: onBattery)
}

// MARK: - Paths

@Test func efficientDrawsTheCoreAnimationLightWithoutAskingForMetal() {
    var asked = false
    func available() -> Bool { asked = true; return true }
    #expect(AmbientPath.resolve(budget: budget(), detail: .efficient, shadersAvailable: available(),
                                layerAllowed: available()) == .coreAnimation)
    #expect(AmbientPath.resolve(budget: budget(reduceMotion: true), detail: .efficient, shadersAvailable: available(),
                                layerAllowed: available()) == .coreAnimation, "Reduce Motion rests the same layers")
    #expect(!asked, "Efficient never asks about the Metal library or layer")
    #expect(AmbientPath.resolve(budget: budget(lowPower: true), detail: .efficient, shadersAvailable: available(),
                                layerAllowed: available()) == .staticHalo, "Low Power keeps the static halo")
    #expect(!asked)
    // Detailed is what it was.
    #expect(AmbientPath.resolve(budget: budget(), detail: .detailed, shadersAvailable: true, layerAllowed: true) == .layer)
    #expect(AmbientPath.resolve(budget: budget(), shadersAvailable: true, layerAllowed: false) == .shader)
    #expect(AmbientPath.resolve(budget: budget(reduceMotion: true), shadersAvailable: true, layerAllowed: true) == .fallback)
    #expect(AmbientPath.coreAnimation.isShader == false)
}

@Test func efficientMomentsPlayTheirStillVariants() {
    var asked = false
    func available() -> Bool { asked = true; return true }
    for b in [budget(), budget(lowPower: true), budget(isOpen: false), budget(onBattery: true)] {
        #expect(MomentPath.resolve(budget: b, detail: .efficient, shadersAvailable: available()) == .reduced)
    }
    #expect(!asked, "a still moment never asks about the Metal library")
    #expect(MomentPath.resolve(budget: budget(), detail: .detailed, shadersAvailable: true) == .shader)
    #expect(MomentPath.resolve(budget: budget(lowPower: true), shadersAvailable: true) == .fallback)
}

/// Callers animate palette changes unless the light cross-fades them itself (Efficient's live Core Animation light).
@Test func onlyTheCoreAnimationLightCrossFadesItsPalettes() {
    #expect(AmbientLayer.crossFadesPalettes(budget: budget(), detail: .efficient, rendering: .automatic))
    #expect(AmbientLayer.crossFadesPalettes(budget: budget(reduceMotion: true), detail: .efficient, rendering: .automatic))
    #expect(!AmbientLayer.crossFadesPalettes(budget: budget(), detail: .efficient, rendering: .inline), "snapshots")
    #expect(!AmbientLayer.crossFadesPalettes(budget: budget(), detail: .detailed, rendering: .automatic))
    #expect(!AmbientLayer.crossFadesPalettes(budget: budget(lowPower: true), detail: .efficient, rendering: .automatic,
                                             qaKeepsRunning: false), "Low Power's halo")
    #expect(AmbientLayer.crossFadesPalettes(budget: budget(lowPower: true), detail: .efficient, rendering: .automatic,
                                            qaKeepsRunning: true), "the Debug effects switch keeps the light, as in the light")
}

@Test func crossFadeFollowsTheColourShiftToken() {
    #expect(AmbientCAFade.motion(.colorShift, personality: .standard, reduceMotion: false)
            == AmbientCAFade(duration: 0.8, curve: .easeInEaseOut))
    #expect(AmbientCAFade.motion(.colorShift, personality: .calm, reduceMotion: true)
            == AmbientCAFade(duration: 0.3, curve: .easeInEaseOut))
    #expect(AmbientCAFade.motion(.colorShift, personality: .instant, reduceMotion: false) == nil)
    #expect(AmbientCAFade.motion(.ambientIn, personality: .standard, reduceMotion: false)
            == AmbientCAFade(duration: 0.5, curve: .easeOut))
}

@Test func clockMathRunsStopsAndResumes() {
    let running = AmbientCAClock.timing(time: 12, running: true, parentNow: 100)
    #expect(AmbientCAClock.time(of: running, parentNow: 100) == 12)
    #expect(abs(AmbientCAClock.time(of: running, parentNow: 102.5) - 14.5) < 1e-9)
    let stopped = AmbientCAClock.timing(time: 14.5, running: false, parentNow: 200)
    #expect(stopped.speed == 0)
    #expect(AmbientCAClock.time(of: stopped, parentNow: 900) == 14.5, "a stopped clock shows its time forever")
    let resumed = AmbientCAClock.timing(time: 14.5, running: true, parentNow: 900)
    #expect(abs(AmbientCAClock.time(of: resumed, parentNow: 901) - 15.5) < 1e-9, "and continues from it")
    #expect(AmbientCAClock.frameRate(interval: 1.0 / 30) == 30)
    #expect(AmbientCAClock.frameRate(interval: 1.0 / 20) == 20)
}

// MARK: - The view

@MainActor @Suite("Core Animation light") struct CoreAnimationLightTests {
    @Test(arguments: [AmbientEffect.aurora, .motes, .tide, .halo])
    func buildsItsLayersAndAnimations(_ effect: AmbientEffect) throws {
        let view = caView(effect, rests: false)
        let built = try #require(view.effect)
        #expect(built.group.superlayer === view.lightLayer)
        #expect(built.content.superlayer === view.clockLayerForTests, "the content runs on the light's clock")
        let expected: Int = switch effect {
        case .aurora: AuroraCA.curtains.count
        case .motes: 2 * MotesCA.motes.count            // a rising track and a dot per mote
        case .tide: TideMath.lineCount
        case .halo: 0
        }
        #expect(built.animatedLayers.count == expected)
        #expect(view.installedFrameRate == 30)
        for layer in built.animatedLayers {
            for key in layer.animationKeys() ?? [] {
                let animation = try #require(layer.animation(forKey: key))
                #expect(animation.repeatCount == .infinity, "\(key) loops")
                #expect(animation.beginTime == AmbientCAClock.epoch)
                #expect(animation.preferredFrameRateRange.maximum == 30, "\(key) asks for the budget's rate")
            }
        }
        #expect(abs(Double(built.group.opacity) - Glow.ambientAlphaCap(.subtle)) < 1e-6)
        #expect(built.group.allowsGroupOpacity)
    }

    /// The budget pauses the light by stopping its clock (closed, occluded, full screen); it resumes where it stopped.
    /// Battery re-installs the animations at 20 fps. Reduce Motion rests it on the resting frame.
    @Test func clockPausesRestsAndResumes() async throws {
        let view = caView(.aurora, time: 7.3, rests: false)
        #expect(view.isClockRunning && view.clockSpeed == 1)
        try await Task.sleep(for: .milliseconds(120))
        var state = try #require(view.state)
        state.interval = nil                                                // paused budget
        view.state = state
        #expect(!view.isClockRunning && view.clockSpeed == 0)
        let stopped = view.lightTime
        #expect(stopped > 7.3 + 0.05, "time ran while the light ran (\(stopped))")
        try await Task.sleep(for: .milliseconds(120))
        #expect(view.lightTime == stopped, "a paused light stands still")
        state.interval = 1.0 / 30
        view.state = state
        #expect(view.isClockRunning && view.clockSpeed == 1)
        #expect(abs(view.lightTime - stopped) < 0.05, "it resumes where it stopped")
        state.interval = 1.0 / 20                                           // on battery
        view.state = state
        #expect(view.installedFrameRate == 20)
        let rate = try #require(view.effect?.animatedLayers.first?.animation(forKey: "drift"))
        #expect(rate.preferredFrameRateRange.maximum == 20)
        state.rests = true                                                  // Reduce Motion / Instant
        view.state = state
        #expect(view.clockSpeed == 0 && abs(view.lightTime - 7.3) < 1e-6)
        state.rests = false
        view.state = state
        #expect(view.clockSpeed == 1 && abs(view.lightTime - 7.3) < 0.05)
    }

    /// A light first shown while the budget pauses it (a full-screen app in front, off screen) stands on its resting
    /// frame, as the Metal light draws one still frame, and runs from there once the budget runs it.
    @Test func aLightFirstShownPausedStandsOnItsRestingFrame() async throws {
        let view = caView(.motes, time: 7.3, interval: nil, rests: false)
        #expect(!view.isClockRunning && view.clockSpeed == 0)
        #expect(abs(view.lightTime - 7.3) < 1e-6)
        try await Task.sleep(for: .milliseconds(120))
        #expect(abs(view.lightTime - 7.3) < 1e-6, "a paused light stands still")
        var state = try #require(view.state)
        state.interval = 1.0 / 30
        view.state = state
        #expect(view.isClockRunning && view.clockSpeed == 1)
        #expect(abs(view.lightTime - 7.3) < 0.05, "it runs from its resting frame")
    }

    /// The fill rises under a mask and fades under Reduce Motion; settled, no mask is left (no offscreen pass).
    @Test func fillMasksOnlyWhileRising() throws {
        let view = caView(.motes, fill: 0.5, rests: false)
        #expect(view.isFillMasked && view.fillOpacity == 1)
        var state = try #require(view.state)
        state.fill = 1
        view.state = state
        #expect(!view.isFillMasked && view.fillOpacity == 1)
        state.fill = 0
        view.state = state
        #expect(!view.isFillMasked && view.fillOpacity == 0)
        state.rests = true
        state.fill = 0.4
        view.state = state
        #expect(!view.isFillMasked && abs(view.fillOpacity - 0.4) < 1e-6)
    }

    /// Palette and level changes recolour the layers and cross-fade them; the cap is the group's opacity.
    @Test func paletteAndLevelChangesCrossFadeUnderTheCap() throws {
        let fade = AmbientCAFade(duration: 0.8, curve: .easeInEaseOut)
        let view = AmbientCANSView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 240)
        view.state = caState(.tide, palette: .afterglow, level: .subtle, crossFade: fade)
        let group = try #require(view.effect?.group)
        #expect(view.lightLayer.animation(forKey: kCATransition) == nil, "the first look does not fade in")
        view.state = caState(.tide, palette: .timer, level: .vivid, crossFade: fade)
        let transition = try #require(view.lightLayer.animation(forKey: kCATransition) as? CATransition)
        #expect(transition.type == .fade && transition.duration == 0.8)
        #expect(abs(Double(group.opacity) - Glow.ambientAlphaCap(.vivid)) < 1e-6)
        #expect(view.effect?.group === group, "a new look keeps the layers")
        let strokes = (group.sublayers ?? []).flatMap(allLayers).compactMap { $0 as? CAShapeLayer }
        #expect(!strokes.isEmpty)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        for stroke in strokes {
            let color = try #require(stroke.strokeColor?.converted(to: sRGB, intent: .defaultIntent, options: nil))
            let c = try #require(color.components)
            #expect(c[3] <= 1)
            #expect(c[0] <= Glow.maxBrightness + 1e-6 && c[1] <= Glow.maxBrightness + 1e-6)
        }
        // Instant: no cross-fade.
        let instant = AmbientCANSView()
        instant.frame = view.frame
        instant.state = caState(.aurora, crossFade: nil)
        instant.state = caState(.aurora, palette: .charging, crossFade: nil)
        #expect(instant.lightLayer.animation(forKey: kCATransition) == nil)
        // A new effect builds new layers.
        view.state = caState(.motes, palette: .timer, level: .vivid, crossFade: fade)
        #expect(view.effect?.group !== group && group.superlayer == nil)
    }

    /// Rendered as the window server would: light where it belongs, the band clear, alpha within the cap.
    @Test(.enabled(if: shadersRun), arguments: [AmbientEffect.aurora, .motes, .tide],
          [AmbienceLevel.subtle, .vivid])
    func rendersUnderTheCapWithTheBandClear(_ effect: AmbientEffect, _ level: AmbienceLevel) throws {
        let cap = Glow.ambientAlphaCap(level)
        for time in [0.0, 7.3, 23.9] {
            let raster = try rasterizeCA(caView(effect, palette: .afterglow, level: level, time: time))
            #expect(raster.peakAlpha > 0.1 * cap, "\(effect) draws light at t = \(time)")
            #expect(raster.peakAlpha <= cap + 2.0 / 255, "\(effect) \(level): peak \(raster.peakAlpha) over the cap")
            #expect(raster.peakAlpha(topRows: 0.40) <= 1.0 / 255, "\(effect): the band stays black")
            #expect(raster.meanAlpha(rows: 0.75, 1) > raster.meanAlpha(rows: 0.40, 0.55), "\(effect) rises from the bottom")
        }
    }

    /// The aurora rises like the Metal one: a flat, soft top from 40 % of the height, no domes, and each 5-% band of
    /// rows within 0.03 of the Metal aurora's mean alpha at both levels (the rise mask is fitted to it, DESIGN.md
    /// §5.7).
    @Test(.enabled(if: shadersRun), arguments: [AmbienceLevel.subtle, .vivid])
    func theAuroraRisesLikeTheMetalOne(_ level: AmbienceLevel) throws {
        let size = CGSize(width: 640, height: 240)
        let efficient = try rasterizeCA(caView(.aurora, palette: .afterglow, level: level, size: size))
        let detailed = try rasterizeLayer(layerState(.aurora, palette: .afterglow, level: level), size: size, scale: 1,
                                          time: 7.3)
        for band in stride(from: 0.40, to: 0.99, by: 0.05) {
            let ours = efficient.meanAlpha(rows: band, band + 0.05)
            let theirs = detailed.meanAlpha(rows: band, band + 0.05)
            #expect(abs(ours - theirs) < 0.03, "\(level), rows \(band): \(ours) against \(theirs)")
        }
    }

    /// A song change that arrived a while ago plays only what is left of the swell, once: rendered as the window
    /// server would, the light is lifted part-way through and back on its place when the swell is over (a `timeOffset`
    /// would wrap around and lift it a second time). A small halo in the middle has no looping animation and stays
    /// inside the view, so only the swell moves it, by its whole lift.
    @Test(.enabled(if: shadersRun)) func aLateSongChangePlaysTheRestOfTheSwellOnce() throws {
        let view = caView(.halo, rests: false)
        var state = try #require(view.state)
        state.halo = HaloPlacement(center: .center, radius: 40)
        view.state = state
        let still = try rasterizeCA(view)
        state.rippleStart = Date().addingTimeInterval(-0.3)
        view.state = state
        let swell = try #require(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey))
        #expect(swell.timeOffset == 0)
        let now = CACurrentMediaTime()
        let lifted = try rasterizeCA(view, at: now + 0.05)          // 0.35 s into the swell: still lifted
        let settled = try rasterizeCA(view, at: now + 0.4)          // 0.7 s: over
        #expect(still.centroidRow - lifted.centroidRow > 1, "lifted (\(still.centroidRow) → \(lifted.centroidRow))")
        #expect(abs(settled.centroidRow - still.centroidRow) < 0.05, "settled (\(settled.centroidRow))")
        // A new change lifts it, and the same change does nothing when something else changes (both while the change
        // is still under way, however long the renders above took); a paused light does not swell, and plays what is
        // left of the swell once it runs.
        state.rippleStart = Date()
        view.state = state
        let fresh = try #require(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey))
        #expect(fresh !== swell, "a new change lifts it")
        state.level = .vivid
        view.state = state
        #expect(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey) === fresh, "each change lifts it once")
        state.interval = nil
        state.rippleStart = Date()
        view.state = state
        #expect(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey) === fresh, "a paused light does not swell")
        state.interval = 1.0 / 30
        view.state = state
        let resumed = try #require(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey))
        #expect(resumed !== fresh, "the change swells once the light runs")
    }

    /// The tide deepens its waves in place for a song change instead of lifting as a block; resting drops it.
    @Test func theTideSwellsInPlace() throws {
        let view = caView(.tide, rests: false)
        var state = try #require(view.state)
        state.rippleStart = Date()
        view.state = state
        let tide = try #require(view.effect as? TideCA)
        #expect(view.swellLayerForTests.animation(forKey: AmbientCA.swellKey) == nil, "no lift")
        #expect(tide.swellingLayers.count == TideMath.lineCount * TideCA.strokes.count)
        let swell = try #require(tide.swellingLayers.first?.animation(forKey: AmbientCA.swellKey)
                                 as? CAKeyframeAnimation)
        #expect(swell.keyPath == "path" && swell.values?.count == TideCA.swellScales.count)
        state.rests = true                                                  // the clock jumps to the resting frame
        view.state = state
        #expect(tide.swellingLayers.isEmpty)
    }

    /// Development snapshots: each effect at Subtle and Vivid on both paths (`CRANNY_SNAPSHOT_DIR`).
    @Test(.enabled(if: shadersRun && SnapshotOutput.directory("Effects") != nil))
    func writesComparisonSnapshots() throws {
        let dir = try #require(SnapshotOutput.directory("Effects"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 640, height: 240)
        for effect in [AmbientEffect.aurora, .motes, .tide] {
            for level in [AmbienceLevel.subtle, .vivid] {
                let ca = try rasterizeCA(caView(effect, palette: .afterglow, level: level, size: size), scale: 2)
                try writePNG(ca, to: dir.appendingPathComponent("\(effect)-\(level)-efficient.png"))
                let metal = try rasterizeLayer(layerState(effect, palette: .afterglow, level: level), size: size,
                                               scale: 2, time: 7.3)
                try writePNG(metal, to: dir.appendingPathComponent("\(effect)-\(level)-detailed.png"))
            }
        }
    }
}

private func allLayers(_ layer: CALayer) -> [CALayer] {
    [layer] + (layer.sublayers ?? []).flatMap(allLayers)
}

// MARK: - No Metal in Efficient

/// The process's GPU memory now: what `footprint` lists as "Owned physical footprint (graphics)", in MB
/// (`task_vm_info.ledger_tag_graphics_footprint`), or nil if the kernel does not report it.
private func graphicsFootprintMB() -> Double? {
    var info = task_vm_info_data_t()
    let full = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    var count = full
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(full)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS, count == full else { return nil }
    return Double(info.ledger_tag_graphics_footprint) / 1_048_576
}

/// What `hostEverything` saw.
private nonisolated struct EverythingProbe: CustomStringConvertible, Sendable {
    var coreAnimation = false, metal = false, queries = 0, renderers = 0
    /// The most GPU memory the process held while everything played, in MB (nil: not reported).
    var graphicsMB: Double?

    var description: String {
        "Core Animation light \(coreAnimation), Metal layer \(metal), device queries \(queries), renderers "
            + "\(renderers), GPU memory \(graphicsMB.map { String(format: "%.1f MB", $0) } ?? "not reported")"
    }
}

/// Hosts the light and every moment with `detail` in a window ordered in off screen, so SwiftUI renders it and a
/// Metal light draws (with the Debug effects switch on, as in a QA run, so even a locked screen does not pause it),
/// plays a song change and lets everything run for 1.5 s, sampling the process's GPU memory. Returns what the
/// hierarchy holds, whether the effects asked Metal for a device or built a renderer, and the most GPU memory seen.
/// Run in a child process (exit tests), where nothing else has touched Metal.
@MainActor private func hostEverything(detail: AmbientDetail) -> EverythingProbe {
    UserDefaults.standard.register(defaults: ["CrannyQAEffectsAlwaysOn": true])   // in memory only
    var theme = CrannyTheme()
    theme.ambientDetail = detail
    var outline = Path()
    outline.move(to: CGPoint(x: 10, y: 4))
    outline.addLine(to: CGPoint(x: 290, y: 30))
    func everything(songChange: Int) -> some View {
        VStack(spacing: 0) {
            FirstLight(palette: .afterglow, level: .vivid, budget: runningBudget) {
                AmbientLayer(palette: .afterglow, level: .vivid, effect: .aurora, energy: 0, budget: runningBudget)
            }
            .songChangeRipple(songChange)
            .frame(width: 640, height: 200)
            MotesField(palette: .timer, level: .subtle, energy: 0, budget: runningBudget).frame(width: 640, height: 120)
            TideField(palette: .charging, level: .vivid, energy: 0, budget: runningBudget)
                .songChangeRipple(songChange)
                .frame(width: 640, height: 120)
            HaloField(palette: .afterglow, level: .subtle, budget: runningBudget).frame(width: 640, height: 120)
            EmberBurst(level: .vivid, budget: runningBudget)
            ChargeSweep(outline: outline, level: .vivid, budget: runningBudget).frame(width: 300, height: 40)
            LiquidNeck(progress: 0.5, budget: runningBudget) {
                HStack(spacing: 6) { Capsule().fill(.black).frame(width: 100, height: 30); Circle().fill(.black).frame(width: 30) }
            }
            .frame(width: 200, height: 40)
        }
        .crannyThemeRoot(theme)
    }
    let host = NSHostingView(rootView: everything(songChange: 1))
    let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 640, height: 900), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    var probe = EverythingProbe()
    for pass in 0..<6 {                                                 // First light and the moments play meanwhile
        if pass == 1 { host.rootView = everything(songChange: 2) }     // a song change: the swell and the ripple
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        if let now = graphicsFootprintMB() { probe.graphicsMB = max(probe.graphicsMB ?? 0, now) }
    }
    func find(_ view: NSView, _ kind: AnyClass) -> Bool {
        view.isKind(of: kind) || view.subviews.contains { find($0, kind) }
    }
    probe.coreAnimation = find(host, AmbientCANSView.self)
    probe.metal = find(host, AmbientMetalNSView.self)
    probe.queries = AmbientGPU.deviceQueries
    probe.renderers = AmbientRenderer.registeredCount
    window.orderOut(nil)
    window.contentView = nil
    window.close()
    return probe
}

/// Efficient draws the light with Core Animation and never builds an `AmbientRenderer`, asks Metal for a device or
/// gives the process GPU memory, whatever plays (First light, the song-change swell, the ember burst, the charge sweep,
/// the liquid neck). The GPU memory check also catches a SwiftUI Canvas, MeshGradient or shader on an Efficient path,
/// which never asks `AmbientGPU`: hosted the same way, an animated `Canvas` alone was measured at ≈ 260 MB, Detailed
/// at ≈ 267 MB and Efficient at 0 (M4 Max, screen locked).
@Test func efficientNeverTouchesTheGPU() async {
    await #expect(processExitsWith: .success) {
        let probe = await MainActor.run { hostEverything(detail: .efficient) }
        guard probe.coreAnimation, !probe.metal, probe.queries == 0, probe.renderers == 0,
              (probe.graphicsMB ?? 0) < 8 else {
            FileHandle.standardError.write(Data("Efficient touched the GPU: \(probe)\n".utf8))
            exit(1)
        }
    }
}

/// The same probe on Detailed (unchanged): the Metal layer, its renderer and the device queries are all there, so the
/// probe above would see them. How much GPU memory the driver charges for them depends on the GPU (≈ 267 MB on an
/// M4 Max), so the 100-MB floor is checked only with `CRANNY_INTEGRATION=1`, never on CI's virtual GPU.
@Test(.enabled(if: shadersRun)) func detailedStillDrawsWithMetal() async {
    await #expect(processExitsWith: .success) {
        let probe = await MainActor.run { hostEverything(detail: .detailed) }
        guard !probe.coreAnimation, probe.metal, probe.queries > 0, probe.renderers > 0,
              !integrationTests || probe.graphicsMB.map({ $0 > 100 }) ?? true else {
            FileHandle.standardError.write(Data("Detailed did not draw with Metal: \(probe)\n".utf8))
            exit(1)
        }
    }
}
