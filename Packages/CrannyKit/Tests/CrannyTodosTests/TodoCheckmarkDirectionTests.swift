// A check mark reads the same in every language (like SF Symbols' `checkmark`); a custom `Shape` is mirrored right to
// left unless it says otherwise (ARCHITECTURE.md §8.7).
import AppKit
import CrannyCore
import SwiftUI
import Testing
@testable import CrannyTodos

@MainActor @Test func theCheckMarkIsNotMirroredRightToLeft() throws {
    func png(_ direction: LayoutDirection) throws -> Data {
        let renderer = ImageRenderer(content: TodoCheckmark()
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 20)
            .background(Color.white)
            .environment(\.layoutDirection, direction))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
    #expect(try png(.rightToLeft) == png(.leftToRight))
}
