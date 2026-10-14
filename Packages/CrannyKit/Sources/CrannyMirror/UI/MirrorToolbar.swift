// CrannyMirror/UI/MirrorToolbar.swift — the hover toolbar of a running Mirror (DESIGN.md §7.4): 24-pt circles
// on black at the top-trailing corner, for flip and a camera menu. Not hover-only (§1 principle 7): it also shows
// while the widget has keyboard focus and whenever VoiceOver runs, and both actions live in the options too.
import CrannyCore
import SwiftUI

struct MirrorToolbar: View {
    let model: MirrorModel
    var focus: FocusState<MirrorFocus?>.Binding

    var body: some View {
        HStack(spacing: 0) {
            Button { model.isMirrored.toggle() } label: {
                Image(systemName: MirrorSymbol.flip)
            }
            .buttonStyle(MirrorToolbarButtonStyle())
            .focused(focus, equals: .flip)
            .focusEffectDisabled()
            .help(MirrorCopy.flipHelp)
            .accessibilityLabel(Text(verbatim: MirrorCopy.mirrorImage))
            .accessibilityValue(Text(verbatim: model.isMirrored ? MirrorCopy.on : MirrorCopy.off))
            .accessibilityAddTraits(.isToggle)

            // A menu with one entry would be a dead control: it appears once a second camera is connected.
            if model.catalog.devices.count > 1 {
                CameraMenu(model: model)
                    .focused(focus, equals: .camera)
                    .focusEffectDisabled()
            }
        }
        .padding(MirrorMetrics.toolbarInset - (HitTarget.preferred - MirrorMetrics.toolbarCircle) / 2)
    }
}

/// The camera menu: Automatic and every connected camera (`CameraChoices`); the current choice is checked.
struct CameraMenu: View {
    let model: MirrorModel

    var body: some View {
        Menu {
            Picker(selection: model.cameraSelection) {
                CameraChoices(model: model, separatesAutomatic: true)
            } label: {
                Text(verbatim: MirrorCopy.camera)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: MirrorSymbol.cameraMenu)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(MirrorToolbarButtonStyle())
        .fixedSize()
        .help(MirrorCopy.camera)
        .accessibilityLabel(Text(verbatim: MirrorCopy.camera))
        .accessibilityValue(Text(verbatim: model.camera?.name ?? ""))
    }
}

/// A 24-pt circle on black (the `scrim` token: black 55 %, opaque under Reduce Transparency) inside a 28-pt hit
/// target; hover and press add the `control` white over it, press scales to 0.94 (not under Reduce Motion).
struct MirrorToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(configuration: configuration)
    }

    private struct ToolbarButtonBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isFocused) private var isFocused
        @State private var hovered = false
        let configuration: Configuration

        var body: some View {
            let p = theme.palette
            let circle = MirrorMetrics.toolbarCircle
            configuration.label
                // DESIGN.md §14.1: hierarchical, white, medium weight in the Nook.
                .font(.system(size: MirrorMetrics.toolbarGlyph, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(p.label)
                .frame(width: circle, height: circle)
                .background {
                    Circle().fill(p.scrim)
                    Circle().fill(configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : .clear)
                }
                .overlay { if theme.increaseContrast { Circle().strokeBorder(p.stroke, lineWidth: StrokeWidth.regular) } }
                .overlay {
                    // Keyboard focus: the 2-pt accent ring, concentric (outset 3, DESIGN.md §16).
                    Circle().strokeBorder(theme.accentColor, lineWidth: StrokeWidth.focus)
                        .padding(-Radius.focusRingOutset)
                        .opacity(isFocused ? 1 : 0)
                }
                .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
                .frame(width: HitTarget.preferred, height: HitTarget.preferred)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
                .animation(theme.animation(.press), value: configuration.isPressed)
        }
    }
}

/// Owns the focus state a toolbar needs (previews only).
private struct ToolbarPreview: View {
    @FocusState private var focus: MirrorFocus?
    let model = MirrorModel.preview(phase: .running(deviceID: "sample.builtIn"))
    var body: some View {
        ZStack(alignment: .topTrailing) {
            SampleFeedView()
            MirrorToolbar(model: model, focus: $focus)
        }
    }
}

#Preview("Toolbar on the sample feed") {
    ToolbarPreview()
        .crannyCard(cells: 3, frameless: true)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
