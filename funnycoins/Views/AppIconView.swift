import SwiftUI

/// Arte do ícone do app: o bichinho Filhote sobre um fundo dourado, com uma moeda de real.
/// É a fonte do arquivo em Assets.xcassets/AppIcon. Se mudar aqui, gere o PNG de novo.
/// O fundo é quadrado e sem cantos arredondados, porque o sistema aplica a máscara do ícone.
struct AppIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            // Fundo dourado, lembrando moeda e conquista
            LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.35),
                                    Color(red: 0.98, green: 0.6, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Luz suave atrás do bichinho
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.84, height: size * 0.84)
                .offset(y: size * 0.04)

            // Faíscas
            sparkle(x: -0.3, y: -0.28, scale: 1)
            sparkle(x: 0.33, y: 0.2, scale: 0.7)
            sparkle(x: -0.34, y: 0.16, scale: 0.55)

            // Moeda de real flutuando
            coin
                .offset(x: size * 0.24, y: -size * 0.25)

            PetView(stage: .baby, mood: .happy, color: .green, size: size * 0.78, isAnimated: false)
                .offset(y: size * 0.05)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var coin: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.55),
                                              Color(red: 0.93, green: 0.68, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(Color(red: 0.8, green: 0.52, blue: 0.05), lineWidth: size * 0.014)
            Text("R$")
                .font(.system(size: size * 0.085, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 0.44, blue: 0.0))
        }
        .frame(width: size * 0.2, height: size * 0.2)
        .rotationEffect(.degrees(12))
        .shadow(color: .black.opacity(0.15), radius: size * 0.01, y: size * 0.008)
    }

    private func sparkle(x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.08 * scale))
            .foregroundStyle(.white.opacity(0.9))
            .offset(x: size * x, y: size * y)
    }
}

#Preview("Ícone") {
    AppIconView(size: 512)
        .clipShape(.rect(cornerRadius: 512 * 0.22, style: .continuous))
        .padding()
}
