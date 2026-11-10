import SwiftUI

enum AppPalette {
    static let blue = Color(red: 0.08, green: 0.43, blue: 0.98)
    static let indigo = Color(red: 0.39, green: 0.28, blue: 0.94)
    static let mint = Color(red: 0.18, green: 0.78, blue: 0.65)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    AppPalette.blue.opacity(0.12),
                    AppPalette.indigo.opacity(0.07),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppPalette.blue.opacity(0.09))
                .frame(width: 460, height: 460)
                .blur(radius: 40)
                .offset(x: 390, y: -280)

            Circle()
                .fill(AppPalette.indigo.opacity(0.07))
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(x: -420, y: 320)
        }
        .ignoresSafeArea()
    }
}

struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 54

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.82), color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            )
            .shadow(color: color.opacity(0.3), radius: 12, y: 6)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 42)
            .background(AppPalette.blue.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func glassCard() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}
