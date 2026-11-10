import SwiftUI

struct WorkflowVariableHelp: View {
    @Binding var dateUTCOffset: String?
    private let values = [
        ("{{input}}", "The text entered in the most recent Ask for text action."),
        ("{{choice}}", "The option selected in the most recent Show a choice menu action."),
        ("{{file}}", "The text contents loaded by the most recent Read a text file action."),
        ("{{output}}", "The output from the most recent Run a shell command or Run AppleScript action."),
        ("{{clipboard}}", "The text currently copied to your clipboard when this action runs."),
        ("{{date}}", "The date this automation started, in DD/MM/YYYY format."),
        ("{{time}}", "The time this automation started, in 12-hour AM/PM format.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use values in your actions").font(.subheadline.weight(.semibold))
            Text("Type a placeholder exactly as shown into an action’s text or file-path field. AutoProductive replaces it with its value when the action runs.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(values, id: \.0) { placeholder, explanation in
                    GridRow(alignment: .top) {
                        Text(placeholder).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary).fixedSize()
                        Text(explanation).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Text("Time coordinate: UTC")
                Picker("UTC offset direction", selection: Binding(
                    get: { (dateUTCOffset ?? "+00:00").hasPrefix("-") ? "-" : "+" },
                    set: { dateUTCOffset = $0 + String((dateUTCOffset ?? "+00:00").dropFirst()) }
                )) { Text("+").tag("+"); Text("−").tag("-") }
                .labelsHidden().frame(width: 65)
                TextField("00:00", text: Binding(
                    get: { String((dateUTCOffset ?? "+00:00").dropFirst()) },
                    set: { dateUTCOffset = ((dateUTCOffset ?? "+00:00").hasPrefix("-") ? "-" : "+") + $0 }
                )).textFieldStyle(.roundedBorder).frame(width: 70)
                if WorkflowText.utcOffsetSeconds(dateUTCOffset) == nil {
                    Text("Use HH:MM, up to 14:00.").foregroundStyle(.red)
                }
            }
            Text("Put the action that supplies a value before the action that uses it. If no value has been supplied yet, that placeholder stays as typed. Clipboard, date and time are available without an earlier action.")
            Text("Example: Ask for text collects “Nithilan”. A later Type text action containing “Hello {{input}}!” types “Hello Nithilan!”.")
            DisclosureGroup("Using these values in scripts") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scripts receive values as environment variables instead of {{…}} placeholders. Use the same names in capitals after AUTOPRODUCTIVE_, such as AUTOPRODUCTIVE_INPUT or AUTOPRODUCTIVE_FILE.")
                    Text("Shell example: printf '%s' \"$AUTOPRODUCTIVE_INPUT\"")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("AppleScript example: do shell script \"printf '%s' \\\"$AUTOPRODUCTIVE_INPUT\\\"\" without altering line endings")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("This AppleScript form preserves accents, symbols and line breaks in the value.")
                }.padding(.top, 6)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
