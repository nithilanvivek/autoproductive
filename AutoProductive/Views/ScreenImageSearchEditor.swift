import AppKit
import SwiftUI

struct ScreenImageSearchEditor: View {
    @Binding var step: WorkflowStep
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Search for image in", selection: Binding(
                get: { step.imageSearchScope ?? .entireScreen },
                set: { step.imageSearchScope = $0 }
            )) {
                Text("Entire Screen").tag(ImageSearchScope.entireScreen)
                Text("Screen Rectangles").tag(ImageSearchScope.rectangles)
            }.pickerStyle(.segmented)
            Toggle("Match resized images", isOn: Binding(get: { step.matchResizedImages ?? true }, set: { step.matchResizedImages = $0 }))
            if step.imageSearchScope == .rectangles {
                ForEach(Array((step.imageRegions ?? []).enumerated()), id: \.offset) { index, region in
                    HStack {
                        Text("Rectangle \(index + 1): \(region.x.formatted()), \(region.y.formatted()) · \(region.width.formatted()) × \(region.height.formatted()) points")
                            .font(.caption).monospacedDigit()
                        Spacer()
                        Button { step.imageRegions?.remove(at: index) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove image search rectangle \(index + 1)")
                    }
                }
                Button("Select Rectangle on Screen…", systemImage: "rectangle.dashed") {
                    error = nil
                    do {
                        try ScreenRegionPicker.shared.select(mode: .rectangle) { region in
                            var regions = step.imageRegions ?? []
                            if regions.count < 32 { regions.append(region); step.imageRegions = regions }
                        }
                    } catch { DiagnosticJournal.shared.recordError("ScreenImageSearchEditor", error); self.error = error.localizedDescription }
                }.disabled((step.imageRegions?.count ?? 0) >= 32)
                if (step.imageRegions ?? []).isEmpty { Text("Select at least one rectangle.").font(.caption).foregroundStyle(.red) }
                Text("Searches inside any selected rectangle. The complete reference image must fit inside the area.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Searches the full screen on each connected display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(step.matchResizedImages == false ? "Requires the reference image’s original pixel size." : "Recognizes the complete image displayed at 10–200% of its original size, keeping its proportions.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { migrateLegacyArea() }
        .onDisappear { ScreenRegionPicker.shared.cancel() }
    }

    private func migrateLegacyArea() {
        guard step.imageSearchScope == nil else { return }
        // Preserve fixed-position and single-display legacy searches as an
        // equivalent rectangle in the editing draft, without changing saved data.
        let point = CGPoint(x: step.x, y: step.y)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success,
              let display = displays.first(where: { CGDisplayBounds($0).contains(point) }) else { return }
        let frame = CGDisplayBounds(display)
        let region: ScreenColorRegion
        if step.option == "search" {
            region = ScreenColorRegion(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        } else if let image = try? ScreenReferenceImage.load(step.text) {
            region = ScreenColorRegion(x: step.x, y: step.y,
                                       width: Double(image.width) * frame.width / Double(CGDisplayPixelsWide(display)),
                                       height: Double(image.height) * frame.height / Double(CGDisplayPixelsHigh(display)))
        } else { return }
        step.imageRegions = [region]; step.imageSearchScope = .rectangles
    }
}
