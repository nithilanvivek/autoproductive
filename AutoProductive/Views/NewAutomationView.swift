import SwiftUI

struct NewAutomationView: View {
    let openAppAction: () -> Void
    let composeMailAction: () -> Void
    let workflowAction: (AutomationKind) -> Void

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                Text("Create New Automation")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.8)

                Text("Choose what should happen when your automation runs.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 7)
                    .padding(.bottom, 32)

                VStack(spacing: 20) {
                    AutomationTypeCard(kind: .sequence, color: AppPalette.blue) { workflowAction(.sequence) }
                    AutomationTypeCard(kind: .keyRemap, color: AppPalette.indigo) { workflowAction(.keyRemap) }
                }

            }
            .frame(maxWidth: 760)
            .padding(.top, 44)
            .padding(.horizontal, 48)
            .padding(.bottom, 44)
            }
        }
        .navigationTitle("New Automation")
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

private struct AutomationTypeCard: View {
    let kind: AutomationKind
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                SymbolTile(symbol: kind.symbol, color: color, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(kind.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .glassCard()
            .scaleEffect(isHovering ? 1.018 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
