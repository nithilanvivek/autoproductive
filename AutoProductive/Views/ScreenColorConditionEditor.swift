import AppKit
import SwiftUI

struct ScreenColorConditionEditor: View {
    @Binding var step: WorkflowStep
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Look for color in", selection: Binding(
                get: { step.colorRegions != nil },
                set: { step.colorRegions = $0 ? (step.colorRegions ?? []) : nil }
            )) {
                Text("One pixel").tag(false)
                Text("Screen rectangles").tag(true)
            }.pickerStyle(.segmented)
            if let regions = step.colorRegions {
                ForEach(regions.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rectangle \(index + 1)").font(.caption.weight(.semibold))
                            HStack { regionField("X", index: index, key: \.x); regionField("Y", index: index, key: \.y) }
                            HStack { regionField("Width", index: index, key: \.width); regionField("Height", index: index, key: \.height) }
                        }
                        Button { step.colorRegions?.remove(at: index) } label: { Image(systemName: "trash") }
                            .help("Remove rectangle \(index + 1)")
                            .accessibilityLabel("Remove rectangle \(index + 1)")
                    }
                }
                Button("Select Rectangle on Screen…", systemImage: "rectangle.dashed") { selectRectangle() }
                    .disabled(regions.count >= 32)
                if regions.isEmpty { Text("Select at least one rectangle.").font(.caption).foregroundStyle(.red) }
                if regions.count > 1 {
                    Picker("Color must appear in", selection: Binding(
                        get: { step.colorInEveryRegion == true }, set: { step.colorInEveryRegion = $0 }
                    )) {
                        Text("Any selected rectangle").tag(false)
                        Text("Every selected rectangle").tag(true)
                    }
                }
                Text("Matches when at least one pixel inside the chosen area has this color. Add more rectangles to watch separate areas.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { number("X", value: $step.x); number("Y", value: $step.y) }
                Button("Select Pixel on Screen…", systemImage: "scope") {
                    select(mode: .pixel) { region in step.x = region.x; step.y = region.y }
                }
                Text("Coordinates are screen points from the top-left of the primary display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let selectionError { Text(selectionError).font(.caption).foregroundStyle(.red) }
            ViewThatFits(in: .horizontal) {
                HStack { colorField; selectColorButton }
                VStack(alignment: .leading, spacing: 8) { colorField; selectColorButton }
            }
            number("Color tolerance (0–255)", value: $step.amount)
            Text("Colors are compared in sRGB from the screen capture, without normal display-temperature tinting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { ScreenRegionPicker.shared.cancel() }
    }

    private var colorField: some View {
        TextField("#RRGGBB", text: $step.text).textFieldStyle(.roundedBorder)
            .frame(minWidth: 100)
            .accessibilityLabel("Screen color hex value")
    }

    private var selectColorButton: some View {
        Button("Select Color…", systemImage: "eyedropper") {
            selectionError = nil
            do {
                try ScreenColorSampler.shared.select { color in
                    step.text = String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
                }
            } catch { DiagnosticJournal.shared.recordError("ScreenColorConditionEditor", error); selectionError = error.localizedDescription }
        }
        .fixedSize()
        .help("Move the magnifier anywhere on screen, then click a color. Press Esc to cancel.")
    }

    private func number(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title).font(.caption); TextField(title, value: value, format: .number).textFieldStyle(.roundedBorder) }
    }
    private func regionField(_ title: String, index: Int, key: WritableKeyPath<ScreenColorRegion, Double>) -> some View {
        number(title, value: Binding(get: {
            guard let regions = step.colorRegions, regions.indices.contains(index) else { return 0 }
            return regions[index][keyPath: key]
        }, set: { value in
            guard step.colorRegions?.indices.contains(index) == true else { return }
            step.colorRegions?[index][keyPath: key] = value
        }))
    }
    private func selectRectangle() {
        select(mode: .rectangle) { region in
            guard var regions = step.colorRegions, regions.count < 32 else { return }
            regions.append(region); step.colorRegions = regions
        }
    }
    private func select(mode: ScreenRegionPicker.Mode, completion: @escaping (ScreenColorRegion) -> Void) {
        selectionError = nil
        do { try ScreenRegionPicker.shared.select(mode: mode, completion: completion) }
        catch { DiagnosticJournal.shared.recordError("ScreenColorConditionEditor", error); selectionError = error.localizedDescription }
    }
}

/// Allows a partial edit, but normalizes to the supported range on Return or
/// focus loss. Invalid drafts cannot pass WorkflowDefinition.validate().
struct TriggerIntervalField: View {
    let title: String
    @Binding var seconds: Double
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                TextField("Seconds", text: $draft).frame(width: 100)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityLabel(title + " seconds")
                    .onSubmit { normalize() }
                Text("seconds")
            }
            Text("Minimum 0.5 seconds · Maximum 86,400 seconds (one day)")
                .font(.caption).foregroundStyle(WorkflowTiming.isValid(seconds) ? Color.secondary : Color.red)
        }
        .onAppear { draft = seconds.formatted(.number.grouping(.never)) }
        .onChange(of: draft) { _, value in
            if focused { seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan }
        }
        .onChange(of: focused) { _, value in if !value { normalize() } }
        .onChange(of: seconds) { _, value in
            if !focused { draft = value.formatted(.number.grouping(.never)) }
        }
    }

    private func normalize() {
        seconds = WorkflowTiming.clamped(Double(draft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan)
        draft = seconds.formatted(.number.grouping(.never))
    }
}
