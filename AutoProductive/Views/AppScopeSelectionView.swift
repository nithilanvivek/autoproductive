import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppScopeSelectionView: View {
    @Binding var identifiers: [String]
    var emptyLabel = "All apps (default)"
    var allowsAllApps = true
    @State private var newIdentifier = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if identifiers.isEmpty {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(identifiers, id: \.self) { identifier in
                    HStack {
                        Text(identifier).textSelection(.enabled)
                        Spacer()
                        Button {
                            identifiers.removeAll { $0 == identifier }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .accessibilityLabel("Remove \(identifier)")
                    }
                }
            }
            HStack {
                TextField("Bundle identifier", text: $newIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addIdentifier)
                Button("Add", action: addIdentifier)
                    .disabled(newIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Choose Apps…", action: chooseApplications)
            }
            if allowsAllApps && !identifiers.isEmpty {
                Button("Use all apps") { identifiers = [] }
                    .font(.caption)
            }
        }
    }

    private func addIdentifier() {
        identifiers = AppScope.normalized(identifiers + [newIdentifier])
        newIdentifier = ""
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            identifiers = AppScope.normalized(identifiers + panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }
}
