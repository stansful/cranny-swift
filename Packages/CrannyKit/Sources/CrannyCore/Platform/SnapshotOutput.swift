// CrannyCore/Platform/SnapshotOutput.swift
// Where the opt-in snapshot suites write their PNGs: ONE variable for every module (docs/CONTRIBUTING.md ▸ Opt-in
// tests). Read by test targets only; the app never calls it.
import Foundation

/// The output of the opt-in snapshot suites: `CRANNY_SNAPSHOT_DIR=<dir>` turns them on, and each suite writes into
/// its own folder, `<dir>/<folder>/` (one folder per test target), so a run of every suite never mixes files.
/// `CRANNY_SNAPSHOT_LANGUAGE=ru` asks the suites that can render another language for it.
public nonisolated enum SnapshotOutput {
    /// The variable that turns the snapshot suites on and names the folder they write into.
    public static let directoryVariable = "CRANNY_SNAPSHOT_DIR"
    /// The variable that asks for another language than the development language (e.g. `ru`).
    public static let languageVariable = "CRANNY_SNAPSHOT_LANGUAGE"

    /// `<CRANNY_SNAPSHOT_DIR>/<folder>/`, or nil when the variable is not set (the suite then writes nothing). The
    /// folder is not created here.
    public static func directory(_ folder: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let root = environment[directoryVariable], !root.isEmpty else { return nil }
        return URL(filePath: root, directoryHint: .isDirectory).appending(path: folder, directoryHint: .isDirectory)
    }

    /// The language asked for, or nil for the development language (English).
    public static func language(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let language = environment[languageVariable], !language.isEmpty else { return nil }
        return language
    }
}
