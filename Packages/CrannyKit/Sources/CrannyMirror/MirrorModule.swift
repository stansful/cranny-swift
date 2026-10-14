// CrannyMirror/MirrorModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §7.5, §10.5).
// `register(in:)` only builds objects and contributes: no camera, no enumeration, no permission query happens
// until a Mirror widget appears in the open panel, and the camera itself only starts on a click.
import CrannyCore

/// Mirror: a frameless camera-preview widget (DESIGN.md §7.4). Registered by the shell's `CompositionRoot`.
public enum MirrorModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.mirror`).
    public static var id: ModuleID { .mirror }

    /// Contributes the widget and declares the camera permission. Observers start in `onLaunch`; the camera is
    /// released in `onTerminate`.
    public static func register(in registry: ModuleRegistry) {
        contribute(to: registry, model: makeModel(registry.services), sleep: SystemSleepObserver())
    }

    /// The contributions and the lifecycle wiring (tests pass a model on fakes and a private notification center).
    static func contribute(to registry: ModuleRegistry, model: MirrorModel, sleep: SystemSleepObserver) {
        registry.add(widget: MirrorWidget(model: model))
        registry.declare(.camera, reason: MirrorCopy.permissionReason)

        registry.onLaunch {
            model.activate()
            sleep.start { model.halt(.systemSleep) }
        }
        registry.onTerminate {
            sleep.stop()
            model.shutdown()
        }
    }

    /// The live model: AVFoundation camera and discovery, permission through `PermissionsCenter`. Debug builds
    /// swap in the sample parts for `--qa-mirror` (Preview/MirrorQA.swift).
    static func makeModel(_ services: CrannyServices) -> MirrorModel {
        #if DEBUG
        if let scenario = MirrorQA.scenario() { return MirrorQA.makeModel(scenario, services: services) }
        #endif
        return MirrorModel(settings: services.settings, notch: services.notch, environment: services.environment,
                           catalog: CameraCatalog(discovery: AVCameraDiscovery()), controller: CameraController(),
                           authorization: PermissionsCenterAuthorization(center: services.permissions))
    }
}
