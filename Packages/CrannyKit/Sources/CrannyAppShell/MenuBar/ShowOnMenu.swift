// CrannyAppShell/MenuBar/ShowOnMenu.swift — Show On ▸ ✓ Built-in Display · ✓ External Display · … (DESIGN.md §13).
// One checkable row per connected display, plus "Display with the Pointer" when there are several. The last
// display that shows Cranny cannot be unchecked (its row is disabled), so the notch never vanishes everywhere.
import CrannyCore
import Foundation
import SwiftUI

struct ShowOnMenu: View {
    let displays: DisplayList

    var body: some View {
        Menu {
            ForEach(displays.displays) { display in
                Toggle(isOn: Binding(get: { displays.isShown(display.key) }, set: { _ in displays.toggle(display.key) })) {
                    Text(verbatim: display.name)
                }
                .disabled(!displays.canToggle(display.key))
            }
            if displays.offersPointerMode {
                Divider()
                Toggle(isOn: Binding(get: { displays.followsPointer }, set: { _ in displays.togglePointerMode() })) {
                    Text("Display with the Pointer", bundle: .module,
                         comment: "Menu bar ▸ Show On: show Cranny only on the display the pointer is on")
                }
            }
        } label: {
            Text("Show On", bundle: .module, comment: "Menu bar: submenu listing the displays that show Cranny")
        }
    }
}

#Preview("Show On · two displays") {
    let list = DisplayList(settings: CrannyServices.preview().settings) {
        [ConnectedDisplay(key: "built-in", name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true),
         ConnectedDisplay(key: "studio", name: "Studio Display", isBuiltIn: false, hasNotch: false)]
    }
    list.start()
    return Menu { ShowOnMenu(displays: list) } label: { Text(verbatim: "Cranny") }
        .fixedSize()
        .padding()
        .crannyThemeRoot(CrannyTheme())
}
