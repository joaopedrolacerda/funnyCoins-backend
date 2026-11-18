import Foundation

/// Cores disponíveis para o bichinho.
enum PetColor: String, CaseIterable, Identifiable {
    case green, blue, pink, orange, purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: "Verde"
        case .blue: "Azul"
        case .pink: "Rosa"
        case .orange: "Laranja"
        case .purple: "Roxo"
        }
    }
}

/// Estágios de evolução, ligados ao progresso nos níveis.
enum PetStage: Int, CaseIterable, Comparable {
    case egg, baby, young, adult, legend

    var title: String {
        switch self {
        case .egg: "Ovo"
        case .baby: "Filhote"
        case .young: "Jovem"
        case .adult: "Adulto"
        case .legend: "Lendário"
        }
    }

    /// Tamanho relativo do bichinho: ele cresce ao evoluir.
    var scale: CGFloat {
        switch self {
        case .egg: 0.8
        case .baby: 0.75
        case .young: 0.85
        case .adult: 0.95
        case .legend: 1.0
        }
    }

    static func < (lhs: PetStage, rhs: PetStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Estilo das orelhas do bichinho.
enum PetEars: Hashable {
    case none
    /// Orelhinhas pontudas curtas.
    case pointy
    /// Orelhas longas, mais imponentes.
    case long
}

/// Enfeite no topo da cabeça.
enum PetHeadAccessory: Hashable {
    case none, leaf, crown
}

/// Forma do corpo e partes de cada estágio. Medidas são frações do tamanho da view.
struct PetAppearance: Hashable {
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    var cornerRatio: CGFloat
    var ears: PetEars = .none
    var hasArms = false
    var hasTail = false
    var hasWings = false
    var hasAura = false
    /// Símbolo na barriga (SF Symbol), ou nil.
    var bellyEmblem: String?
    var headAccessory: PetHeadAccessory = .none

    /// Quantidade de partes extras: cresce a cada evolução.
    var featureCount: Int {
        [ears != .none, hasArms, hasTail, hasWings, hasAura, bellyEmblem != nil, headAccessory != .none]
            .filter { $0 }.count
    }
}

extension PetStage {
    /// Forma de cada estágio. O ovo é desenhado à parte e não tem aparência de criatura.
    var appearance: PetAppearance? {
        switch self {
        case .egg:
            nil
        case .baby:
            // Bolinha redonda original: sem partes extras.
            PetAppearance(bodyWidth: 0.78, bodyHeight: 0.7, cornerRatio: 0.36)
        case .young:
            // Mais alto, com orelhinhas, bracinhos e um broto na cabeça.
            PetAppearance(bodyWidth: 0.7, bodyHeight: 0.76, cornerRatio: 0.32,
                          ears: .pointy, hasArms: true, headAccessory: .leaf)
        case .adult:
            // Forte e protegido: orelhas longas, rabinho e escudo da reserva completa.
            PetAppearance(bodyWidth: 0.8, bodyHeight: 0.78, cornerRatio: 0.3,
                          ears: .long, hasArms: true, hasTail: true, bellyEmblem: "shield.fill")
        case .legend:
            // Lendário: asas, aura dourada, coroa e estrela na barriga.
            PetAppearance(bodyWidth: 0.82, bodyHeight: 0.8, cornerRatio: 0.3,
                          ears: .long, hasArms: true, hasTail: true, hasWings: true, hasAura: true,
                          bellyEmblem: "star.fill", headAccessory: .crown)
        }
    }
}

/// Espinho na casca do ovo.
struct EggSpike: Hashable {
    /// Ângulo em graus a partir do topo do ovo, no sentido horário. Negativo fica do lado esquerdo.
    let angle: Double
    /// Comprimento como fração do tamanho da view.
    let length: CGFloat
}

/// Desenho do ovo, o primeiro estágio.
enum EggDesign {
    /// Espinhos simétricos espalhados pela casca, sem nenhum embaixo, onde o ovo se apoia.
    static let spikes: [EggSpike] = [
        EggSpike(angle: 0, length: 0.14),
        EggSpike(angle: -35, length: 0.12),
        EggSpike(angle: 35, length: 0.12),
        EggSpike(angle: -75, length: 0.13),
        EggSpike(angle: 75, length: 0.13),
        EggSpike(angle: -115, length: 0.1),
        EggSpike(angle: 115, length: 0.1)
    ]

    /// Maior ângulo permitido para um espinho. Passou disso, ele encostaria no chão.
    static let maxSpikeAngle: Double = 130
}

/// Humor do bichinho, calculado a partir do comportamento financeiro.
enum PetMood {
    case happy, ok, sad, hungry, sick

    var title: String {
        switch self {
        case .happy: "Feliz"
        case .ok: "Tranquilo"
        case .sad: "Triste"
        case .hungry: "Com fome"
        case .sick: "Doente"
        }
    }

    var symbol: String {
        switch self {
        case .happy: "heart.fill"
        case .ok: "face.smiling"
        case .sad: "cloud.rain.fill"
        case .hungry: "fork.knife"
        case .sick: "thermometer.medium"
        }
    }

    /// Curvatura da boca: 1 sorriso, -1 tristeza.
    var mouthCurve: CGFloat {
        switch self {
        case .happy: 1
        case .ok: 0.4
        case .sad: -0.7
        case .hungry: 0
        case .sick: -0.4
        }
    }
}

/// Necessidades do bichinho, de 0 a 1.
struct PetNeeds {
    /// Cai a cada dia sem registrar lançamentos.
    let hunger: Double
    /// Progresso da reserva de emergência.
    let protection: Double
    /// Sobe com contas em dia e aportes; cai com contas atrasadas.
    let joy: Double

    var average: Double { (hunger + protection + joy) / 3 }
}

extension GameSnapshot {
    var daysSinceLastEntry: Int? {
        guard let last = entries.map(\.date).max() else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return max(days, 0)
    }

    var overdueBills: [Bill] {
        bills.filter { $0.isOverdue(on: now) }
    }

    var petNeeds: PetNeeds {
        // Fome: cheia no dia do registro, vazia depois de 5 dias sem registrar.
        let hunger = daysSinceLastEntry.map { max(0, 1 - Double($0) * 0.2) } ?? 0

        let protection = isLevel1Complete ? 1 : reserveProgress

        let calendar = Calendar.current
        let savedThisMonth = reserveMovements.contains {
            $0.amount > 0 && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        } || investedThisMonth > 0
        var joy = 0.5
        joy -= Double(overdueBills.count) * 0.25
        if !bills.isEmpty && pendingBillsThisMonth.isEmpty { joy += 0.25 }
        if savedThisMonth { joy += 0.25 }

        return PetNeeds(hunger: hunger, protection: protection, joy: min(max(joy, 0), 1))
    }

    var petMood: PetMood {
        let needs = petNeeds
        if !overdueBills.isEmpty { return .sick }
        if needs.hunger < 0.3 { return .hungry }
        if needs.average >= 0.7 { return .happy }
        if needs.average >= 0.4 { return .ok }
        return .sad
    }

    var petStage: PetStage {
        if entries.isEmpty { return .egg }
        let modalities = Set(investments.map(\.modality)).count
        if isLevel1Complete && (modalities >= 3 || xp >= 1500) { return .legend }
        if isLevel1Complete { return .adult }
        if reserveProgress >= 0.5 { return .young }
        return .baby
    }

    var nextEvolutionHint: String? {
        switch petStage {
        case .egg: "Registre seu primeiro ganho para chocar o ovo"
        case .baby: "Chegue a 50% da reserva para virar Jovem"
        case .young: "Complete a reserva para virar Adulto"
        case .adult: "Invista em 3 modalidades para virar Lendário"
        case .legend: nil
        }
    }

    /// Fala do bichinho de acordo com o estado atual.
    var petMessage: String {
        if petStage == .egg { return "Toc, toc... registre um ganho para eu nascer!" }
        switch petMood {
        case .happy: return "Estou muito feliz! Nossas finanças estão em dia."
        case .ok: return "Tô bem! Que tal guardar um pouquinho hoje?"
        case .sad: return "Tô meio pra baixo... me ajuda a crescer a reserva?"
        case .hungry: return "Tô com fome! Registre um ganho ou gasto pra me alimentar."
        case .sick:
            let names = overdueBills.map(\.name).formatted(.list(type: .and))
            return "Ai... \(names) atrasou e isso me deixa doente. Paga pra mim?"
        }
    }

    static let petTips = [
        "Reserva de emergência primeiro, investimento depois!",
        "Anotar cada gasto é o segredo pra saber pra onde vai o dinheiro.",
        "Pague as contas fixas antes de gastar com lazer.",
        "Guardar um pouco de cada ganho faz a reserva crescer rapidinho.",
        "Diversificar é não colocar todos os ovos na mesma cesta. Falo por experiência!",
        "Investimento de risco alto só com dinheiro que pode esperar.",
        "Pequenos valores todo mês valem mais que um valor grande de vez em quando."
    ]
}
