import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

/// `AmbientUniforms` mirrors `cranny::AmbientUniforms` byte for byte: eleven 16-byte vectors.
@Test func uniformsLayoutMatchesTheShader() {
    #expect(MemoryLayout<AmbientUniforms>.size == 176)
    #expect(MemoryLayout<AmbientUniforms>.stride == 176)
    #expect(MemoryLayout<AmbientUniforms>.alignment == 16)
    #expect(MemoryLayout<AmbientUniforms>.offset(of: \.stops) == 80)
    #expect(MemoryLayout<AmbientUniforms>.offset(of: \.counts) == 160)
}

@Test func uniformsCarryTheState() {
    var state = layerState(.aurora, palette: .afterglow, level: .vivid, energy: 0.25, fill: 1.4)
    let date = Date(timeIntervalSinceReferenceDate: 1000)
    var u = AmbientUniforms(state: state, size: CGSize(width: 800, height: 200), scale: 2, time: 12, date: date)
    #expect(u.frame == SIMD4(800, 200, 2, 12))
    #expect(u.params == SIMD4(0.25, 1, 0.8, 1))                         // energy, intensity, cap (Vivid), fill clamped
    #expect(u.reveal.z < 0)                                             // no reveal
    #expect(u.ripple == .zero)                                          // no ripple
    #expect(u.halo == SIMD4(0.5, 1, 260, 1))                            // ambient halo, dithered
    #expect(u.counts.x == 3)
    #expect(u.counts.y == 0)                                            // a drawable of the whole layer
    #expect(AmbientUniforms(state: state, size: CGSize(width: 800, height: 200), scale: 2, time: 12, date: date,
                            rowOffset: 152).counts.y == 152)            // the lit band starts 152 rows down
    let iris = BrandColor.iris
    #expect(abs(u.stops.0.x - Float(iris.r)) < 1e-6 && u.stops.0.w == 1 && u.stops.3 == .zero)

    state.reveal = AmbientReveal(center: .top, radius: 120, feather: 40)
    state.rippleStart = date.addingTimeInterval(-0.2)
    state.level = .subtle
    u = AmbientUniforms(state: state, size: CGSize(width: 800, height: 200), scale: 2, time: 12, date: date)
    #expect(u.reveal == SIMD4(400, 0, 120, 40))
    #expect(u.ripple.x == 400 && u.ripple.y == 0 && abs(u.ripple.z - 0.2) < 1e-5 && u.ripple.w == 1)
    #expect(u.params.x > 0.25)                                          // the ripple's energy pulse
    #expect(u.params.z == Float(Glow.ambientAlphaCap(.subtle)))
}

@Test func uniformsClampStopsAndSkipMotesDither() {
    var state = layerState(.motes)
    state.glows = [RGB(1.4, -0.2, 0.5), .white, .black, .white, .black, .white]
    let u = AmbientUniforms(state: state, size: CGSize(width: 10, height: 10), scale: 1, time: 0, date: Date())
    #expect(u.stops.0 == SIMD4(1, 0, 0.5, 1))
    #expect(u.counts.x == 5)                                            // at most five stops
    #expect(u.halo.w == 0)                                              // specks are not dithered
}
