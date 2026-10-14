// CrannyMirror/UI/CameraPreviewView.swift — live frames: an `AVCaptureVideoPreviewLayer` in a layer-hosting
// NSView (R3 §5), aspect-fill, mirrored by the connection (or by a flipped layer where the connection cannot),
// with its own continuous corner so the frames match the card's radius even if SwiftUI's clip misses AppKit.
import AppKit
import AVFoundation
import CrannyCore
import SwiftUI

/// The feed of a running camera: real frames or, in previews and visual QA, the drawn sample.
struct MirrorFeedView: View {
    @Environment(\.cranny) private var theme
    let feed: CameraFeed
    let isMirrored: Bool

    var body: some View {
        switch feed {
        case .session(let handle):
            CameraPreviewView(handle: handle, isMirrored: isMirrored, cornerRadius: theme.grid.cardRadius)
        case .sample:
            SampleFeedView(isMirrored: isMirrored)
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let handle: CaptureSessionHandle
    let isMirrored: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> CameraPreviewHostView {
        CameraPreviewHostView(session: handle.session)
    }

    func updateNSView(_ view: CameraPreviewHostView, context: Context) {
        view.isMirrored = isMirrored
        view.cornerRadius = cornerRadius
    }

    static func dismantleNSView(_ view: CameraPreviewHostView, coordinator: ()) {
        view.detach()
    }
}

/// Layer-hosting view: the preview layer fills it; frames never pass through SwiftUI.
final class CameraPreviewHostView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    var isMirrored = true { didSet { if isMirrored != oldValue { applyMirroring() } } }
    var cornerRadius: CGFloat = Radius.card { didSet { layer?.cornerRadius = cornerRadius } }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        let host = CALayer()
        host.masksToBounds = true
        host.cornerCurve = .continuous
        host.cornerRadius = cornerRadius
        layer = host                     // set the layer BEFORE wantsLayer: a layer-hosting view
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        host.addSublayer(previewLayer)
        applyMirroring()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)            // no implicit animation while the card morphs
        previewLayer.frame = bounds
        CATransaction.commit()
        applyMirroring()                                  // the connection exists once the session has its input
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        previewLayer.contentsScale = scale
    }

    /// Frames are not interactive: clicks go to the SwiftUI card on top.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func detach() { previewLayer.session = nil }

    private func applyMirroring() {
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirrored != isMirrored { connection.isVideoMirrored = isMirrored }
            previewLayer.setAffineTransform(.identity)
        } else {
            previewLayer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }
    }
}

// The live preview needs a running camera, which previews never start (ARCHITECTURE.md §7.5). The running look
// is previewed with the sample feed in MirrorWidget.swift and SampleFeedView.swift.
#Preview("Feed · sample stand-in") {
    MirrorFeedView(feed: .sample, isMirrored: true)
        .crannyCard(cells: 2, frameless: true)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
