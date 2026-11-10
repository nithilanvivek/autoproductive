import SwiftUI

struct ProblemReportView: View {
    @ObservedObject var model: ProblemReportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.report.kind == "crash" ? "AutoProductive quit unexpectedly" : "Report a Bug or Give Feedback", systemImage: "exclamationmark.bubble")
                .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            if model.sent {
                Label("Report sent. Thank you.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Report ID: \(model.report.id)").font(.caption).textSelection(.enabled)
                Spacer()
                HStack { Spacer(); Button("Done", action: model.close).keyboardShortcut(.defaultAction) }
            } else {
                Text(model.report.kind == "crash" ? "Send this report to the developer, Nithilan Vivek, to help investigate the crash." : "Send a bug report or feedback to the developer, Nithilan Vivek.")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.report.kind == "crash" ? "What happened? (optional)" : "Describe the bug or share your feedback (optional)").font(.headline)
                        TextEditor(text: $model.details).frame(minHeight: 100, maxHeight: 180)
                            .accessibilityLabel("Problem description").border(.secondary.opacity(0.3))
                        Toggle("Include crash details and diagnostic logs", isOn: $model.includeDiagnostics)
                        Text("Includes the app/macOS version, crash stack and recent app events. It excludes your saved automations, clipboard, typed text, file contents and screenshots. Nothing is sent until you click Send.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Report Details") {
                            Text(model.preview).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if model.loading { ProgressView("Preparing report…") }
                        if let error = model.error { Text(error).foregroundStyle(.red).font(.callout) }
                    }
                }.disabled(model.sending)
                HStack {
                    Button(model.report.kind == "crash" ? "Don’t Send" : "Cancel", action: model.close)
                        .keyboardShortcut(.cancelAction).disabled(model.sending)
                    Spacer()
                    if model.sending { ProgressView().controlSize(.small) }
                    Button(model.sending ? "Sending…" : model.report.kind == "crash" ? "Send Crash Report to Developer" : "Send Report to Developer", action: model.send)
                        .buttonStyle(.borderedProminent).disabled(model.loading || model.sending)
                }
            }
        }.padding(24).frame(minWidth: 400, minHeight: 320)
    }
}
