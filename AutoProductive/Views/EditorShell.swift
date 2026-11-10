import SwiftUI

struct EditorShell<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.color = color
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 18) {
                            SymbolTile(symbol: symbol, color: color, size: 64)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(title)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                Text(subtitle)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        content
                            .padding(24)
                            .glassCard()
                    }
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 44)
                    .padding(.top, 52)
                    .padding(.bottom, 28)
                }

                Divider()
                footer
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 16)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}
