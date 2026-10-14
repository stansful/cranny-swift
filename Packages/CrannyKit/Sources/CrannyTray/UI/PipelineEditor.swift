// CrannyTray/UI/PipelineEditor.swift — Settings ▸ Tray ▸ pipeline editor (DESIGN.md §11.1: "a chain builder: steps,
// reorder, a preview of the output name"). A sheet on the Settings window: name, steps with their parameters, a warning
// under any step that would have nothing to work on, and what the chain makes of a sample file.
import CrannyCore
import Foundation
import SwiftUI

struct PipelineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PipelineDefinition
    let maxDimension: Int
    let onSave: @MainActor (PipelineDefinition) -> Void

    init(pipeline: PipelineDefinition, maxDimension: Int, onSave: @escaping @MainActor (PipelineDefinition) -> Void) {
        _draft = State(initialValue: pipeline)
        self.maxDimension = maxDimension
        self.onSave = onSave
    }

    var body: some View {
        let problems = PipelineValidation.problems(in: draft.steps)
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(text: nameBinding, prompt: Text("Web export", bundle: .module, comment: "Pipeline editor: example name in the empty name field")) {
                        Text("Name", bundle: .module, comment: "Pipeline editor: name field label")
                    }
                }
                Section {
                    if draft.steps.isEmpty {
                        Text("Add a step to begin.", bundle: .module, comment: "Pipeline editor: empty chain")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                        StepRow(step: stepBinding(index), index: index, count: draft.steps.count, maxDimension: maxDimension,
                                problem: problems.first { $0.stepIndex == index }) { action in
                            apply(action, at: index)
                        }
                    }
                    .onMove { from, to in draft.steps.move(fromOffsets: from, toOffset: to) }
                    addStepMenu
                } header: {
                    Text("Steps", bundle: .module, comment: "Pipeline editor: section header")
                } footer: {
                    if let preview = preview {
                        Text(verbatim: preview).font(.callout.monospaced()).foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Example: \(preview)", bundle: .module, comment: "Pipeline editor: VoiceOver label of the output-name preview"))
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module, comment: "Pipeline editor: button") }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSave(draft)
                    dismiss()
                } label: { Text("Save", bundle: .module, comment: "Pipeline editor: button") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.steps.isEmpty || !problems.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 420, idealHeight: 480)
    }

    // MARK: Steps

    private var addStepMenu: some View {
        Menu {
            ForEach(PipelineStep.catalog, id: \.kind) { step in
                Button { draft.steps.append(defaultStep(step)) } label: {
                    Text(verbatim: PipelineTitles.kind(step, maxDimension: maxDimension))
                }
                .disabled(step.kind == "convert" && ImageSteps.writableFormats.isEmpty)
            }
        } label: {
            Label { Text("Add Step", bundle: .module, comment: "Pipeline editor: menu that adds a step") } icon: { Image(systemName: "plus") }
        }
        .fixedSize()
    }

    private func defaultStep(_ step: PipelineStep) -> PipelineStep {
        if case .convert = step { return .convert(format: ImageSteps.writableFormats.first ?? .jpeg) }
        return step
    }

    private func apply(_ action: StepRow.Action, at index: Int) {
        switch action {
        case .moveUp where index > 0: draft.steps.swapAt(index, index - 1)
        case .moveDown where index < draft.steps.count - 1: draft.steps.swapAt(index, index + 1)
        case .remove: draft.steps.remove(at: index)
        default: break
        }
    }

    private func stepBinding(_ index: Int) -> Binding<PipelineStep> {
        Binding { draft.steps.indices.contains(index) ? draft.steps[index] : .zip }
            set: { if draft.steps.indices.contains(index) { draft.steps[index] = $0 } }
    }

    private var nameBinding: Binding<String> {
        Binding { draft.name ?? "" } set: { draft.name = $0 }
    }

    private var preview: String? {
        let sample = PipelinePreview.sample(for: draft.input)
        var options = PipelineOptions()
        options.maxDimension = maxDimension
        options.naming = .localized
        guard let output = PipelinePreview.outputName(of: draft.steps, sample: sample, options: options) else { return nil }
        return "\(sample.name) → \(output)"
    }
}

/// One step: its title, its parameter (format, size), reorder and remove.
private struct StepRow: View {
    enum Action { case moveUp, moveDown, remove }

    @Binding var step: PipelineStep
    let index: Int
    let count: Int
    let maxDimension: Int
    let problem: PipelineProblem?
    let perform: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                parameter
                Spacer()
                Menu {
                    Button { perform(.moveUp) } label: { Text("Move Up", bundle: .module, comment: "Pipeline editor: step menu") }
                        .disabled(index == 0)
                    Button { perform(.moveDown) } label: { Text("Move Down", bundle: .module, comment: "Pipeline editor: step menu") }
                        .disabled(index == count - 1)
                    Divider()
                    Button(role: .destructive) { perform(.remove) } label: {
                        Text("Remove Step", bundle: .module, comment: "Pipeline editor: step menu")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Step options", bundle: .module, comment: "Pipeline editor: VoiceOver label of a step's menu"))
            }
            if let problem {
                Label { Text(verbatim: PipelineTitles.problem(problem)) } icon: { Image(systemName: "exclamationmark") }
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var parameter: some View {
        switch step {
        case .convert(let format):
            Picker(selection: Binding { format } set: { step = .convert(format: $0) }) {
                ForEach(ImageSteps.writableFormats, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
            } label: {
                Text(verbatim: PipelineTitles.kind(step, maxDimension: maxDimension))
            }
            .fixedSize()
        case .resize(let target):
            Picker(selection: Binding { target } set: { step = .resize(to: $0) }) {
                ForEach([25, 50, 75], id: \.self) { percent in
                    Text(verbatim: PipelineTitles.step(.resize(to: .scale(percent: percent)), maxDimension: maxDimension))
                        .tag(TrayResize.scale(percent: percent))
                }
                Divider()
                Text(verbatim: PipelineTitles.step(.resize(to: .maxDimension(pixels: 0)), maxDimension: maxDimension))
                    .tag(TrayResize.maxDimension(pixels: 0))
                ForEach(TraySettings.maxDimensionChoices.filter { $0 != maxDimension }, id: \.self) { pixels in
                    Text(verbatim: PipelineTitles.step(.resize(to: .maxDimension(pixels: pixels)), maxDimension: maxDimension))
                        .tag(TrayResize.maxDimension(pixels: pixels))
                }
            } label: {
                Text(verbatim: PipelineTitles.kind(step, maxDimension: maxDimension))
            }
            .fixedSize()
        default:
            Text(verbatim: PipelineTitles.step(step, maxDimension: maxDimension))
        }
    }
}

#Preview("Pipeline editor") {
    PipelineEditor(pipeline: PipelineDefinition(id: "user.preview", name: "Web export", symbol: "wand.and.stars",
                                                steps: [.resize(to: .scale(percent: 50)), .convert(format: .jpeg), .copyPaths]),
                   maxDimension: 1600) { _ in }
}
