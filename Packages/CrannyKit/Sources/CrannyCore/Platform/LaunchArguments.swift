// CrannyCore/Platform/LaunchArguments.swift
// The one parser for command-line arguments: `--diagnostics <file>` (every build) and the Debug visual-QA hooks
// (`--qa-state open`, `--qa-media playing`, …; docs/CONTRIBUTING.md). Pure: tests pass their own arguments.
import Foundation

/// Command-line arguments as `--name value` pairs and bare flags.
public nonisolated struct LaunchArguments: Sendable, Equatable {
    /// All arguments, the executable path first (as `ProcessInfo.arguments`).
    public let values: [String]

    /// The arguments to parse.
    public init(_ values: [String]) { self.values = values }

    /// This process's arguments.
    public static var current: LaunchArguments { LaunchArguments(ProcessInfo.processInfo.arguments) }

    /// Whether the bare flag `name` is present (`--qa-hints`).
    public func contains(_ name: String) -> Bool { values.contains(name) }

    /// The argument after the first `name` (`value(after: "--qa-state")` → "open"), or nil when `name` is absent or last.
    public func value(after name: String) -> String? {
        guard let index = values.firstIndex(of: name), index + 1 < values.count else { return nil }
        return values[index + 1]
    }

    /// `value(after:)` as an integer, nil when absent or not a number.
    public func int(after name: String) -> Int? { value(after: name).flatMap { Int($0) } }

    /// `value(after:)` as a number, nil when absent or not a number.
    public func double(after name: String) -> Double? { value(after: name).flatMap { Double($0) } }

    // MARK: Visual QA snapshots (one rule for the three readers)

    /// `--qa-snapshot <file.png>`: NotchUI renders the primary panel's canvas to that PNG (`.png`, any case).
    public var qaPanelSnapshot: String? {
        value(after: "--qa-snapshot").flatMap { Self.isPNG($0) ? $0 : nil }
    }

    /// `--qa-snapshot <folder>`: the shell and the menu bar write in-process window snapshots there (anything that
    /// is not a `.png` file).
    public var qaSnapshotDirectory: String? {
        value(after: "--qa-snapshot").flatMap { Self.isPNG($0) ? nil : $0 }
    }

    private static func isPNG(_ path: String) -> Bool { path.lowercased().hasSuffix(".png") }
}
