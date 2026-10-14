// CrannyNotchUI/PreviewGallery.swift — #Preview matrices (ARCHITECTURE.md §10.13 acceptance): every presentation
// × {14″ notch, floating island, attached} × {standard, lit, highContrast, opaque}. Each cell is a real
// `NotchCanvasView` of a sample scene (PreviewSupport.swift), cropped to the top of its canvas. The same matrix
// is written to PNGs by the opt-in `SnapshotGallery` test.
import CrannyCore
import SwiftUI

/// One row per display style, one column per palette variant.
struct PreviewMatrix: View {
    let phase: NotchPhase
    var height: CGFloat = 120

    private static let displays: [(String, NotchMetrics, NoNotchStyle)] = [
        ("14″ notch", PreviewDisplays.notch, .floatingIsland),
        ("Floating island", PreviewDisplays.external, .floatingIsland),
        ("Attached", PreviewDisplays.external, .attached),
    ]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text(verbatim: "")
                ForEach(PreviewVariant.allCases, id: \.self) { Text(verbatim: $0.rawValue).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(Self.displays, id: \.0) { name, metrics, style in
                GridRow {
                    Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                    ForEach(PreviewVariant.allCases, id: \.self) { variant in
                        let (model, registry) = previewScene(phase, metrics: metrics, style: style, variant: variant)
                        NotchCanvasView(model: model, registry: registry)
                            .frame(width: model.layout.canvasSize.width, height: model.layout.canvasSize.height)
                            .frame(width: model.layout.canvasSize.width, height: height, alignment: .top)
                            .clipped()
                            .background(Color(white: 0.3))
                            .scaleEffect(0.5, anchor: .topLeading)
                            .frame(width: model.layout.canvasSize.width / 2, height: height / 2, alignment: .topLeading)
                    }
                }
            }
        }
        .padding()
    }
}

#Preview("Matrix · closed") { PreviewMatrix(phase: .idle, height: 60) }
#Preview("Matrix · hover breath") { PreviewMatrix(phase: .breath, height: 60) }
#Preview("Matrix · compact") { PreviewMatrix(phase: .compact, height: 60) }
#Preview("Matrix · peek") { PreviewMatrix(phase: .peek, height: 120) }
#Preview("Matrix · open") { PreviewMatrix(phase: .open, height: 240) }
