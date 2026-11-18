import SwiftUI

/// Anel de progresso animado usado nos níveis.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 12
    var tint: Color = .green
    var font: Font = .headline

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(font.monospacedDigit())
        }
    }
}

/// Fundo padrão dos cartões da jornada.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Tamanho mínimo para sheets no macOS, que abrem pequenas por padrão.
    func sheetFrame() -> some View {
        #if os(macOS)
        frame(minWidth: 420, minHeight: 480)
        #else
        self
        #endif
    }

    /// Teclado numérico no iOS.
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

/// Campo de valor em reais.
struct CurrencyField: View {
    let title: String
    @Binding var value: Decimal

    var body: some View {
        TextField(title, value: $value, format: BRFormat.currency)
            .decimalKeyboard()
    }
}
