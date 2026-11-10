import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileBucketView: View {
    @ObservedObject private var bucket = FileBucket.shared
    @ObservedObject private var shortcuts = FileBucketShortcuts.shared
    @State private var showOptions = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Bucket").font(.largeTitle.bold())
                        Text("Drag files or folders to a screen edge or drop them here. AutoProductive stores a local copy.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Files or Folders…", action: chooseFiles)
                }
                if bucket.items.isEmpty {
                    ContentUnavailableView {
                        Label { Text("File Bucket is empty") } icon: { BucketIcon().frame(width: 48, height: 48) }
                    } description: { Text("Drag files to an edge or drop them here.") }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(bucket.items, id: \.self) { url in
                                VStack(alignment: .leading, spacing: 8) {
                                  HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data))
                                        .resizable().frame(width: 32, height: 32)
                                    Text(url.lastPathComponent).lineLimit(2).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                  }
                                  HStack {
                                    Button("Open") { NSWorkspace.shared.open(url) }
                                    Button("Show in Finder") { FileBucketFinderReveal.reveal(url, bucket: bucket) }
                                    Button("Remove") { bucket.remove(url) }
                                        .help(bucket.permanentlyDeleteOnRemove ? "Permanently delete this File Bucket copy" : "Move this File Bucket copy to Trash")
                                    Spacer(minLength: 0)
                                  }.controlSize(.small)
                                }
                                .padding(10)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("file-bucket-items")
                }
                DisclosureGroup("Options", isExpanded: $showOptions) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Accept file drops at screen edges", isOn: Binding(
                                get: { bucket.edgeDropEnabled }, set: { bucket.setEdgeDropEnabled($0) }))
                                .toggleStyle(.checkbox)
                            Toggle("Permanently delete files when removed", isOn: Binding(
                                get: { bucket.permanentlyDeleteOnRemove }, set: { bucket.setPermanentlyDeleteOnRemove($0) }))
                                .toggleStyle(.checkbox)
                                .help("Permanently deletes File Bucket’s stored copies instead of moving them to Trash.")
                            shortcutSetting("Open/Close File Bucket", enabled: \.openEnabled, key: \.open)
                            shortcutSetting("Add a File or Folder to File Bucket", enabled: \.addEnabled, key: \.add)
                        }.padding(.top, 8)
                    }.frame(maxHeight: 190)
                }
                if let error = shortcuts.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
                if let error = bucket.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .padding(24)
        }
        .frame(minWidth: 280, minHeight: 240)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: NSURL.self) {
                    _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                        if let url = item as? URL, url.isFileURL { Task { @MainActor in bucket.importURLs([url]) } }
                    }
                } else {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        if let url = FileBucket.fileURL(from: data) { Task { @MainActor in bucket.importURLs([url]) } }
                    }
                }
            }
            return !providers.isEmpty
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in bucket.importURLs(panel.urls) }
        }
    }

    private func shortcutSetting(_ title: String, enabled: WritableKeyPath<FileBucketShortcutSettings, Bool>,
                                 key: WritableKeyPath<FileBucketShortcutSettings, KeyboardShortcutDefinition?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(get: { shortcuts.settings[keyPath: enabled] }, set: { value in
                var settings = shortcuts.settings; settings[keyPath: enabled] = value; shortcuts.update(settings)
            })).toggleStyle(.checkbox)
            if key == \.add {
                Text("Select a file(s) or a folder(s) in Finder and type this shortcut to copy them to the File Bucket")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KeyboardShortcutRecorder(shortcut: Binding(get: { shortcuts.settings[keyPath: key] }, set: { value in
                var settings = shortcuts.settings; settings[keyPath: key] = value; shortcuts.update(settings)
            }), existingShortcuts: AutomationStore.loadStoredAutomations().compactMap(\.keyboardShortcut) +
                [key == \.open ? shortcuts.settings.add : shortcuts.settings.open].compactMap { $0 }, compact: true)
                .disabled(!shortcuts.settings[keyPath: enabled])
        }
    }
}

struct BucketIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.16, y: h * 0.32))
                path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.9))
                path.addQuadCurve(to: CGPoint(x: w * 0.73, y: h * 0.9), control: CGPoint(x: w * 0.5, y: h))
                path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.32))
                path.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.25, width: w * 0.68, height: h * 0.15))
                path.move(to: CGPoint(x: w * 0.25, y: h * 0.3))
                path.addCurve(to: CGPoint(x: w * 0.75, y: h * 0.3), control1: CGPoint(x: w * 0.25, y: -h * 0.02), control2: CGPoint(x: w * 0.75, y: -h * 0.02))
            }.stroke(style: StrokeStyle(lineWidth: max(1.3, w * 0.055), lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
