// CrannyTray/Store/TrayStore+Pipelines.swift — running pipelines on tray items or on files dropped on a pipeline zone
// (DESIGN.md §8.2–§8.3): progress on the source tiles, cancellation, results slid in beside the source with an Undo
// chip for 5 s, a `.generic` haptic and a VoiceOver announcement; errors as a one-line badge.
// Runs are background work with a visible ring, so they run at `.utility`, the `ditto` tool too (efficiency cores,
// throttled under thermal pressure and Low Power Mode). Progress ticks go to a per-job `TrayJobProgress` box, not to
// `jobs`, so a tick re-renders only the views that show that job's ring; `jobs` changes only when a run starts, fails
// or ends.
import CrannyCore
import Foundation
import Observation
import os

private nonisolated let log = Log.logger(.pipelines)

/// A pipeline run in progress (or a failed run of dropped files, shown as a tile until dismissed).
nonisolated struct TrayJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let pipelineID: String
    /// Localized pipeline name (VoiceOver value, tooltip).
    let title: String
    /// Tray items being processed: their tiles dim behind the ring.
    let sourceIDs: [UUID]
    /// Dropped files that are not in the Tray get a placeholder tile with this name.
    let placeholderName: String?
    /// The fraction done when the job was made (previews, QA). While it runs, the live value is
    /// `TrayStore.progress(of:)`, which ticks without touching `jobs`.
    var progress: Double = 0
    var failure: String?
}

/// The live progress of one running job. Observable on its own, so a tick invalidates only the views that read it.
@MainActor @Observable final class TrayJobProgress {
    /// 0…1, never going back.
    private(set) var fraction: Double

    init(_ fraction: Double) { self.fraction = fraction }

    /// Moves forward to `fraction` (an equal or lower report changes nothing and notifies nobody).
    func advance(to fraction: Double) {
        let next = max(self.fraction, fraction)
        if next != self.fraction { self.fraction = next }
    }
}

/// The Undo chip offered for 5 s after a run wrote files.
nonisolated struct TrayUndoOffer: Equatable, Sendable {
    let id: UUID
    let title: String
    let itemIDs: [UUID]
    /// Files Cranny wrote outside the Tray; Undo moves them to the Trash.
    let files: [URL]
}

extension TrayStore {
    /// How long the Undo chip stays (DESIGN.md §8.2).
    static let undoDuration: Duration = .seconds(5)

    /// The run's settings, snapshotted now.
    var pipelineOptions: PipelineOptions {
        PipelineOptions(quality: settings[TraySettings.jpegQuality], maxDimension: settings[TraySettings.maxDimension],
                        zipNaming: settings[TraySettings.zipNaming], naming: .localized, date: now())
    }

    func title(of pipeline: PipelineDefinition) -> String {
        PipelineTitles.title(pipeline, maxDimension: settings[TraySettings.maxDimension])
    }

    /// How far `job` is: the live box while it runs, else the value it was made with. Read it in the body that draws
    /// the ring (or says the percent), so only that view follows the ticks.
    func progress(of job: TrayJob) -> Double {
        liveProgress[job.id]?.fraction ?? job.progress
    }

    // MARK: Starting

    /// Runs `pipeline` on tray items (the chips). Results go beside the last source and become the selection.
    func run(_ pipeline: PipelineDefinition, on ids: [UUID]) {
        let sources = items.filter { ids.contains($0.id) && urls[$0.id] != nil }
        guard !sources.isEmpty else { return }
        for source in sources { failures[source.id] = nil }
        let job = TrayJob(id: UUID(), pipelineID: pipeline.id, title: title(of: pipeline), sourceIDs: sources.map(\.id),
                          placeholderName: nil)
        start(job, pipeline: pipeline, inputs: sources.compactMap { urls[$0.id] }, after: sources.last?.id, selectsResults: true)
    }

    /// Runs `pipeline` on files dropped on its catch zone; the result is kept in the Tray (DESIGN.md §8.3). Temporary
    /// files (resolved promises) are copied into the run's own folder first, so the shell may clean up after the drop.
    func run(_ pipeline: PipelineDefinition, dropped urls: [URL]) async -> Bool {
        guard !urls.isEmpty else { return false }
        await load()
        let job = TrayJob(id: UUID(), pipelineID: pipeline.id, title: title(of: pipeline), sourceIDs: [],
                          placeholderName: urls.count == 1 ? urls[0].lastPathComponent : nil)
        let inputs = await Self.stage(urls, storage: storage, into: directories.work.appending(path: "\(job.id.uuidString)-input"))
        start(job, pipeline: pipeline, inputs: inputs, origins: urls, after: nil, selectsResults: false)
        if settings[TraySettings.opensTrayOnDrop] { notch.open(page: .tray, focus: nil, reason: .drag) }
        return true
    }

    private func start(_ job: TrayJob, pipeline: PipelineDefinition, inputs: [URL], origins: [URL]? = nil,
                       after anchor: UUID?, selectsResults: Bool) {
        liveProgress[job.id] = TrayJobProgress(job.progress)
        jobs.append(job)
        let options = pipelineOptions
        let location = settings[TraySettings.outputLocation]
        let work = directories.work.appending(path: job.id.uuidString, directoryHint: .isDirectory)
        let destinationSource = (origins ?? inputs).first
        let jobID = job.id
        log.info("run \(pipeline.id, privacy: .public) on \(inputs.count, privacy: .public) file(s)")
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in self?.setProgress(fraction, of: jobID) }
        }
        // `.utility`: the steps (`@concurrent`) run at this priority instead of the main actor's user-initiated one.
        tasks[jobID] = Task(priority: .utility) { [weak self] in
            do {
                let result = try await PipelineRunner.run(pipeline.steps, inputs: inputs, options: options, workDirectory: work,
                                                          progress: report)
                await self?.finish(jobID, result: result, inputs: origins ?? inputs, destinationSource: destinationSource,
                                   location: location, after: anchor, selectsResults: selectsResults)
            } catch is CancellationError {
                self?.endJob(jobID)
            } catch {
                self?.fail(jobID, error)
            }
            await Self.removeFolder(work)
            if origins != nil { await Self.removeFolder(work.deletingLastPathComponent().appending(path: "\(jobID.uuidString)-input")) }
        }
    }

    /// Cancels a run (✕ on the ring).
    func cancel(_ jobID: UUID) { tasks[jobID]?.cancel() }

    /// Hides a failed run of dropped files.
    func dismissJob(_ jobID: UUID) { jobs.removeAll { $0.id == jobID } }

    // MARK: Finishing

    /// A tick: only the job's box changes (gone once the job ended or failed, so late ticks are dropped).
    private func setProgress(_ fraction: Double, of jobID: UUID) {
        liveProgress[jobID]?.advance(to: fraction)
    }

    private func finish(_ jobID: UUID, result: PipelineRunResult, inputs: [URL], destinationSource: URL?,
                        location: TrayOutputLocation, after anchor: UUID?, selectsResults: Bool) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        var finalURLs = inputs
        var lostResults = false
        if !result.files.isEmpty {
            // Where results go is decided off the main actor too: it checks the folder (§9.2, may be a network volume).
            let placed = await Self.move(result.files, placement: placement, source: destinationSource, location: location)
            guard !placed.isEmpty else { return fail(jobID, TrayError.cannotWrite) }
            let made = await storage.linkResults(placed, now: now())
            lostResults = placed.count < result.files.count || made.count < placed.count
            insert(made.map(\.item), urls: Dictionary(uniqueKeysWithValues: made.map { ($0.item.id, $0.url) }), after: anchor)
            freshItems.formUnion(made.map(\.item.id))
            if selectsResults { selection.set(made.map(\.item.id)) }
            offerUndo(TrayUndoOffer(id: jobID, title: job.title, itemIDs: made.map(\.item.id), files: placed))
            finalURLs = placed
        }
        if result.copiesPaths {
            system.copy(text: finalURLs.map(\.path).joined(separator: "\n"))
            notch.flash(symbol: "doc.on.doc", label: Self.copiedLabel)
        }
        if let text = result.text {
            system.copy(text: text)
            notch.flash(symbol: "doc.on.doc", label: Self.copiedLabel)
        }
        if result.reveals { system.reveal(finalURLs) }
        haptics.play(.generic)
        // Some results could not be placed or linked: the ones that could are in the Tray, the source says the rest failed.
        if lostResults { return fail(jobID, TrayError.cannotWrite) }
        announce(String(localized: "\(job.title) finished", bundle: .module,
                        comment: "VoiceOver announcement: a tray pipeline finished; the argument is the pipeline name"))
        endJob(jobID)
    }

    /// "Copied" / «Готово» in the band after Copy paths (the chip, the context menu, a pipeline ending in Copy paths)
    /// and after a pipeline copied text, always beside the copy glyph (`doc.on.doc`), which says that something was
    /// copied (design ruling E4); the word fits the wing in every language (`NotchControl.flash`).
    static var copiedLabel: String {
        String(localized: "Copied", bundle: .module,
               comment: "Notch flash: confirms Copy paths or a copied text, beside the copy glyph that says it was copied; one short word that must fit the compact wing (measured, see NotchControl.flash)")
    }

    private func fail(_ jobID: UUID, _ error: any Error) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let message = (error as? TrayError)?.errorDescription ?? TrayError.cannotWrite.errorDescription ?? ""
        log.error("pipeline \(self.jobs[i].pipelineID, privacy: .public) failed: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
        tasks[jobID] = nil
        liveProgress[jobID] = nil
        if jobs[i].sourceIDs.isEmpty {
            jobs[i].failure = message                       // dropped files: the placeholder tile shows the error
        } else {
            for id in jobs[i].sourceIDs { failures[id] = message }
            jobs.remove(at: i)
        }
        announce(message)
    }

    private func endJob(_ jobID: UUID) {
        jobs.removeAll { $0.id == jobID }
        tasks[jobID] = nil
        liveProgress[jobID] = nil
    }

    // MARK: Undo

    private func offerUndo(_ offer: TrayUndoOffer) {
        undoOffer = offer
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoDuration)
            guard !Task.isCancelled, self?.undoOffer?.id == offer.id else { return }
            self?.undoOffer = nil
        }
    }

    /// The Undo chip: results leave the Tray and the files Cranny wrote go to the Trash.
    func undo() {
        guard let offer = undoOffer else { return }
        undoOffer = nil
        undoTask?.cancel()
        remove(Set(offer.itemIDs))
        let system = system
        Task { await system.trash(offer.files) }
    }

    // MARK: VoiceOver

    /// A VoiceOver announcement; the live system sends it through the app-wide limit (one per 10 s, DESIGN.md §16).
    func announce(_ message: String) {
        system.announce(message)
    }

    // MARK: Files (off the main actor)

    /// Moves results into the folder `placement` picks for `source` under unique names; returns where they landed.
    @concurrent static func move(_ files: [URL], placement: OutputPlacement, source: URL?,
                                 location: TrayOutputLocation) async -> [URL] {
        let directory = placement.directory(for: source, location: location)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var placed: [URL] = []
        for file in files {
            let target = OutputNaming.uniqueURL(base: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension,
                                                in: directory)
            do {
                try FileManager.default.moveItem(at: file, to: target)
                placed.append(target)
            } catch {
                log.error("could not place a result: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
        return placed
    }

    /// Copies temporary inputs into `folder` (other files are used where they are).
    @concurrent static func stage(_ urls: [URL], storage: TrayStorage, into folder: URL) async -> [URL] {
        guard urls.contains(where: storage.isTemporary) else { return urls }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return urls.map { url in
            guard storage.isTemporary(url) else { return url }
            let copy = OutputNaming.uniqueURL(base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension, in: folder)
            return (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : url
        }
    }

    @concurrent static func removeFolder(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }
}
