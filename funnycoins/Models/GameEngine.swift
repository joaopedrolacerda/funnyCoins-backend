import Foundation

/// Conquista desbloqueável da jornada.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let isUnlocked: Bool
}

/// Fotografia do estado do jogo calculada a partir dos dados salvos.
/// Toda a lógica de progressão fica aqui, separada das telas.
struct GameSnapshot {
    let profile: PlayerProfile
    let entries: [CashEntry]
    let bills: [Bill]
    let reserveMovements: [ReserveMovement]
    let investments: [Investment]
    var now: Date = .now

    // MARK: Nível 1 - Reserva de emergência

    var reserveBalance: Decimal {
        reserveMovements.reduce(0) { $0 + $1.amount }
    }

    var reserveGoal: Decimal {
        profile.monthlyEssentialCost * Decimal(profile.targetMonths)
    }

    var reserveProgress: Double {
        guard reserveGoal > 0 else { return 0 }
        return min(max((reserveBalance / reserveGoal).doubleValue, 0), 1)
    }

    var reserveMissing: Decimal {
        max(reserveGoal - reserveBalance, 0)
    }

    /// Meses de custo de vida cobertos pela reserva atual.
    var monthsCovered: Double {
        guard profile.monthlyEssentialCost > 0 else { return 0 }
        return (reserveBalance / profile.monthlyEssentialCost).doubleValue
    }

    var isLevel1Complete: Bool {
        reserveGoal > 0 && reserveBalance >= reserveGoal
    }

    /// O Nível 2 só fica disponível com a reserva completa.
    var currentLevel: Int { isLevel1Complete ? 2 : 1 }

    // MARK: Fluxo de caixa

    private func isInCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: now, toGranularity: .month)
    }

    var monthIncome: Decimal {
        entries.filter { $0.kind == .income && isInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var monthExpense: Decimal {
        entries.filter { $0.kind == .expense && isInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var totalIncome: Decimal {
        entries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
    }

    var totalExpense: Decimal {
        entries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
    }

    /// Dinheiro livre: entradas menos saídas, reserva e investimentos.
    var freeBalance: Decimal {
        totalIncome - totalExpense - reserveBalance - investedTotal
    }

    var pendingBillsThisMonth: [Bill] {
        bills.filter { !$0.isPaid(in: now) }
    }

    // MARK: Nível 2 - Investimentos

    var investedTotal: Decimal {
        investments.reduce(0) { $0 + $1.amount }
    }

    var investedThisMonth: Decimal {
        investments.filter { isInCurrentMonth($0.date) }.reduce(0) { $0 + $1.amount }
    }

    /// Meta mensal de aporte: percentual das entradas do mês.
    var monthlyInvestTarget: Decimal {
        monthIncome * Decimal(profile.investPercent) / 100
    }

    var monthlyInvestProgress: Double {
        guard monthlyInvestTarget > 0 else { return 0 }
        return min((investedThisMonth / monthlyInvestTarget).doubleValue, 1)
    }

    /// Quanto de um ganho vai para a reserva (Nível 1) ou para investimentos (Nível 2).
    /// No Nível 1 nunca passa do que falta para completar a reserva.
    func suggestedSplit(of amount: Decimal, percent: Int) -> Decimal {
        guard amount > 0, percent > 0 else { return 0 }
        let raw = amount * Decimal(percent) / 100
        return isLevel1Complete ? raw : min(raw, reserveMissing)
    }

    /// Total investido agrupado por modalidade, do maior para o menor.
    var allocation: [(modality: InvestmentModality, amount: Decimal)] {
        Dictionary(grouping: investments, by: \.modality)
            .map { (modality: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: Gamificação

    var achievements: [Achievement] {
        let paidAllBills = !bills.isEmpty && pendingBillsThisMonth.isEmpty
        let modalities = Set(investments.map(\.modality)).count
        return [
            Achievement(id: "first-entry", title: "Primeiro passo",
                        detail: "Registre seu primeiro lançamento",
                        symbol: "flag.fill", isUnlocked: !entries.isEmpty),
            Achievement(id: "bills-ok", title: "Contas em dia",
                        detail: "Pague todas as contas fixas do mês",
                        symbol: "checkmark.seal.fill", isUnlocked: paidAllBills),
            Achievement(id: "reserve-25", title: "Cofrinho",
                        detail: "Chegue a 25% da reserva",
                        symbol: "shield.lefthalf.filled", isUnlocked: reserveProgress >= 0.25),
            Achievement(id: "reserve-50", title: "Meio caminho",
                        detail: "Chegue a 50% da reserva",
                        symbol: "shield.fill", isUnlocked: reserveProgress >= 0.5),
            Achievement(id: "reserve-100", title: "Blindado",
                        detail: "Complete a reserva de emergência",
                        symbol: "shield.checkered", isUnlocked: isLevel1Complete),
            Achievement(id: "first-investment", title: "Investidor",
                        detail: "Faça seu primeiro aporte",
                        symbol: "chart.line.uptrend.xyaxis", isUnlocked: !investments.isEmpty),
            Achievement(id: "diversified", title: "Diversificado",
                        detail: "Invista em 3 modalidades diferentes",
                        symbol: "circle.hexagongrid.fill", isUnlocked: modalities >= 3),
            Achievement(id: "monthly-goal", title: "Meta batida",
                        detail: "Atinja a meta de aporte do mês",
                        symbol: "trophy.fill",
                        isUnlocked: monthlyInvestTarget > 0 && investedThisMonth >= monthlyInvestTarget)
        ]
    }

    /// XP calculado a partir das ações registradas, sem estado extra para salvar.
    var xp: Int {
        let entryXP = entries.count * 5
        let billXP = bills.reduce(0) { $0 + $1.paidMonthKeys.count } * 15
        let depositXP = reserveMovements.filter { $0.amount > 0 }.count * 20
        let investXP = investments.count * 30
        let achievementXP = achievements.filter(\.isUnlocked).count * 100
        return entryXP + billXP + depositXP + investXP + achievementXP
    }

    private static let ranks: [(minXP: Int, title: String)] = [
        (0, "Aprendiz"),
        (200, "Poupador"),
        (600, "Estrategista"),
        (1500, "Investidor"),
        (4000, "Mestre das Finanças")
    ]

    var rankTitle: String {
        Self.ranks.last { xp >= $0.minXP }?.title ?? "Aprendiz"
    }

    /// XP da próxima patente, ou nil se já estiver na última.
    var nextRankXP: Int? {
        Self.ranks.first { $0.minXP > xp }?.minXP
    }

    var rankProgress: Double {
        guard let next = nextRankXP else { return 1 }
        let current = Self.ranks.last { xp >= $0.minXP }?.minXP ?? 0
        return Double(xp - current) / Double(next - current)
    }
}
