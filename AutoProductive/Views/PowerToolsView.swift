import SwiftUI

struct PowerToolsView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeometryReader { geometry in
            let width = min(760, max(0, geometry.size.width - 32))
            let height = max(0, geometry.size.height - 24)
            ZStack {
                AppBackground()
                MenuBarView(popupSize: NSSize(width: width, height: height),
                            maximumHeight: height,
                            openMainWindow: { openWindow(id: "main") },
                            contentHeightChanged: { _ in }, isPowerTools: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Power Tools")
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}
