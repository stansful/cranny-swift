// CrannyCore/DesignSystem/Components.swift
// The primitives every feature module builds on. They read tokens only.
import SwiftUI
import AppKit

// MARK: - NotchSurface: fill + clipped content + keyline + elevation (+ optional underglow)

/// Fills the FIXED canvas. Content states lay themselves out at their final size, top-centred,
/// and are revealed by the animated clip — text never reflows during a morph (R1 §7.2).
public struct NotchSurface<Content: View>: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    public var geometry: NotchGeometry
    public var band: CGFloat
    public var openness: Double                 // 0 closed/compact … 1 peek/open
    public var elevation: [CrannyShadow]
    public var keylineTint: Color?              // album accent while music plays
    public var underglow: Color?                // ambient glow1 (Vivid only)
    private let content: Content

    public init(geometry: NotchGeometry, band: CGFloat, openness: Double, elevation: [CrannyShadow] = Elevation.open,
                keylineTint: Color? = nil, underglow: Color? = nil, @ViewBuilder content: () -> Content) {
        self.geometry = geometry; self.band = band; self.openness = openness; self.elevation = elevation
        self.keylineTint = keylineTint; self.underglow = underglow; self.content = content()
    }

    public var body: some View {
        let shape = NotchShape(geometry)
        let p = theme.palette
        ZStack(alignment: .top) {
            if let underglow, theme.allowsUnderglow {
                // Coloured *shadow* = light on the desktop that stays click-through.
                shape.fill(Color.black)
                    .shadow(color: underglow.opacity(Glow.underglow.opacity * openness),
                            radius: Glow.underglow.radius, x: 0, y: Glow.underglow.y)
            }
            surfaceFill(shape, p)
                .crannyElevation(elevation, amount: openness)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
            if openness > 0 || theme.increaseContrast {
                // HIG key line: separates the shape from dark windows. Never along the screen
                // edge or beside the menu bar: masked to start below the band.
                shape.stroke((keylineTint ?? .white).opacity(theme.increaseContrast ? p.spec.keyline : p.spec.keyline * openness),
                             lineWidth: StrokeWidth.keyline)
                    .mask(bandMask(fadeTo: 1))
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Cranny"))   // a name, not a key (a key would be looked up in Bundle.main)
    }

    @ViewBuilder private func surfaceFill(_ shape: NotchShape, _ p: CrannyPalette) -> some View {
        let canGlass = !theme.reduceTransparency && !theme.increaseContrast
        if geometry.isFloating && theme.glassIsland && canGlass {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.75)), in: shape)
            } else {
                shape.fill(p.surface)
            }
        } else if theme.translucentBackground && canGlass {
            ZStack {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
                } else {
                    VisualEffectBackdrop().clipShape(shape)
                }
                // The band stays pure black (no seam around the camera); below it 72 % black.
                shape.fill(p.surface).mask(bandMask(fadeTo: 0.72))
            }
        } else {
            shape.fill(p.surface)
        }
    }

    /// Opaque through the band, then a 6-pt ramp to `fadeTo` (layout-independent mask).
    private func bandMask(fadeTo: Double) -> some View {
        VStack(spacing: 0) {
            Color.white.frame(height: geometry.topInset + band).opacity(fadeTo == 1 ? 0 : 1)
            LinearGradient(colors: [.white.opacity(fadeTo == 1 ? 0 : 1), .white.opacity(fadeTo)],
                           startPoint: .top, endPoint: .bottom).frame(height: fadeTo == 1 ? 6 : 24)
            Color.white.opacity(fadeTo)
        }
    }
}

/// macOS 14/15 translucent backdrop.
public struct VisualEffectBackdrop: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Compact slots around the camera

/// leading | camera housing (never draw here) | trailing. Content hugs the camera.
public struct CompactSlots<Leading: View, Center: View, Trailing: View>: View {
    public var layout: NotchLayout
    public var slot: SlotWidth
    public var label: CGFloat
    private let leading: Leading, center: Center, trailing: Trailing

    public init(layout: NotchLayout, slot: SlotWidth, label: CGFloat = 0,
                @ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center,
                @ViewBuilder trailing: () -> Trailing) {
        self.layout = layout; self.slot = slot; self.label = label
        self.leading = leading(); self.center = center(); self.trailing = trailing()
    }

    public var body: some View {
        let u = layout.u, s = slot.points(unit: u)
        let outer = 12 * u, gap = 8 * u
        HStack(spacing: 0) {
            leading.frame(width: max(s - outer - gap, 0), alignment: .trailing)
                .padding(.leading, outer).padding(.trailing, gap)
            Color.clear.frame(width: layout.middle(label: label)).overlay { center }  // not EmptyView().frame()
            trailing.frame(width: max(s - outer - gap, 0), alignment: .leading)
                .padding(.leading, gap).padding(.trailing, outer)
        }
        .frame(height: layout.rowHeight)
        .padding(.top, layout.rowInset)
    }
}

// MARK: - Card

public struct CrannyCardModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    public var cells: Int
    public var hovered: Bool
    public var frameless: Bool          // Mirror: the preview IS the card

    public func body(content: Content) -> some View {
        let g = theme.grid, p = theme.palette
        let shape = RoundedRectangle(cornerRadius: g.cardRadius, style: .continuous)
        let carded = theme.widgetStyle == .cards && !frameless
        content
            .padding(frameless ? 0 : g.density.cardPadding)
            .frame(width: g.width(cells: cells), height: g.height, alignment: .topLeading)
            .background { if carded { shape.fill(hovered ? p.cardHover : p.card) } }
            .overlay {
                if carded {
                    shape.strokeBorder(p.hairline, lineWidth: theme.increaseContrast ? 1 : StrokeWidth.hairline(displayScale))
                }
            }
            .clipShape(shape)
            .containerShape(shape)          // inner ContainerRelativeShape stays concentric
            .animation(theme.animation(.hover), value: hovered)
    }
}

public extension View {
    func crannyCard(cells: Int, hovered: Bool = false, frameless: Bool = false) -> some View {
        modifier(CrannyCardModifier(cells: cells, hovered: hovered, frameless: frameless))
    }

    /// Keyboard focus: 2-pt accent ring, concentric (radius + 3, outset 3). Shown only after
    /// keyboard interaction; disable the system focus effect on the same element.
    func crannyFocusRing(_ focused: Bool, radius: CGFloat) -> some View {
        modifier(FocusRingModifier(focused: focused, radius: radius))
    }
}

struct FocusRingModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    var focused: Bool, radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius + Radius.focusRingOutset, style: .continuous)
                .strokeBorder(theme.accentColor, lineWidth: StrokeWidth.focus)
                .padding(-Radius.focusRingOutset)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Buttons

/// Icon button used everywhere in the notch. `.prominent` = the ONE primary action per card.
public struct CrannyIconButtonStyle: ButtonStyle {
    public enum Role: Sendable { case plain, filled, prominent }
    public var role: Role
    public var size: CGFloat
    public init(_ role: Role = .plain, size: CGFloat = HitTarget.preferred) { self.role = role; self.size = size }
    public func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, role: role, size: size)
    }

    struct IconButtonBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration, role: Role, size: CGFloat
        var body: some View {
            let p = theme.palette
            let fill: Color = switch role {
            case .prominent: .white
            case .filled: configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control
            case .plain: configuration.isPressed ? p.controlPressed : hovered ? p.control : .clear
            }
            configuration.label
                .font(.system(size: (size * 0.48).rounded(), weight: .semibold))
                .foregroundStyle(role == .prominent ? Color.black : p.label)
                .frame(width: size, height: size)
                .background(CrannyButtonShape(theme.buttonShape).fill(fill))
                .contentShape(CrannyButtonShape(theme.buttonShape))
                .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
                .opacity(enabled ? (configuration.isPressed && theme.reduceMotion ? 0.7 : 1) : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
                .animation(theme.animation(.press), value: configuration.isPressed)
        }
    }
}

// MARK: - Level bar (HUD, scrubber) and progress ring

public struct LevelBar: View {
    @Environment(\.cranny) private var theme
    public var value: Double                // 0…1
    public var tint: Color?                 // nil = white (default HUD)
    public var thickness: CGFloat
    public var steps: Int                   // ticks drawn under DWC / Increase Contrast / fine steps
    public var showsTicks: Bool
    public var muted: Bool

    public init(value: Double, tint: Color? = nil, thickness: CGFloat = StrokeWidth.hudBar,
                steps: Int = 16, showsTicks: Bool = false, muted: Bool = false) {
        self.value = value; self.tint = tint; self.thickness = thickness
        self.steps = steps; self.showsTicks = showsTicks; self.muted = muted
    }

    public var body: some View {
        let p = theme.palette
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(p.control)
                Capsule(style: .continuous).fill(muted ? p.tertiaryLabel : (tint ?? p.label))
                    .frame(width: value <= 0 ? 0 : max(thickness, g.size.width * min(value, 1)))
                if showsTicks || theme.differentiateWithoutColor || theme.increaseContrast {
                    HStack(spacing: 0) {
                        ForEach(1..<max(steps, 2), id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: thickness)
        .animation(theme.animation(.hudLevel), value: value)
    }
}

public struct ProgressRing: View {
    @Environment(\.cranny) private var theme
    public var progress: Double, color: Color, lineWidth: CGFloat
    public init(progress: Double, color: Color, lineWidth: CGFloat) {
        self.progress = progress; self.color = color; self.lineWidth = lineWidth
    }
    public var body: some View {
        ZStack {
            Circle().stroke(theme.palette.control, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Key cap (hold-⌘ hints, command palette, tutorial)

public struct KeyCap: View {
    @Environment(\.cranny) private var theme
    public var keys: String
    public init(_ keys: String) { self.keys = keys }
    public var body: some View {
        let p = theme.palette
        Text(keys)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(p.secondaryLabel)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(p.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).strokeBorder(p.hairline, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)       // shortcuts are exposed as accessibility hints instead
    }
}

// MARK: - Drop zone (Tray, AirDrop, pipelines)

public struct DropZone: View {
    @Environment(\.cranny) private var theme
    /// `title` is ALREADY localized by the caller (`String(localized:bundle: .module)`): a `LocalizedStringKey`
    /// passed into CrannyCore would be looked up in Bundle.main and stay English (ARCHITECTURE §3.2).
    public var symbol: String, title: String, targeted: Bool, tint: Color?
    public init(symbol: String, title: String, targeted: Bool, tint: Color? = nil) {
        self.symbol = symbol; self.title = title; self.targeted = targeted; self.tint = tint
    }
    public var body: some View {
        let p = theme.palette, r = theme.grid.innerRadius
        let armed = tint ?? theme.accentColor
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            Text(title).crannyFont(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(targeted ? p.label : p.secondaryLabel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(targeted ? armed.opacity(0.15) : .clear))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
            .strokeBorder(targeted ? armed : p.stroke,
                          style: StrokeStyle(lineWidth: StrokeWidth.emphasis,
                                             dash: targeted && theme.differentiateWithoutColor ? [] : StrokeWidth.dash)))
        .scaleEffect(targeted && !theme.reduceMotion ? 1.03 : 1)
        .animation(theme.animation(.commit), value: targeted)
        .accessibilityElement(children: .combine)
    }
}
