// CrannyTray/UI/TraySettingsPane.swift — Settings ▸ Tray (DESIGN.md §11.1): retention, max items, copies or links,
// open the Tray on drop, AirDrop zone, pinned pipelines (drop zones), the pipeline editor and the defaults (JPEG
// quality, max dimension, output location, zip naming). Settings is an ordinary window: system controls and text
// styles (§11.3), a dot before changed values and "Reset to Default" in each row's context menu.
import CrannyCore
import Foundation
import SwiftUI

struct TraySettingsPane: View {
    let store: TrayStore
    @State private var editing: PipelineDefinition?
    @State private var confirmsClear = false

    private var settings: SettingsStore { store.settings }
    private static let lastSection = "tray.settings.content"

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                storage
                dropping
                pinned
                userPipelines
                defaults
                content.id(Self.lastSection)
            }
            .formStyle(.grouped)
            .onAppear { if TrayQA.scrollsSettingsToBottom { proxy.scrollTo(Self.lastSection, anchor: .bottom) } }
        }
        .sheet(item: $editing) { pipeline in
            PipelineEditor(pipeline: pipeline, maxDimension: settings[TraySettings.maxDimension]) { saved in
                save(saved)
            }
        }
    }

    // MARK: Sections

    private var storage: some View {
        Section {
            Picker(selection: settings.binding(TraySettings.storageMode)) {
                Text("Copies", bundle: .module, comment: "Settings ▸ Tray: keep dropped files as copies (default)").tag(TrayStorageMode.copy)
                Text("Links to the originals", bundle: .module, comment: "Settings ▸ Tray: keep dropped files as links").tag(TrayStorageMode.link)
            } label: {
                SettingLabel(settings: settings, key: TraySettings.storageMode,
                             title: String(localized: "Keep dropped files as", bundle: .module, comment: "Settings ▸ Tray: row label"),
                             note: String(localized: "Copies stay even if the original is moved or deleted. Links take no space; screenshots and other temporary files are always copied.",
                                          bundle: .module, comment: "Settings ▸ Tray: footnote under Keep dropped files as"))
            }
            Picker(selection: settings.binding(TraySettings.retention)) {
                Text("Until I remove them", bundle: .module, comment: "Settings ▸ Tray ▸ Remove items: never automatically (default)").tag(TrayRetention.untilRemoved)
                Text("When Cranny quits", bundle: .module, comment: "Settings ▸ Tray ▸ Remove items: clear on quit").tag(TrayRetention.clearOnQuit)
                Text("After one day", bundle: .module, comment: "Settings ▸ Tray ▸ Remove items: 24 hours after each was added").tag(TrayRetention.afterOneDay)
            } label: {
                SettingLabel(settings: settings, key: TraySettings.retention,
                             title: String(localized: "Remove items", bundle: .module, comment: "Settings ▸ Tray: row label (retention)"))
            }
            Picker(selection: settings.binding(TraySettings.maxItems)) {
                ForEach(TraySettings.maxItemsChoices, id: \.self) { count in
                    Text("\(count) items", bundle: .module, comment: "Settings ▸ Tray ▸ Keep at most: number of items").tag(count)
                }
            } label: {
                SettingLabel(settings: settings, key: TraySettings.maxItems,
                             title: String(localized: "Keep at most", bundle: .module, comment: "Settings ▸ Tray: row label (item cap)"),
                             note: String(localized: "The oldest items leave first.", bundle: .module, comment: "Settings ▸ Tray: footnote under Keep at most"))
            }
        } header: {
            Text("Storage", bundle: .module, comment: "Settings ▸ Tray: section header")
        }
    }

    private var dropping: some View {
        Section {
            Toggle(isOn: settings.binding(TraySettings.opensTrayOnDrop)) {
                SettingLabel(settings: settings, key: TraySettings.opensTrayOnDrop,
                             title: String(localized: "Show the Tray after dropping files", bundle: .module, comment: "Settings ▸ Tray: toggle"))
            }
            Toggle(isOn: settings.binding(TraySettings.showsAirDropZone)) {
                SettingLabel(settings: settings, key: TraySettings.showsAirDropZone,
                             title: String(localized: "AirDrop zone", bundle: .module, comment: "Settings ▸ Tray: toggle"),
                             note: String(localized: "While you drag files to the notch, and on the Tray page.", bundle: .module,
                                          comment: "Settings ▸ Tray: footnote under AirDrop zone"))
            }
        } header: {
            Text("Dropping", bundle: .module, comment: "Settings ▸ Tray: section header")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var pinned: some View {
        let all = BuiltinPipelines.pinnable + settings[TraySettings.userPipelines]
        let maxDimension = settings[TraySettings.maxDimension]
        return Section {
            ForEach(0..<TraySettings.maxPinnedPipelines, id: \.self) { slot in
                Picker(selection: pinnedBinding(slot)) {
                    Text("None", bundle: .module, comment: "Settings ▸ Tray ▸ pinned pipelines: empty slot").tag(String?.none)
                    Divider()
                    ForEach(all) { pipeline in
                        Label { Text(verbatim: PipelineTitles.title(pipeline, maxDimension: maxDimension)) } icon: {
                            Image(systemName: pipeline.isUserPipeline ? "wand.and.stars" : pipeline.symbol)
                        }
                        .tag(String?.some(pipeline.id))
                    }
                } label: {
                    SettingLabel(settings: settings, key: TraySettings.pinnedPipelines,
                                 title: String(localized: "Drop zone \(slot + 1)", bundle: .module, comment: "Settings ▸ Tray ▸ pinned pipelines: row label"))
                }
            }
        } header: {
            Text("Pinned pipelines", bundle: .module, comment: "Settings ▸ Tray: section header")
        } footer: {
            Text("While you drag files to the notch, pinned pipelines appear next to Keep in Tray and AirDrop. Drop files on one to run it.",
                 bundle: .module, comment: "Settings ▸ Tray: footnote under Pinned pipelines")
                .foregroundStyle(.secondary)
        }
    }

    private var userPipelines: some View {
        let pipelines = settings[TraySettings.userPipelines]
        let maxDimension = settings[TraySettings.maxDimension]
        return Section {
            ForEach(pipelines) { pipeline in
                HStack {
                    Label { Text(verbatim: PipelineTitles.title(pipeline, maxDimension: maxDimension)) } icon: { Image(systemName: "wand.and.stars") }
                    Spacer()
                    Text(verbatim: pipeline.steps.map { PipelineTitles.step($0, maxDimension: maxDimension) }.joined(separator: " → "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button { editing = pipeline } label: { Text("Edit…", bundle: .module, comment: "Settings ▸ Tray ▸ your pipelines: edit button") }
                }
                .contextMenu {
                    Button { editing = pipeline } label: { Text("Edit…", bundle: .module, comment: "Settings ▸ Tray ▸ your pipelines: edit button") }
                    Button(role: .destructive) { delete(pipeline) } label: {
                        Text("Delete", bundle: .module, comment: "Settings ▸ Tray ▸ your pipelines: delete a pipeline")
                    }
                }
            }
            Button {
                editing = .newUserPipeline(name: "")
            } label: {
                Text("New Pipeline…", bundle: .module, comment: "Settings ▸ Tray ▸ your pipelines: button that opens the editor")
            }
        } header: {
            Text("Your pipelines", bundle: .module, comment: "Settings ▸ Tray: section header")
        } footer: {
            Text("Chain steps into one action, for example Resize → Convert to JPEG → Copy paths. They appear as chips when they fit the selected files.",
                 bundle: .module, comment: "Settings ▸ Tray: footnote under Your pipelines")
                .foregroundStyle(.secondary)
        }
    }

    private var defaults: some View {
        Section {
            LabeledContent {
                HStack {
                    Slider(value: settings.binding(TraySettings.jpegQuality), in: 0.3...1, step: 0.05) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(verbatim: 0.3.formatted(.percent))
                    } maximumValueLabel: {
                        Text(verbatim: 1.0.formatted(.percent))
                    }
                    Text(verbatim: settings[TraySettings.jpegQuality].formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            } label: {
                SettingLabel(settings: settings, key: TraySettings.jpegQuality,
                             title: String(localized: "JPEG and HEIC quality", bundle: .module, comment: "Settings ▸ Tray: slider label"))
            }
            Picker(selection: settings.binding(TraySettings.maxDimension)) {
                ForEach(TraySettings.maxDimensionChoices, id: \.self) { pixels in
                    Text("\(String(pixels)) px", bundle: .module, comment: "Settings ▸ Tray ▸ Resize to: pixels on the longer side; the argument is a number of pixels").tag(pixels)
                }
            } label: {
                SettingLabel(settings: settings, key: TraySettings.maxDimension,
                             title: String(localized: "Resize to", bundle: .module, comment: "Settings ▸ Tray: row label (maximum dimension)"),
                             note: String(localized: "The longer side of images resized to the maximum.", bundle: .module, comment: "Settings ▸ Tray: footnote under Resize to"))
            }
            Picker(selection: settings.binding(TraySettings.outputLocation)) {
                Text("Next to the original", bundle: .module, comment: "Settings ▸ Tray ▸ Save results: next to the source file").tag(TrayOutputLocation.nextToSource)
                Text("Downloads", bundle: .module, comment: "Settings ▸ Tray ▸ Save results: the Downloads folder").tag(TrayOutputLocation.downloads)
            } label: {
                SettingLabel(settings: settings, key: TraySettings.outputLocation,
                             title: String(localized: "Save results", bundle: .module, comment: "Settings ▸ Tray: row label (output location)"),
                             note: String(localized: "Results of files the Tray keeps a copy of go to Downloads.", bundle: .module,
                                          comment: "Settings ▸ Tray: footnote under Save results"))
            }
            Picker(selection: settings.binding(TraySettings.zipNaming)) {
                Text("First item’s name (Brief.zip)", bundle: .module, comment: "Settings ▸ Tray ▸ Name zip archives: example uses an English file name").tag(TrayZipNaming.firstItem)
                Text(verbatim: datedExample).tag(TrayZipNaming.dated)
            } label: {
                SettingLabel(settings: settings, key: TraySettings.zipNaming,
                             title: String(localized: "Name zip archives", bundle: .module, comment: "Settings ▸ Tray: row label (zip naming)"))
            }
        } header: {
            Text("Defaults", bundle: .module, comment: "Settings ▸ Tray: section header")
        }
    }

    private var content: some View {
        Section {
            LabeledContent {
                Button(role: .destructive) { confirmsClear = true } label: {
                    Text("Clear Tray…", bundle: .module, comment: "Settings ▸ Tray: button that removes every item")
                }
                .disabled(store.items.isEmpty)
                .confirmationDialog(Text("Remove every item from the Tray?", bundle: .module, comment: "Settings ▸ Tray: Clear confirmation"),
                                    isPresented: $confirmsClear) {
                    Button(role: .destructive, action: store.clear) {
                        Text("Clear Tray", bundle: .module, comment: "Settings ▸ Tray and command palette: remove every item from the Tray (confirmation button, command)")
                    }
                } message: {
                    Text("Copies kept by the Tray are deleted. Your own files are not touched.", bundle: .module,
                         comment: "Settings ▸ Tray: Clear confirmation message")
                }
            } label: {
                Text(verbatim: String(localized: "\(store.items.count) items · \(store.totalSize.formatted(.byteCount(style: .file)))",
                                      bundle: .module, comment: "Tray chip row with nothing selected: number of items and their total size"))
            }
        }
    }

    // MARK: Helpers

    private var datedExample: String {
        let base = OutputNaming.localized.zipBaseName(firstItem: "", naming: .dated, date: Date())
        return String(localized: "Date (\(base).zip)", bundle: .module, comment: "Settings ▸ Tray ▸ Name zip archives: dated option; the argument is an example name")
    }

    private func pinnedBinding(_ slot: Int) -> Binding<String?> {
        Binding {
            PinnedPipelineSlots.id(in: settings[TraySettings.pinnedPipelines], slot: slot)
        } set: { newValue in
            settings[TraySettings.pinnedPipelines] = PinnedPipelineSlots.setting(newValue, slot: slot,
                                                                                 in: settings[TraySettings.pinnedPipelines])
        }
    }

    private func save(_ pipeline: PipelineDefinition) {
        var pipelines = settings[TraySettings.userPipelines]
        if let i = pipelines.firstIndex(where: { $0.id == pipeline.id }) { pipelines[i] = pipeline } else { pipelines.append(pipeline) }
        settings[TraySettings.userPipelines] = pipelines
    }

    private func delete(_ pipeline: PipelineDefinition) {
        settings[TraySettings.userPipelines] = settings[TraySettings.userPipelines].filter { $0.id != pipeline.id }
        settings[TraySettings.pinnedPipelines] = PinnedPipelineSlots.removing(pipeline.id, from: settings[TraySettings.pinnedPipelines])
    }
}

/// A row label with the changed-value dot, an optional footnote and "Reset to Default" (DESIGN.md §11.3).
struct SettingLabel<Value: Codable & Sendable & Equatable>: View {
    let settings: SettingsStore
    let key: SettingKey<Value>
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .opacity(settings.isDefault(key) ? 0 : 1)
                    .accessibilityHidden(true)
                Text(verbatim: title)
            }
            if let note {
                Text(verbatim: note).font(.footnote).foregroundStyle(.secondary).padding(.leading, 12)
            }
        }
        .contextMenu {
            Button { settings.reset(key) } label: {
                Text("Reset to Default", bundle: .module, comment: "Settings ▸ Tray: row context menu")
            }
            .disabled(settings.isDefault(key))
        }
        .accessibilityValue(settings.isDefault(key) ? Text(verbatim: "")
                            : Text("Changed", bundle: .module, comment: "Settings ▸ Tray: VoiceOver value of a row whose value is not the default"))
    }
}

#Preview("Settings ▸ Tray") {
    TraySettingsPane(store: TrayPreview.store(items: 3))
        .frame(width: 620, height: 900)
}
