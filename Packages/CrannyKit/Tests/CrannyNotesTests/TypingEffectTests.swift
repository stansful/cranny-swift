// The typing effect: run bookkeeping (pure) and the TextKit 2 renderer, which must never touch the text storage
// or the undo stack (ARCHITECTURE.md §10.6 acceptance).
import AppKit
import CrannyCore
import Testing
@testable import CrannyNotes

@Suite("Typing effect") struct TypingEffectTests {
    @Test func runsMergePerEventAndKeepTheLast32() {
        var effect = TypingEffect()
        effect.typed(NSRange(location: 0, length: 1), at: 1)
        effect.typed(NSRange(location: 1, length: 2), at: 1)                    // same event, adjacent
        #expect(effect.runs == [.init(range: NSRange(location: 0, length: 3), start: 1)])
        effect.typed(NSRange(location: 3, length: 1), at: 2)
        #expect(effect.runs.count == 2)
        var many = TypingEffect()
        var dropped: [NSRange] = []
        for i in 0..<40 { dropped += many.typed(NSRange(location: i, length: 1), at: Double(i)) }
        #expect(many.runs.count == TypingEffect.maximumRuns)
        #expect(dropped == (0..<8).map { NSRange(location: $0, length: 1) })
        #expect(many.typed(NSRange(location: 99, length: 0), at: 99).isEmpty)
    }

    @Test func runsFollowEdits() {
        var effect = TypingEffect()
        effect.typed(NSRange(location: 10, length: 2), at: 0)
        effect.textChanged(edited: NSRange(location: 0, length: 3), delta: 3)    // insert before
        #expect(effect.runs.first?.range == NSRange(location: 13, length: 2))
        effect.textChanged(edited: NSRange(location: 15, length: 1), delta: 1)   // insert right after: not absorbed
        #expect(effect.runs.first?.range == NSRange(location: 13, length: 2))
        effect.textChanged(edited: NSRange(location: 14, length: 1), delta: 1)   // insert inside: grows
        #expect(effect.runs.first?.range == NSRange(location: 13, length: 3))
        effect.textChanged(edited: NSRange(location: 12, length: 0), delta: -2)  // delete [12, 14): clipped
        #expect(effect.runs.first?.range == NSRange(location: 12, length: 2))
        effect.textChanged(edited: NSRange(location: 10, length: 0), delta: -10) // delete it all
        #expect(effect.isIdle)
    }

    @Test func easingAndExpiry() {
        #expect(TypingEffect.progress(elapsed: 0) == 0)
        #expect(abs(TypingEffect.progress(elapsed: 0.15) - 0.875) < 1e-9)       // ease-out cubic at half time
        #expect(TypingEffect.progress(elapsed: 0.3) == 1)
        #expect(TypingEffect.progress(elapsed: -1) == 0)
        var effect = TypingEffect()
        effect.typed(NSRange(location: 0, length: 1), at: 0)
        effect.typed(NSRange(location: 5, length: 1), at: 0.2)
        let frame = effect.advance(to: 0.35)
        #expect(frame.finished == [NSRange(location: 0, length: 1)])
        #expect(frame.active.map(\.range) == [NSRange(location: 5, length: 1)])
        #expect(effect.runs.count == 1)
        #expect(effect.advance(to: 1).finished.count == 1)
        #expect(effect.isIdle)
    }

    @Test func blendGoesFromAccentToTheCharactersColour() {
        let accent = (rgb: RGB(hex: 0x409CFF), alpha: 1.0)
        let comment = (rgb: RGB.white, alpha: 0.55)
        let start = TypingEffect.blend(from: accent, to: comment, progress: 0)
        let end = TypingEffect.blend(from: accent, to: comment, progress: 1)
        let mid = TypingEffect.blend(from: accent, to: comment, progress: 0.5)
        #expect(start.rgb == accent.rgb && start.alpha == 1)
        #expect(end.rgb == comment.rgb && end.alpha == 0.55)
        #expect(abs(mid.alpha - 0.775) < 1e-9)
    }

    // MARK: Renderer

    private final class UndoProvider: NSObject, NSTextViewDelegate {
        let manager = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    @Test func rendererNeverTouchesTheStorageOrTheUndoStack() throws {
        let textView = NSTextView(usingTextLayoutManager: true)
        let undo = UndoProvider()
        textView.delegate = undo
        textView.allowsUndo = true
        textView.string = "let x = 1"
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        textView.insertText("23", replacementRange: textView.selectedRange())       // typed: one undo group
        let storageBefore = try #require(textView.textStorage?.copy() as? NSAttributedString)
        var time = 10.0
        let renderer = TypingEffectRenderer()
        renderer.now = { time }
        renderer.attach(to: textView)
        renderer.setAccent(RGB(hex: 0x409CFF))
        renderer.typed(NSRange(location: 9, length: 2))
        time += 0.1
        renderer.step()
        let layout = try #require(textView.textLayoutManager)
        var colouredRuns = 0
        layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attributes, _ in
            if attributes[.foregroundColor] != nil { colouredRuns += 1 }
            return true
        }
        #expect(colouredRuns > 0)                                               // the effect is drawn…
        #expect(textView.textStorage?.isEqual(to: storageBefore) == true)       // …without changing the storage
        time += 1
        renderer.step()
        #expect(renderer.state.isIdle)
        var remaining = 0
        layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attributes, _ in
            if attributes[.foregroundColor] != nil { remaining += 1 }
            return true
        }
        #expect(remaining == 0)                                                 // settled: nothing left drawn
        undo.manager.undo()                                                     // the only undo step is the typing
        #expect(textView.string == "let x = 1")
        #expect(!undo.manager.canUndo)
        renderer.stop()
    }

    @Test func turningTheEffectOffClearsIt() {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = "abc"
        let renderer = TypingEffectRenderer()
        renderer.attach(to: textView)
        renderer.typed(NSRange(location: 0, length: 3))
        #expect(!renderer.state.isIdle)
        renderer.isEnabled = false
        #expect(renderer.state.isIdle)
        renderer.typed(NSRange(location: 0, length: 1))                         // ignored while off
        #expect(renderer.state.isIdle)
    }
}
