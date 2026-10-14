// Pure pipeline logic: definitions, validation, contextual chips, catch zones and their layout, persistence.
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@Suite struct PipelineModelTests {
    @Test func validChainsHaveNoProblems() {
        #expect(PipelineValidation.problems(in: [.resize(to: .scale(percent: 50)), .convert(format: .jpeg), .copyPaths]).isEmpty)
        #expect(PipelineValidation.problems(in: [.compress, .zip, .reveal]).isEmpty)
        #expect(PipelineValidation.problems(in: [.convert(format: .png), .makePDF]).isEmpty)
        #expect(PipelineValidation.problems(in: [.copyPaths, .zip]).isEmpty)
    }

    @Test func stepsWithNothingToWorkOnAreReported() {
        let problems = PipelineValidation.problems(in: [.zip, .compress])
        #expect(problems == [PipelineProblem(stepIndex: 1, needs: .images, gets: .archives)])
        // Unzip can make anything: an image step after it is not guaranteed to have images.
        #expect(PipelineValidation.problems(in: [.unzip, .resize(to: .scale(percent: 50))]).map(\.stepIndex) == [1])
        // A pass-through first step takes any file, so the image step after it may get none.
        #expect(PipelineValidation.problems(in: [.copyPaths, .compress]).map(\.stepIndex) == [1])
        #expect(!PipelineTitles.problem(problems[0]).isEmpty)
    }

    @Test func acceptsOnlyWhatTheFirstStepTakes() {
        let web = PipelineDefinition(id: "user.web", name: "Web", symbol: "wand.and.stars",
                                     steps: [.resize(to: .maxDimension(pixels: 0)), .convert(format: .jpeg)])
        #expect(web.accepts([.png, .jpeg]))
        #expect(!web.accepts([.png, .pdf]))
        #expect(!web.accepts([]))
        #expect(BuiltinPipelines.zip.accepts([.pdf, .folder, .png]))
        #expect(BuiltinPipelines.unzip.accepts([.zip]))
        #expect(!BuiltinPipelines.unzip.accepts([.pdf]))
        #expect(BuiltinPipelines.makePDF.accepts([.png, .pdf]))
        #expect(BuiltinPipelines.compressVideo.accepts([.quickTimeMovie, .mpeg4Movie]))
        let broken = PipelineDefinition(id: "user.broken", name: nil, symbol: "wand.and.stars", steps: [.zip, .compress])
        #expect(!broken.accepts([.png]))
        let empty = PipelineDefinition.newUserPipeline(name: "")
        #expect(empty.isUserPipeline && !empty.accepts([.png]))
    }

    @Test func chipsAreOnlyThoseValidForEverySelectedItem() {
        let images = PipelineChipSet.make(types: [.png, .png], userPipelines: [], maxDimension: 1600,
                                          writable: [.jpeg, .png, .heic, .tiff])
        #expect(images.compress)
        #expect(images.convertFormats == [.jpeg, .heic, .tiff])          // not to PNG: they already are
        #expect(images.resizeOptions == [.scale(percent: 50), .maxDimension(pixels: 0), .maxDimension(pixels: 2048)])
        #expect(images.zip && images.copyPaths && images.airDrop && !images.unzip)
        #expect(images.more.map(\.id).contains(BuiltinPipelines.makePDF.id))

        let mixed = PipelineChipSet.make(types: [.png, .pdf], userPipelines: [], maxDimension: 1600)
        #expect(!mixed.compress && mixed.convertFormats.isEmpty && mixed.resizeOptions.isEmpty)
        #expect(mixed.more.map(\.id) == [BuiltinPipelines.makePDF.id])

        let archives = PipelineChipSet.make(types: [.zip], userPipelines: [], maxDimension: 1600)
        #expect(archives.unzip && !archives.compress)

        let large = PipelineChipSet.make(types: [.jpeg], userPipelines: [], maxDimension: 2560, writable: [.jpeg, .png])
        #expect(large.resizeOptions == [.scale(percent: 50), .maxDimension(pixels: 2048), .maxDimension(pixels: 0)])
        #expect(large.convertFormats == [.png])

        let user = PipelineDefinition(id: "user.a", name: "A", symbol: "wand.and.stars", steps: [.compress])
        #expect(PipelineChipSet.make(types: [.png], userPipelines: [user], maxDimension: 1600).user == [user])
        #expect(PipelineChipSet.make(types: [.pdf], userPipelines: [user], maxDimension: 1600).user.isEmpty)
        #expect(PipelineChipSet.make(types: [], userPipelines: [user], maxDimension: 1600) == PipelineChipSet())
    }

    @Test func catchZonesAreThePinnedPipelinesThatTakeTheDrag() {
        let pinned = ["builtin.compress", "builtin.zip", "user.web", "builtin.unzip"]
        let web = PipelineDefinition(id: "user.web", name: "Web", symbol: "wand.and.stars", steps: [.resize(to: .scale(percent: 50))])
        #expect(BuiltinPipelines.catchZones(pinned: pinned, userPipelines: [web], types: [.png]).map(\.id)
                == ["builtin.compress", "builtin.zip", "user.web"])
        #expect(BuiltinPipelines.catchZones(pinned: pinned, userPipelines: [web], types: [.pdf]).map(\.id) == ["builtin.zip"])
        #expect(BuiltinPipelines.catchZones(pinned: pinned, userPipelines: [web], types: [.zip]).map(\.id)
                == ["builtin.zip", "builtin.unzip"])
        // A drag that only says "file URL": only pipelines that take any file.
        #expect(BuiltinPipelines.catchZones(pinned: pinned, userPipelines: [], types: [.fileURL]).map(\.id) == ["builtin.zip"])
        #expect(BuiltinPipelines.catchZones(pinned: pinned, userPipelines: [], types: []).map(\.id) == ["builtin.zip"])
        // Unknown ids (a deleted user pipeline) are skipped.
        #expect(BuiltinPipelines.catchZones(pinned: ["user.gone"], userPipelines: [], types: [.png]).isEmpty)
    }

    @Test func catchLayoutKeepsAtLeastFourCellsForKeep() {
        #expect(CatchLayout.cells(total: 12, showsAirDrop: true, pipelines: 3) == (keep: 4, airDrop: 2, pipelines: 3))
        #expect(CatchLayout.cells(total: 10, showsAirDrop: true, pipelines: 3) == (keep: 4, airDrop: 2, pipelines: 2))
        #expect(CatchLayout.cells(total: 10, showsAirDrop: true, pipelines: 0) == (keep: 8, airDrop: 2, pipelines: 0))
        #expect(CatchLayout.cells(total: 5, showsAirDrop: true, pipelines: 2) == (keep: 5, airDrop: 0, pipelines: 0))
        #expect(CatchLayout.cells(total: 8, showsAirDrop: false, pipelines: 3) == (keep: 4, airDrop: 0, pipelines: 2))
        #expect(CatchLayout.columns(width: NookGrid().width(cells: 10), grid: NookGrid()) == 10)
        #expect(CatchLayout.columns(width: 10, grid: NookGrid()) == 1)
    }

    @Test func definitionsRoundTripThroughSettings() throws {
        let pipeline = PipelineDefinition(id: "user.x", name: "Web export", symbol: "wand.and.stars",
                                          steps: [.resize(to: .maxDimension(pixels: 1600)), .convert(format: .avif), .stripMetadata,
                                                  .removeBackground, .makePDF, .compressVideo, .zip, .unzip, .copyPaths, .copyText, .reveal,
                                                  .resize(to: .scale(percent: 25)), .compress])
        let data = try JSONEncoder().encode([pipeline])
        #expect(try JSONDecoder().decode([PipelineDefinition].self, from: data) == [pipeline])

        let settings = SettingsStore(defaults: UserDefaults(suiteName: "cranny.tray.tests.\(UUID().uuidString)") ?? .standard)
        settings[TraySettings.userPipelines] = [pipeline]
        #expect(settings[TraySettings.userPipelines] == [pipeline])
        #expect(settings[TraySettings.pinnedPipelines] == ["builtin.compress", "builtin.zip"])
    }

    @Test func settingsDefaultsMatchTheArchitecture() {
        #expect(TraySettings.retention.defaultValue == .untilRemoved)
        #expect(TraySettings.maxItems.defaultValue == 50)
        #expect(TraySettings.storageMode.defaultValue == .copy)
        #expect(TraySettings.opensTrayOnDrop.defaultValue)
        #expect(TraySettings.showsAirDropZone.defaultValue)
        #expect(TraySettings.userPipelines.defaultValue.isEmpty)
        #expect(TraySettings.jpegQuality.defaultValue == 0.8)
        #expect(TraySettings.maxDimension.defaultValue == 1600)
        #expect(TraySettings.outputLocation.defaultValue == .nextToSource)
        #expect(TraySettings.zipNaming.defaultValue == .firstItem)
        #expect(TraySettings.retention.id == "tray.retention")
        // Every pinned default exists.
        #expect(TraySettings.pinnedPipelines.defaultValue.allSatisfy { BuiltinPipelines.definition($0, userPipelines: []) != nil })
    }

    @Test func builtinIdsAreStableAndUnique() {
        let ids = BuiltinPipelines.all(userPipelines: []).map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("builtin.compress") && ids.contains("builtin.zip") && ids.contains("builtin.copyPaths"))
        #expect(BuiltinPipelines.convert(.png).id == "builtin.convert.png")
    }

    @Test func titlesNameEveryStep() {
        for step in PipelineStep.catalog + [.convert(format: .heic), .resize(to: .scale(percent: 50))] {
            #expect(!PipelineTitles.step(step, maxDimension: 1600).isEmpty)
            #expect(!PipelineTitles.kind(step, maxDimension: 1600).isEmpty)
        }
        #expect(PipelineTitles.step(.resize(to: .maxDimension(pixels: 0)), maxDimension: 1600).contains("1600"))
        #expect(PipelineTitles.step(.resize(to: .maxDimension(pixels: 2048)), maxDimension: 1600).contains("2048"))
        let named = PipelineDefinition(id: "user.n", name: " Web ", symbol: "wand.and.stars", steps: [.zip])
        #expect(PipelineTitles.title(named, maxDimension: 1600) == "Web")
        #expect(!PipelineTitles.title(.newUserPipeline(name: ""), maxDimension: 1600).isEmpty)
    }

    @Test func imageFormatsMapToTheirTypes() {
        #expect(TrayImageFormat(type: .jpeg) == .jpeg)
        #expect(TrayImageFormat(type: .png) == .png)
        #expect(TrayImageFormat(type: .heic) == .heic)
        #expect(TrayImageFormat(type: .pdf) == nil)
        #expect(TrayImageFormat.allCases.allSatisfy { !$0.fileExtension.isEmpty && !$0.displayName.isEmpty })
    }
}
