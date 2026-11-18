import SwiftUI

extension PetColor {
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .orange: .orange
        case .purple: .purple
        }
    }
}

/// O bichinho desenhado em SwiftUI. Muda de rosto com o humor e de forma com a evolução.
struct PetView: View {
    let stage: PetStage
    let mood: PetMood
    let color: Color
    var size: CGFloat = 200
    /// Desligue em tamanhos pequenos para economizar animações.
    var isAnimated = true

    var body: some View {
        Group {
            if stage == .egg {
                egg
            } else {
                creature
                    .scaleEffect(stage.scale, anchor: .bottom)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Bichinho \(stage.title), \(mood.title)")
    }

    // MARK: Ovo

    private var egg: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.12))
                .frame(width: size * 0.5, height: size * 0.08)
                .offset(y: size * 0.4)

            EggShell(color: color, size: size, isAnimated: isAnimated)
        }
    }

    // MARK: Criatura

    /// Forma do estágio atual. O fallback é a forma do Filhote.
    private var look: PetAppearance {
        stage.appearance ?? PetAppearance(bodyWidth: 0.78, bodyHeight: 0.7, cornerRatio: 0.36)
    }

    private var creature: some View {
        ZStack {
            if look.hasAura {
                PetAura(size: size, isAnimated: isAnimated)
            }

            // Sombra no chão
            Ellipse()
                .fill(.black.opacity(0.12))
                .frame(width: size * 0.6, height: size * 0.08)
                .offset(y: size * 0.42)

            VStack(spacing: -size * 0.06) {
                accessory
                    .zIndex(1)
                bodyShape
            }
            .phaseAnimator(isAnimated ? [false, true] : [false]) { content, up in
                content
                    .offset(y: up ? -size * 0.03 : 0)
                    .scaleEffect(x: up ? 0.98 : 1.02, y: up ? 1.02 : 0.98, anchor: .bottom)
            } animation: { _ in .easeInOut(duration: 1.2) }
        }
    }

    private var bodyColor: Color {
        mood == .sick ? color.mix(with: .gray, by: 0.45) : color
    }

    private var bodyShape: some View {
        let width = look.bodyWidth
        let height = look.bodyHeight
        // Corpos mais altos que o do Filhote (0.7) descem a barriga e o rosto proporcionalmente.
        let extraHeight = height - 0.7

        return ZStack {
            // Partes de trás do corpo
            if look.hasWings { wings(bodyWidth: width) }
            if look.ears != .none { ears(bodyWidth: width, bodyHeight: height) }
            if look.hasTail { tail(bodyWidth: width, bodyHeight: height) }
            if look.hasArms { arms(bodyWidth: width) }

            // Pezinhos
            HStack(spacing: size * 0.22) {
                Ellipse().fill(bodyColor.mix(with: .black, by: 0.2))
                Ellipse().fill(bodyColor.mix(with: .black, by: 0.2))
            }
            .frame(width: size * 0.5, height: size * 0.1)
            .offset(y: size * (height / 2 - 0.03))

            // Corpo
            RoundedRectangle(cornerRadius: size * look.cornerRatio, style: .continuous)
                .fill(LinearGradient(colors: [bodyColor.mix(with: .white, by: 0.35), bodyColor],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * width, height: size * height)

            // Barriguinha, com emblema nas formas evoluídas
            Ellipse()
                .fill(.white.opacity(0.35))
                .frame(width: size * 0.4, height: size * 0.26)
                .overlay { bellyEmblem.offset(y: size * 0.02) }
                .offset(y: size * (0.16 + extraHeight * 0.5))

            face
                .offset(y: -size * (0.06 - extraHeight * 0.3))
        }
        .frame(width: size * (width + 0.02), height: size * (height + 0.04))
    }

    // MARK: Partes que surgem com a evolução

    private func ears(bodyWidth: CGFloat, bodyHeight: CGFloat) -> some View {
        let earHeight: CGFloat = look.ears == .long ? 0.3 : 0.2
        return ForEach([CGFloat(-1), 1], id: \.self) { side in
            EarShape()
                .fill(bodyColor.mix(with: .white, by: 0.2))
                .overlay {
                    EarShape()
                        .fill(.pink.opacity(0.4))
                        .scaleEffect(0.55, anchor: .bottom)
                }
                .frame(width: size * 0.17, height: size * earHeight)
                .rotationEffect(.degrees(side * 18), anchor: .bottom)
                .offset(x: side * size * bodyWidth * 0.27,
                        y: -size * (bodyHeight / 2 + earHeight / 2 - 0.08))
        }
    }

    private func arms(bodyWidth: CGFloat) -> some View {
        let armColor = bodyColor.mix(with: .black, by: 0.08)
        return ZStack {
            // Braço esquerdo parado
            Capsule()
                .fill(armColor)
                .frame(width: size * 0.1, height: size * 0.2)
                .rotationEffect(.degrees(30), anchor: .top)
                .offset(x: -size * bodyWidth / 2, y: size * 0.06)

            // Braço direito acenando
            Capsule()
                .fill(armColor)
                .frame(width: size * 0.1, height: size * 0.2)
                .phaseAnimator(isAnimated ? [false, true] : [false]) { content, raised in
                    content.rotationEffect(.degrees(raised ? -140 : -30), anchor: .top)
                } animation: { raised in
                    raised ? .easeInOut(duration: 0.4).delay(2) : .easeInOut(duration: 0.4)
                }
                .offset(x: size * bodyWidth / 2, y: size * 0.06)
        }
    }

    private func tail(bodyWidth: CGFloat, bodyHeight: CGFloat) -> some View {
        TailShape()
            .stroke(bodyColor.mix(with: .black, by: 0.1),
                    style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
            .frame(width: size * 0.22, height: size * 0.22)
            .offset(x: size * (bodyWidth / 2 + 0.02), y: size * (bodyHeight / 2 - 0.16))
    }

    private func wings(bodyWidth: CGFloat) -> some View {
        ForEach([CGFloat(-1), 1], id: \.self) { side in
            WingShape()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.75), color.mix(with: .white, by: 0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay { WingShape().stroke(color.mix(with: .black, by: 0.15), lineWidth: size * 0.012) }
                .frame(width: size * 0.32, height: size * 0.32)
                // A asa da direita é o espelho da esquerda
                .scaleEffect(x: side, y: 1)
                .phaseAnimator(isAnimated ? [false, true] : [false]) { content, up in
                    content.rotationEffect(.degrees(up ? side * 12 : 0),
                                           anchor: side < 0 ? .trailing : .leading)
                } animation: { _ in .easeInOut(duration: 0.6) }
                .offset(x: side * size * (bodyWidth / 2 + 0.08), y: -size * 0.12)
        }
    }

    @ViewBuilder
    private var bellyEmblem: some View {
        if let emblem = look.bellyEmblem {
            Image(systemName: emblem)
                .font(.system(size: size * 0.11, weight: .bold))
                .foregroundStyle(look.hasAura
                                 ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(bodyColor.mix(with: .black, by: 0.25)))
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
    }

    private var face: some View {
        VStack(spacing: size * 0.05) {
            HStack(spacing: size * 0.2) {
                eye
                eye
            }
            ZStack {
                if mood == .happy {
                    HStack(spacing: size * 0.36) {
                        Circle().fill(.pink.opacity(0.5))
                        Circle().fill(.pink.opacity(0.5))
                    }
                    .frame(width: size * 0.5, height: size * 0.07)
                }
                mouth
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        if mood == .sick {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.08, weight: .black))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: size * 0.09, height: size * 0.12)
        } else {
            Capsule()
                .fill(.black.opacity(0.8))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white)
                        .frame(width: size * 0.03)
                        .offset(x: -size * 0.01, y: size * 0.015)
                }
                .frame(width: size * 0.08, height: mood == .sad ? size * 0.09 : size * 0.12)
                .phaseAnimator(isAnimated ? [false, true] : [false]) { content, closed in
                    content.scaleEffect(y: closed ? 0.1 : 1)
                } animation: { closed in
                    // Fecha depois de alguns segundos e abre rápido: uma piscada.
                    closed ? .easeIn(duration: 0.08).delay(2.8) : .easeOut(duration: 0.1)
                }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        if mood == .hungry {
            Ellipse()
                .fill(.black.opacity(0.75))
                .frame(width: size * 0.09, height: size * 0.1)
        } else {
            MouthShape(curve: mood.mouthCurve)
                .stroke(.black.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.025, lineCap: .round))
                .frame(width: size * 0.18, height: size * 0.07)
        }
    }

    /// Acessório que aparece conforme o bichinho evolui.
    @ViewBuilder
    private var accessory: some View {
        let symbolSize = size * 0.16
        switch look.headAccessory {
        case .none:
            Color.clear.frame(height: symbolSize)
        case .leaf:
            Image(systemName: "leaf.fill")
                .font(.system(size: symbolSize))
                .foregroundStyle(.green.mix(with: .black, by: 0.2))
                .rotationEffect(.degrees(-20))
        case .crown:
            Image(systemName: "crown.fill")
                .font(.system(size: symbolSize * 1.2))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Casca do ovo que balança de um lado para o outro, como se fosse chocar.
private struct EggShell: View {
    let color: Color
    let size: CGFloat
    let isAnimated: Bool

    @State private var isTilted = false

    private var radiusX: CGFloat { size * 0.29 }
    private var radiusY: CGFloat { size * 0.375 }

    var body: some View {
        ZStack {
            // Espinhos atrás da casca, com a base escondida pela borda do ovo.
            ForEach(EggDesign.spikes, id: \.self) { spike in
                spikeView(spike)
            }
            shell
        }
        .frame(width: size * 0.58, height: size * 0.75)
        .rotationEffect(.degrees(isAnimated ? (isTilted ? 5 : -5) : 0), anchor: .bottom)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isTilted = true
            }
        }
    }

    /// Posiciona o espinho na borda da elipse, apontando para fora.
    private func spikeView(_ spike: EggSpike) -> some View {
        let radians = spike.angle * .pi / 180
        let length = size * spike.length
        let inset = size * 0.025
        let distance = length / 2 - inset
        let x = (radiusX + distance) * CGFloat(sin(radians))
        let y = -(radiusY + distance) * CGFloat(cos(radians))

        return SpikeShape()
            .fill(LinearGradient(colors: [color.mix(with: .black, by: 0.1), color.mix(with: .white, by: 0.3)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.11, height: length)
            .rotationEffect(.degrees(spike.angle))
            .offset(x: x, y: y)
    }

    private var shell: some View {
        Ellipse()
            .fill(LinearGradient(colors: [.white, color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            .overlay {
                ZStack {
                    Circle().fill(color.opacity(0.5)).frame(width: size * 0.12, height: size * 0.12)
                        .offset(x: -size * 0.1, y: -size * 0.12)
                    Circle().fill(color.opacity(0.5)).frame(width: size * 0.08, height: size * 0.08)
                        .offset(x: size * 0.12, y: size * 0.02)
                    Circle().fill(color.opacity(0.5)).frame(width: size * 0.1, height: size * 0.1)
                        .offset(x: -size * 0.04, y: size * 0.18)
                }
            }
            .overlay { Ellipse().stroke(color.opacity(0.4), lineWidth: 2) }
    }
}

/// Espinho com ponta levemente arredondada, apontando para cima.
struct SpikeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.width * 0.3, y: rect.height * 0.4))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.width * 0.7, y: rect.height * 0.4))
        path.closeSubpath()
        return path
    }
}

/// Brilho dourado com faíscas ao redor do bichinho Lendário.
private struct PetAura: View {
    let size: CGFloat
    let isAnimated: Bool

    private let sparkles: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-0.42, -0.3, 1), (0.4, -0.36, 0.7), (0.44, 0.1, 0.9), (-0.45, 0.12, 0.6)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.yellow.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
            ForEach(sparkles.indices, id: \.self) { index in
                let sparkle = sparkles[index]
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.08 * sparkle.scale))
                    .foregroundStyle(.yellow)
                    .offset(x: size * sparkle.x, y: size * sparkle.y)
            }
        }
        .frame(width: size, height: size)
        .phaseAnimator(isAnimated ? [false, true] : [false]) { content, glowing in
            content
                .opacity(glowing ? 1 : 0.55)
                .scaleEffect(glowing ? 1.04 : 0.96)
        } animation: { _ in .easeInOut(duration: 1.5) }
    }
}

/// Orelha em forma de gota pontuda, com a base embaixo.
struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.height * 0.3))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.height * 0.3))
        path.closeSubpath()
        return path
    }
}

/// Rabinho enrolado.
struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.8))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.3),
                          control: CGPoint(x: rect.width * 0.7, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.1),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Asa esquerda. A direita é desenhada espelhando esta.
struct WingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = CGPoint(x: rect.maxX, y: rect.height * 0.75)
        path.move(to: base)
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.05),
                          control: CGPoint(x: rect.width * 0.05, y: rect.height * 0.9))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.3),
                          control: CGPoint(x: rect.width * 0.2, y: rect.height * 0.1))
        path.addQuadCurve(to: base,
                          control: CGPoint(x: rect.width * 0.75, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Boca em curva: curvatura positiva sorri, negativa fica triste.
struct MouthShape: Shape {
    var curve: CGFloat

    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edgeY = rect.midY - curve * rect.height / 2
        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: edgeY),
                          control: CGPoint(x: rect.midX, y: rect.midY + curve * rect.height))
        return path
    }
}

#Preview("Evoluções") {
    HStack(spacing: 24) {
        ForEach(PetStage.allCases, id: \.self) { stage in
            VStack {
                PetView(stage: stage, mood: .happy, color: .green, size: 150)
                Text(stage.title).font(.caption.bold())
            }
        }
    }
    .padding(32)
}

#Preview("Formas em cores") {
    HStack(spacing: 24) {
        PetView(stage: .young, mood: .happy, color: .pink, size: 150)
        PetView(stage: .adult, mood: .ok, color: .orange, size: 150)
        PetView(stage: .legend, mood: .happy, color: .purple, size: 150)
    }
    .padding(32)
}

#Preview("Humores") {
    HStack {
        PetView(stage: .adult, mood: .happy, color: .blue, size: 110)
        PetView(stage: .adult, mood: .ok, color: .blue, size: 110)
        PetView(stage: .adult, mood: .sad, color: .blue, size: 110)
        PetView(stage: .adult, mood: .hungry, color: .blue, size: 110)
        PetView(stage: .adult, mood: .sick, color: .blue, size: 110)
    }
    .padding()
}
