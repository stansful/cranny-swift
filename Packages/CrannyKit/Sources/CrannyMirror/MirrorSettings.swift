// CrannyMirror/MirrorSettings.swift — the module's settings keys (ARCHITECTURE.md §10.5). Shown in the widget's
// options (Settings ▸ Layout & Widgets and the card's ⋯ menu) and changed from the hover toolbar.
import CrannyCore

/// Settings of the Mirror widget, stored under `cranny.mirror.*`. "Reset Layout & Widgets…" does not touch
/// them; resetting the `mirror` namespace (Reset All) restores the defaults below.
public enum MirrorSettings {
    /// `AVCaptureDevice.uniqueID` of the camera the user picked; nil (default) follows the system's preferred
    /// camera. A picked camera that is not connected falls back to the preferred one and is used again when it
    /// returns (`CameraCatalog.resolve`).
    public static let cameraID = SettingKey<String?>(.mirror, "cameraID", default: nil)
    /// Show the image flipped like a mirror (default), or as other people see it.
    public static let isMirrored = SettingKey<Bool>(.mirror, "isMirrored", default: true)
}
