// CrannyMirror/Preview/MirrorQA.swift — Debug-only visual QA for the Mirror, like the shell's `--qa-*` hooks
// (docs/CONTRIBUTING.md): `--qa-mirror <scenario>` swaps the camera, discovery and permission for the sample
// parts, so every state can be screenshotted in the real panel without a camera, a prompt or a click.
//
//   scripts/run.sh -- --qa-state open --qa-page nook --qa-mirror running --qa-exit-after 8
//
// Scenarios: off · running · toolbar (running + toolbar held visible) · starting · denied · restricted ·
// nocamera · lidclosed · failed. The whole file is compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation

enum MirrorQA {
    enum Scenario: String, CaseIterable {
        case off, running, toolbar, starting, denied, restricted, nocamera, lidclosed, failed
    }

    /// The scenario requested on the command line, if any.
    static func scenario(arguments: [String] = ProcessInfo.processInfo.arguments) -> Scenario? {
        LaunchArguments(arguments).value(after: "--qa-mirror").flatMap(Scenario.init(rawValue:))
    }

    /// A model wired to sample parts for `scenario`. Running scenarios start as soon as the widget is visible.
    static func makeModel(_ scenario: Scenario, services: CrannyServices) -> MirrorModel {
        let cameras: CameraSnapshot = switch scenario {
        case .nocamera: SampleCameraDiscovery.none
        case .lidclosed: SampleCameraDiscovery.lidClosed
        default: SampleCameraDiscovery.twoCameras
        }
        let authorization: PermissionStatus = switch scenario {
        case .denied: .denied
        case .restricted: .restricted
        default: .granted
        }
        let controller = switch scenario {
        case .failed: SampleCameraController(startDelay: .milliseconds(300), failure: .sessionFailed)
        case .starting: SampleCameraController(startDelay: .seconds(3600))
        default: SampleCameraController()
        }
        // The sample environment: the camera (a drawing here) may "run" while QA screenshots a locked screen.
        let model = MirrorModel(settings: services.settings, notch: services.notch, environment: PreviewSystemEnvironment(),
                                catalog: CameraCatalog(discovery: SampleCameraDiscovery(cameras)),
                                controller: controller, authorization: SampleCameraAuthorization(authorization))
        model.startsWhenVisibleForQA = [.running, .toolbar, .starting, .failed].contains(scenario)
        model.showsToolbarForQA = scenario == .toolbar
        return model
    }
}
#endif
