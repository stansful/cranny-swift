// CrannyMedia/Sample/SampleMedia.swift — a fictional session for the Settings "Simulate" chips, the onboarding
// stage, `#Preview`s and Debug visual QA (`--qa-media`). Original artwork drawn in code; it never touches the
// system (no provider, no helper, commands only change the sample's own state).
import CoreGraphics
import CrannyCore
import Foundation

enum SampleMedia {
    /// Names, not copy: never translated (DESIGN.md §16's example track).
    static let title = "Midnight Window"
    static let artist = "The Example Band"
    static let album = "Night Signals"
    static let duration: TimeInterval = 215

    static func nowPlaying(playing: Bool = true, elapsed: TimeInterval = 84, now: Date = Date()) -> NowPlaying {
        var np = NowPlaying(bundleID: PlayerApps.music, title: title, artist: artist, album: album,
                            duration: duration, elapsed: elapsed, timestamp: now, rate: playing ? 1 : 0,
                            isPlaying: playing, itemID: "cranny.sample.midnight-window")
        np.appName = "Music"
        np.isMusicApp = true
        np.shuffle = .off
        np.repeatMode = .off
        return np
    }

    /// `artwork()`, drawn and its palette extracted once per process: every sample service shows the same picture
    /// (each Settings stage, Simulate chip and onboarding page used to redraw it).
    static let sharedArtwork: DecodedArtwork? = artwork()

    /// A dusk scene: an iris-to-rose sky, an ember sun and a lit window grid. 256 × 256, sRGB.
    static func artwork() -> DecodedArtwork? {
        let side = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(side)
        func cg(_ rgb: RGB, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
        }
        // Sky (CG origin is bottom-left: the gradient runs from the horizon up).
        let sky = [cg(BrandColor.ember), cg(BrandColor.rose), cg(RGB(hex: 0x5B3FB8)), cg(BrandColor.night)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: sky, locations: [0, 0.28, 0.62, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s * 0.30), end: CGPoint(x: 0, y: s), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // Sun.
        ctx.setFillColor(cg(RGB(hex: 0xFFC27A), 0.95))
        ctx.fillEllipse(in: CGRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40))
        // City block with lit windows.
        ctx.setFillColor(cg(BrandColor.night))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.36))
        ctx.fill(CGRect(x: s * 0.08, y: 0, width: s * 0.30, height: s * 0.52))
        ctx.fill(CGRect(x: s * 0.62, y: 0, width: s * 0.26, height: s * 0.46))
        ctx.setFillColor(cg(BrandColor.mint, 0.85))
        for row in 0..<4 {
            for column in 0..<3 where (row + column) % 2 == 0 {
                ctx.fill(CGRect(x: s * (0.12 + 0.08 * CGFloat(column)), y: s * (0.08 + 0.1 * CGFloat(row)), width: s * 0.04, height: s * 0.05))
            }
        }
        ctx.setFillColor(cg(RGB(hex: 0xFFD27A), 0.9))
        ctx.fill(CGRect(x: s * 0.68, y: s * 0.30, width: s * 0.05, height: s * 0.05))
        ctx.fill(CGRect(x: s * 0.77, y: s * 0.18, width: s * 0.05, height: s * 0.05))
        guard let image = ctx.makeImage() else { return nil }
        return DecodedArtwork(image: image, palette: AmbientPalette.extract(from: image))
    }

    /// A service that shows the sample (Settings stage, onboarding, previews, `--qa-media`). Never started.
    @MainActor static func service(settings: SettingsStore, environment: any SystemEnvironment,
                                   permissions: PermissionsCenter, playing: Bool = true) -> MediaService {
        let service = MediaService(settings: settings, environment: environment, permissions: permissions, providers: [])
        service.seed(nowPlaying(playing: playing), artwork: sharedArtwork)
        return service
    }

    /// For `#Preview`s: the sample service on throw-away preview services.
    @MainActor static func previewService(playing: Bool = true) -> MediaService {
        let services = CrannyServices.preview()
        return service(settings: services.settings, environment: services.environment,
                       permissions: services.permissions, playing: playing)
    }
}
