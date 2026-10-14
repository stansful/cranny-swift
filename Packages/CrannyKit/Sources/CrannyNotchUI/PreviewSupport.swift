// CrannyNotchUI/PreviewSupport.swift — sample data for this target's #Preview blocks (ARCHITECTURE.md §9.4):
// a scene in any phase on `CrannyServices.preview()` and one sample live activity. Not used by the app.
import CrannyCore
import Foundation
import Observation
import SwiftUI

/// A static live activity for previews: a glyph in the leading wing, a short label in the trailing wing.
@MainActor @Observable final class PreviewActivity: LiveActivity {
    let id: ActivityID = "preview.sample"
    let isActive = true
    let priority: ActivityPriority = .alert
    let revision = 1
    let slot: SlotWidth = .medium
    var accessibilityLabel: String { "Sample activity" }

    func compactLeading() -> some View { Image(systemName: "timer").accessibilityHidden(true) }
    func compactTrailing() -> some View { Text(verbatim: "4:59").crannyFont(.compact) }
    func minimal() -> some View { Image(systemName: "timer").accessibilityHidden(true) }
    func peekRow() -> some View {
        HStack(spacing: Space.l) {
            Image(systemName: "timer").frame(width: 40, height: 40).accessibilityHidden(true)
            Text(verbatim: "Tea · 4:59 left").crannyFont(.title)
            Spacer(minLength: 0)
        }
    }
}

/// A scene in `phase` with sample data; `.compact` and `.peek` show `PreviewActivity`, `.open` shows Home.
@MainActor func previewScene(_ phase: NotchPhase, metrics: NotchMetrics = .reference) -> (NotchSceneModel, ModuleRegistry) {
    let registry = ModuleRegistry(services: .preview())
    let model = NotchSceneModel(layout: NotchLayout(metrics: metrics), theme: CrannyTheme())
    let sample = PreviewActivity()
    model.sampleActivities[sample.id] = sample
    model.phase = phase
    switch phase {
    case .compact:
        model.primary = sample.id
        model.primarySlot = sample.slot
    case .peek:
        model.primary = sample.id
        model.primarySlot = sample.slot
        model.peekRows = [sample.id]
    case .open:
        model.open = OpenState(page: .nook, reason: .click)
        model.openColumns = 8
    default:
        break
    }
    return (model, registry)
}
