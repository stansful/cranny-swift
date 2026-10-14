// CrannyCore/Additions/WP08-SelectionFocus.swift — additive Core change for the Tray (ARCHITECTURE.md §4.10, §10.0).
import Foundation

/// Key focus for a selection rather than for typing. Implemented by the shell's `NotchControl`; a module asks with
/// `(notch as? any NotchSelectionFocus)?.requestSelectionFocus()` and falls back to `requestKeyboardFocus()` when the
/// control does not conform (previews and test doubles).
///
/// A click on a Tray tile selects it, and the row's keys (Space, ⌘C, ⌘⌫, ⌘.) must then reach the Tray, never the
/// frontmost app (⌘⌫ in Finder would trash the user's own selection). So the panel becomes key, without activating
/// Cranny, but unlike typing that key status does not hold the panel open: it still closes when the pointer leaves,
/// after the usual grace, and the close hands key status back to the previous app (DESIGN.md §3.6).
@MainActor public protocol NotchSelectionFocus: AnyObject {
    /// Makes the open panel key like `requestKeyboardFocus()`, without the `typing` hold. Key status taken this way
    /// holds the panel open after all once a text view or field becomes first responder or anything calls
    /// `requestKeyboardFocus()`; a panel that is already key and held stays held.
    func requestSelectionFocus()
}
