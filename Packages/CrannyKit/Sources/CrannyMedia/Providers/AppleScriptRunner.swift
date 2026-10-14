// CrannyMedia/Providers/AppleScriptRunner.swift — runs the Apple Events fallback's scripts off the main actor
// (ARCHITECTURE.md §6.5, §9.1 rule 3).
//
// Threading: `NSAppleScript.executeAndReturnError` blocks its thread until the player answers (up to the 2-s
// `with timeout` of every script), so scripts never run on the main actor or on Swift's cooperative pool. They run
// on `SerialAppleScriptRunner.shared.queue`, ONE private serial dispatch queue for the whole process: one script at
// a time, in submission order. Each NSAppleScript is created, run and released inside one block on that queue, and
// no other code in Cranny uses NSAppleScript, so no instance is ever used by two threads (the AppleScript component
// itself reports `OSALanguage.isThreadSafe`). Results cross back as Sendable values (`ScriptOutcome`).
import AppKit
import Foundation

/// One script for one player: `tell application id "<bundleID>" to <body>`.
nonisolated struct PlayerScript: Sendable, Equatable {
    let bundleID: String
    /// What to tell the player (`player position`, `playpause`, …).
    let body: String

    /// The full source. A 2-s Apple Event timeout; and if the player quit after it was found running, the script
    /// fails with −600 (procNotFound) before it sends anything, so a script never launches a player.
    var source: String {
        """
        with timeout of 2 seconds
        if not (application id "\(bundleID)" is running) then error number -600
        tell application id "\(bundleID)" to \(body)
        end timeout
        """
    }
}

/// What a script returned, as Sendable values (the descriptor itself stays on the script queue).
nonisolated struct ScriptValue: Sendable, Equatable {
    /// The result as text (`player state as string`); nil when it has no text form.
    var text: String?
    /// The result as a number (`player position`); nil when it is not numeric.
    var number: Double?
    /// The raw bytes of a result that is neither text, a number nor empty (Music's artwork data).
    var binary: Data?

    init(text: String? = nil, number: Double? = nil, binary: Data? = nil) {
        self.text = text; self.number = number; self.binary = binary
    }

    /// Reads a script's result (on the script queue). Text is never parsed as a number, and artwork bytes are never
    /// turned into text.
    init(_ descriptor: NSAppleEventDescriptor) {
        let type = descriptor.descriptorType
        let isText = type == typeUnicodeText || type == typeUTF8Text || type == typeChar
        let isEmpty = type == typeNull || descriptor.data.isEmpty
        text = isText ? descriptor.stringValue : nil
        number = isText || isEmpty ? nil : descriptor.coerce(toDescriptorType: DescType(typeIEEE64BitFloatingPoint))?.doubleValue
        binary = isText || isEmpty || number != nil ? nil : descriptor.data
    }
}

/// How a script ended.
nonisolated enum ScriptOutcome: Sendable, Equatable {
    /// It ran; its result (an empty `ScriptValue` for a command that returns nothing).
    case value(ScriptValue)
    /// The player was not running: nothing was sent.
    case notRunning
    /// AppleScript reported an error: −1743 Automation denied, −1712 the 2-s timeout, …
    case failed(code: Int)
}

/// Runs player scripts off the main actor. Scripts submitted one after another run in that order.
nonisolated protocol AppleScriptRunning: Sendable {
    /// Runs `script` after every script submitted before it and returns its outcome. Never blocks the caller's
    /// thread; the wait is a suspension.
    func run(_ script: PlayerScript) async -> ScriptOutcome
}

/// The app's runner: NSAppleScript on one serial queue (see the file header).
nonisolated final class SerialAppleScriptRunner: AppleScriptRunning {   // Sendable: only immutable `let`s
    /// The process-wide runner: every provider instance shares the queue, so scripts never run concurrently.
    static let shared = SerialAppleScriptRunner()

    private let queue: DispatchQueue
    private let execute: @Sendable (PlayerScript) -> ScriptOutcome

    /// `execute` runs on the runner's queue (tests pass a fake; the app runs NSAppleScript).
    init(label: String = "app.cranny.media.applescript",
         execute: @escaping @Sendable (PlayerScript) -> ScriptOutcome = SerialAppleScriptRunner.runAppleScript) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.execute = execute
    }

    func run(_ script: PlayerScript) async -> ScriptOutcome {
        let execute = execute
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: execute(script)) }
        }
    }

    /// Runs on the queue: only for a running player (checked again inside the script).
    static func runAppleScript(_ script: PlayerScript) -> ScriptOutcome {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: script.bundleID).isEmpty else {
            return .notRunning
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: script.source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            return number == procNotFound ? .notRunning : .failed(code: number)
        }
        return result.map { .value(ScriptValue($0)) } ?? .failed(code: 0)
    }
}
