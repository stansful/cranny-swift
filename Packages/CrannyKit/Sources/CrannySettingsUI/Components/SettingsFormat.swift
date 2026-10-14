// CrannySettingsUI/Components/SettingsFormat.swift — values with their units, always through `FormatStyle`
// (DESIGN.md §17): "120 ms", "2.6 s", "±0 pt", "100 %". Pure functions of the value and a locale (tested).
import CrannyCore
import Foundation

enum SettingsFormat {
    /// A signed tune in points: "±0 pt", "+2 pt", "−1.5 pt" (Notch fit, panel padding).
    static func points(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let number = signedNumber(value, locale: locale)
        return String(localized: "\(number) pt", bundle: .module,
                      comment: "Settings: a length in typographic points with its sign, e.g. \"+2 pt\" (Notch fit, panel padding)")
    }

    /// "+2", "−1.5" with a real minus sign, "±0" for zero.
    static func signedNumber(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "±0" }
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return (rounded > 0 ? "+" : "\u{2212}") + magnitude
    }

    /// "120 ms" (hover delay).
    static func milliseconds(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.milliseconds(Int((seconds * 1000).rounded()))
            .formatted(.units(allowed: [.milliseconds], width: .abbreviated).locale(locale))
    }

    /// "10 s", "2.6 s" (durations and timeouts).
    static func seconds(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let tenths = (seconds * 10).rounded()
        let fraction: Duration.UnitsFormatStyle.FractionalPartDisplayStrategy =
            tenths.truncatingRemainder(dividingBy: 10) == 0 ? .hide : .show(length: 1)
        return Duration.milliseconds(Int(tenths) * 100)
            .formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: fraction).locale(locale))
    }

    /// "100 %" (gesture sensitivity).
    static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "Media, 4 cells", "Peeks, Studio Display": a name and its detail as one VoiceOver label, through a localized
    /// pattern rather than concatenation (ARCHITECTURE §8.7.5).
    static func pair(_ name: String, _ detail: String) -> String {
        String(localized: "\(name), \(detail)", bundle: .module,
               comment: "Settings: a VoiceOver label made of a name and its detail (\"Media, 4 cells\", \"Peeks, Studio Display\")")
    }

    /// "Song, artist and controls · 4–6 cells": a description and a detail on one line (widget library).
    static func detailed(_ text: String, _ detail: String) -> String {
        String(localized: "\(text) · \(detail)", bundle: .module,
               comment: "Settings ▸ Layout & Widgets: a widget's description and the widths it allows, on one line")
    }

    /// A timeout where 0 means off: "Off" or "10 s".
    static func timeout(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        seconds <= 0 ? String(localized: "Off", bundle: .module, comment: "Settings: option that turns something off (a timeout, a display)")
                     : self.seconds(seconds, locale: locale)
    }
}
