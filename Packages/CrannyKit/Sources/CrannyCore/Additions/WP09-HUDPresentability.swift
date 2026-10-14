// CrannyCore/Additions/WP09-HUDPresentability.swift — additive Core change for the HUD (WP9, ARCHITECTURE.md §7.1,
// §10.0): `SystemEnvironment.canPresentHUD`. The HUD takes a volume or brightness key only when Cranny can show the
// HUD (D10: never two HUDs, never none). Lock, sleep and full screen are machine facts the HUD reads itself. Whether
// a panel would draw the HUD is known only to the shell: the pointer's display may have no panel, or its
// General ▸ Displays ▸ HUD toggle may be off. The shell writes the answer here, and the HUD hands the key back to
// macOS when it is false.
import Foundation

public extension SystemEnvironment {
    /// Default for environments that know nothing about panels (previews, tests): presentable, as before.
    var canPresentHUD: Bool { true }
}
