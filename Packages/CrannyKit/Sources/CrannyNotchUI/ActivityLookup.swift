// CrannyNotchUI/ActivityLookup.swift — which object draws an activity on this canvas.
import CrannyCore

extension NotchSceneModel {
    /// Stages put sample instances in `sampleActivities`; the shell leaves it empty and the registry's
    /// live objects draw (ARCHITECTURE.md §4.12).
    func activity(_ id: ActivityID, in registry: ModuleRegistry) -> (any LiveActivity)? {
        sampleActivities[id] ?? registry.activity(id)?.activity
    }
}
