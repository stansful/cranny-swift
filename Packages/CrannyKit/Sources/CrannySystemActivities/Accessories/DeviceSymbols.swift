// CrannySystemActivities/Accessories/DeviceSymbols.swift — device glyphs (DESIGN.md §9.2, §14.1, R3 §3).
// A small data table maps Apple product IDs (vendor 76) to their own glyph; everything else falls back to its
// kind. Restricted symbols (`airpods*`, `beats.headphones`, `magicmouse`) are used ONLY for those products.
// The table is data, not truth: an unknown or new product gets the generic glyph of its kind.
import Foundation

nonisolated enum DeviceSymbols {
    /// Bluetooth SIG company identifier of Apple (also the USB/HID vendor on Magic accessories).
    static let appleVendorID = 76

    /// An Apple product we recognise.
    nonisolated struct Product: Equatable, Sendable {
        let symbol: String
        /// The model's name, shown instead of the device's own (often personal) name in Demo mode.
        let model: String
        let kind: AccessoryKind
    }

    /// Apple/Beats audio products by Bluetooth product ID (the "Product ID" of the IOPS accessory sources).
    static let appleProducts: [Int: Product] = [
        0x2002: Product(symbol: "airpods", model: "AirPods", kind: .earbuds),
        0x200F: Product(symbol: "airpods", model: "AirPods", kind: .earbuds),
        0x2013: Product(symbol: "airpods.gen3", model: "AirPods", kind: .earbuds),
        0x2019: Product(symbol: "airpods.gen3", model: "AirPods 4", kind: .earbuds),
        0x201B: Product(symbol: "airpods.gen3", model: "AirPods 4", kind: .earbuds),
        0x200E: Product(symbol: "airpodspro", model: "AirPods Pro", kind: .earbuds),
        0x2014: Product(symbol: "airpodspro", model: "AirPods Pro", kind: .earbuds),
        0x2024: Product(symbol: "airpodspro", model: "AirPods Pro", kind: .earbuds),
        0x2027: Product(symbol: "airpodspro", model: "AirPods Pro", kind: .earbuds),
        0x200A: Product(symbol: "airpodsmax", model: "AirPods Max", kind: .headphones),
        0x201F: Product(symbol: "airpodsmax", model: "AirPods Max", kind: .headphones),
        0x2006: Product(symbol: "beats.headphones", model: "Beats Solo", kind: .headphones),
        0x2009: Product(symbol: "beats.headphones", model: "Beats Studio", kind: .headphones),
        0x200C: Product(symbol: "beats.headphones", model: "Beats Solo Pro", kind: .headphones),
        0x2017: Product(symbol: "beats.headphones", model: "Beats Studio Pro", kind: .headphones),
        0x2003: Product(symbol: "earbuds", model: "Powerbeats", kind: .earbuds),
        0x2005: Product(symbol: "earbuds", model: "BeatsX", kind: .earbuds),
        0x200B: Product(symbol: "earbuds", model: "Powerbeats Pro", kind: .earbuds),
        0x200D: Product(symbol: "earbuds", model: "Powerbeats", kind: .earbuds),
        0x2010: Product(symbol: "earbuds", model: "Beats Flex", kind: .earbuds),
        0x2011: Product(symbol: "earbuds", model: "Beats Studio Buds", kind: .earbuds),
        0x2012: Product(symbol: "earbuds", model: "Beats Fit Pro", kind: .earbuds),
        0x2016: Product(symbol: "earbuds", model: "Beats Studio Buds +", kind: .earbuds),
    ]

    static func product(vendorID: Int?, productID: Int?) -> Product? {
        guard vendorID == appleVendorID, let productID else { return nil }
        return appleProducts[productID]
    }

    /// The glyph of an accessory: its product's own glyph, else the generic glyph of its kind.
    static func symbol(vendorID: Int?, productID: Int?, kind: AccessoryKind) -> String {
        if let product = product(vendorID: vendorID, productID: productID) { return product.symbol }
        return symbol(for: kind, isApple: vendorID == appleVendorID)
    }

    /// Generic glyphs. `magicmouse` is restricted to Apple's Magic Mouse, so only Apple mice get it.
    static func symbol(for kind: AccessoryKind, isApple: Bool) -> String {
        switch kind {
        case .headphones: "headphones"
        case .earbuds: "earbuds"
        case .speaker: "hifispeaker"
        case .keyboard: "keyboard"
        case .mouse: isApple ? "magicmouse" : "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left.filled"     // there is no `trackpad` symbol (R3 §3)
        case .gameController: "gamecontroller"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    /// The kind from an IOPS or HID "Accessory Category" ("Headset", "Trackpad", "Audio Battery Case" → nil).
    static func kind(forCategory category: String?) -> AccessoryKind? {
        guard let category = category?.lowercased() else { return nil }
        if category.contains("case") { return nil }
        if category.contains("head") { return .headphones }
        if category.contains("trackpad") { return .trackpad }
        if category.contains("keyboard") { return .keyboard }
        if category.contains("mouse") { return .mouse }
        if category.contains("speaker") { return .speaker }
        if category.contains("game") { return .gameController }
        return nil
    }

    /// Every glyph this module can draw (tests assert that each resolves on this OS).
    static var allSymbols: Set<String> {
        Set(appleProducts.values.map(\.symbol))
            .union(AccessoryKind.allCases.flatMap { [symbol(for: $0, isApple: true), symbol(for: $0, isApple: false)] })
    }
}
