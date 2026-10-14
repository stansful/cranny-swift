// CrannyTimer/TimerQA.swift — DEBUG-only visual QA for the Timer (docs/CONTRIBUTING.md "Visual QA hooks"):
//
//   --qa-timer idle                       no timer (the presets)
//   --qa-timer running:<left>[/<total>]   a running timer with <left> seconds left of <total> (default: left)
//   --qa-timer paused:<left>[/<total>]    a paused one
//   --qa-timer done[:<total>]             "Timer done" (no sound)
//   --qa-timer setup:<seconds>            idle with that duration in the set-up ring
//
//   --qa-timer-snapshot <path-prefix>     after `--qa-timer-snapshot-after` s (default 3), writes every visible
//                                          panel of the app as <prefix>-<n>.png — rendered in-process from the
//                                          window's own layers, so it needs no screen-recording permission
//
// With the flag the module uses a throw-away model: it neither restores nor saves `state.json` and stays silent.
// Combine with the shell's `--qa-state closed|open` (closed + a running timer = the compact activity).
#if DEBUG
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.timer)

enum TimerQA {
    static let argument = "--qa-timer"

    static var isRequested: Bool { spec != nil }

    private static var spec: String? { value(after: argument) }

    private static func value(after name: String) -> String? { LaunchArguments.current.value(after: name) }

    static func dependencies(services: CrannyServices) -> TimerDependencies {
        var dependencies = TimerDependencies.live(services: services)
        dependencies.file = nil
        dependencies.sound = SilentTimerSound()
        return dependencies
    }

    /// Applies the requested state after launch (the model is the QA one: nothing is persisted).
    static func apply(to model: TimerModel) {
        guard let spec, let sample = parse(spec) else { return }
        log.info("QA: timer \(spec, privacy: .public)")
        let (state, draft) = sample.state(at: model.now)
        model.showSample(state, draft: draft)
        scheduleSnapshot()
    }

    /// Renders the app's own panels (windows above the normal level) into PNGs.
    private static func scheduleSnapshot() {
        guard let prefix = value(after: "--qa-timer-snapshot") else { return }
        let delay = value(after: "--qa-timer-snapshot-after").flatMap(Double.init) ?? 3
        Task {
            try? await Task.sleep(for: .seconds(delay))
            let panels = NSApp.windows.filter { $0.isVisible && $0.level.rawValue > NSWindow.Level.normal.rawValue }
            for (index, window) in panels.enumerated() {
                guard let view = window.contentView, let layer = view.layer else { continue }
                let scale = window.backingScaleFactor
                let size = view.bounds.size
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                context.scaleBy(x: scale, y: scale)
                layer.render(in: context)
                guard let image = context.makeImage() else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                let url = URL(fileURLWithPath: "\(prefix)-\(index).png")
                do { try rep.representation(using: .png, properties: [:])?.write(to: url) } catch {
                    log.error("QA: snapshot failed: \(error.localizedDescription, privacy: .public)")
                }
                log.info("QA: wrote \(url.path, privacy: .public)")
            }
        }
    }

    /// "running:272/300" → `.running(left: 272, total: 300)`.
    static func parse(_ spec: String) -> TimerModel.Sample? {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let numbers = parts.count > 1 ? parts[1].split(separator: "/").compactMap { TimeInterval($0) } : []
        let first = numbers.first, total = numbers.count > 1 ? numbers[1] : numbers.first
        switch parts.first {
        case "idle": return .idle
        case "running": return first.map { .running(left: $0, total: total ?? $0) }
        case "paused": return first.map { .paused(left: $0, total: total ?? $0) }
        case "done": return .done(total: first ?? TimerLimits.defaultDuration)
        case "setup": return first.map { .setup(seconds: Int($0)) }
        default: return nil
        }
    }
}
#endif
