// CrannyMirror/Camera/CameraDevice.swift — a camera as a value. `AVCaptureDevice` is not Sendable and never
// leaves the files that talk to AVFoundation (CameraDiscovery, CaptureRunner).
import Foundation

/// A camera the Mirror can show (DESIGN.md §7.4: built-in, USB and Continuity cameras; never Desk View).
nonisolated struct CameraDevice: Identifiable, Hashable, Sendable {
    /// Where the camera comes from. The raw value is the order of the camera menu.
    nonisolated enum Kind: Int, Comparable, Sendable, CaseIterable {
        case builtIn, continuity, external, deskView, other
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// `AVCaptureDevice.uniqueID`: stable across launches, stored in `MirrorSettings.cameraID`.
    let id: String
    /// `localizedName`, e.g. "FaceTime HD Camera".
    let name: String
    let kind: Kind
    /// The camera delivers no frames right now: the lid is closed (built-in) or a privacy shutter is shut.
    var isSuspended: Bool

    init(id: String, name: String, kind: Kind, isSuspended: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.isSuspended = isSuspended
    }
}
