// CrannyNotes/Editor/TypingEffectRenderer.swift — draws `TypingEffect` with TextKit 2 rendering attributes
// (`NSTextLayoutManager.addRenderingAttribute`), stepped by one display link that runs only while characters are
// still settling (≤ 300 ms after the last keystroke) and is paused otherwise: zero work while idle (§9.2).
// The text storage, its attributes and the undo stack are never touched.
import AppKit
import CrannyCore
import QuartzCore

@MainActor final class TypingEffectRenderer: NSObject {
    private weak var textView: NSTextView?
    private var displayLink: CADisplayLink?
    private(set) var state = TypingEffect()
    private var accent: (rgb: RGB, alpha: Double) = (RGB(hex: 0x409CFF), 1)
    /// The clock (seconds); tests inject one.
    var now: () -> TimeInterval = { CACurrentMediaTime() }

    /// Off: setting off, Reduce Motion or Instant motion (DESIGN.md §4.2). Turning it off clears what is drawn.
    var isEnabled = true {
        didSet { if !isEnabled { clearAll() } }
    }

    func attach(to textView: NSTextView) { self.textView = textView }

    func setAccent(_ rgb: RGB) { accent = (rgb, 1) }

    /// The user typed `range` (called after the insertion).
    func typed(_ range: NSRange) {
        guard isEnabled, textView?.textLayoutManager != nil else { return }
        for dropped in state.typed(range, at: now()) { setColor(nil, for: dropped) }
        step()
        startLink()
    }

    /// Keeps the runs aligned with the text when it changes (from `NSTextStorageDelegate`).
    func textChanged(edited: NSRange, delta: Int) {
        guard !state.isIdle else { return }
        state.textChanged(edited: edited, delta: delta)
    }

    /// One frame: every settling run gets its blended colour; finished runs fall back to the storage colour.
    @objc func step(_ link: CADisplayLink? = nil) {
        let frame = state.advance(to: now())
        for range in frame.finished { setColor(nil, for: range) }
        for run in frame.active {
            let target = storageColor(at: run.range.location)
            let c = TypingEffect.blend(from: accent, to: target, progress: run.progress)
            setColor(NSColor(srgbRed: c.rgb.r, green: c.rgb.g, blue: c.rgb.b, alpha: c.alpha), for: run.range)
        }
        if state.isIdle { displayLink?.isPaused = true }
    }

    /// Clears every drawn colour (note switch, effect turned off).
    func clearAll() {
        for range in state.removeAll() { setColor(nil, for: range) }
        displayLink?.isPaused = true
    }

    /// The view is going away: stop the display link for good.
    func stop() {
        clearAll()
        displayLink?.invalidate()
        displayLink = nil
    }

    #if DEBUG
    /// Visual QA (`--qa-notes typing`): the last characters drawn at every stage of settling, frozen in time.
    func freezeForQA() {
        guard isEnabled, let length = textView?.textStorage?.length, length > 0 else { return }
        let frozen = now()
        let count = min(8, length)
        for k in 0..<count {
            state.typed(NSRange(location: length - count + k, length: 1), at: frozen - 0.28 + Double(k) * 0.04)
        }
        now = { frozen }
        step()
    }
    #endif

    // MARK: Private

    private func startLink() {
        if let displayLink {
            displayLink.isPaused = false
        } else if let textView, textView.window != nil {                         // a display link needs a screen
            let link = textView.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func storageColor(at location: Int) -> (rgb: RGB, alpha: Double) {
        guard let storage = textView?.textStorage, location < storage.length,
              let color = (storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)?
                .usingColorSpace(.sRGB) else { return (.white, 1) }
        return (RGB(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)), Double(color.alphaComponent))
    }

    private func setColor(_ color: NSColor?, for range: NSRange) {
        guard let textView, let layout = textView.textLayoutManager, let content = textView.textContentStorage,
              let storage = textView.textStorage else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0,
              let start = content.location(content.documentRange.location, offsetBy: clamped.location),
              let end = content.location(start, offsetBy: clamped.length),
              let textRange = NSTextRange(location: start, end: end) else { return }
        if let color {
            layout.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
        } else {
            layout.removeRenderingAttribute(.foregroundColor, for: textRange)
        }
    }
}
