import Foundation
@testable import MyApp

/// Utilitários compartilhados pelos testes.
enum TestSupport {
    /// Data fixa usada como "hoje" nos testes: 15/10/2026 ao meio-dia.
    static let today = date(2026, 10, 15)

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// Cria um valor decimal exato a partir de centavos, evitando imprecisão de Double.
    static func reais(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Monta um snapshot com perfil padrão: custo de R$ 1.000 e 6 meses, ou seja, meta de R$ 6.000.
    static func snapshot(
        monthlyCost: Decimal = 1000,
        targetMonths: Int = 6,
        investPercent: Int = 10,
        entries: [CashEntry] = [],
        bills: [Bill] = [],
        reserve: [ReserveMovement] = [],
        investments: [Investment] = [],
        now: Date = today
    ) -> GameSnapshot {
        GameSnapshot(
            profile: PlayerProfile(monthlyEssentialCost: monthlyCost,
                                   targetMonths: targetMonths,
                                   investPercent: investPercent),
            entries: entries,
            bills: bills,
            reserveMovements: reserve,
            investments: investments,
            now: now)
    }

    static func income(_ amount: Decimal, on date: Date = today) -> CashEntry {
        CashEntry(title: "Salário", amount: amount, date: date, category: .salary)
    }

    static func expense(_ amount: Decimal, on date: Date = today) -> CashEntry {
        CashEntry(title: "Mercado", amount: amount, date: date, category: .food)
    }

    static func deposit(_ amount: Decimal, on date: Date = today) -> ReserveMovement {
        ReserveMovement(amount: amount, date: date)
    }

    static func investment(_ amount: Decimal, in modality: InvestmentModality, on date: Date = today) -> Investment {
        Investment(name: modality.title, modality: modality, amount: amount, date: date)
    }
}

extension String {
    /// O formatador brasileiro usa espaço não separável entre "R$" e o número.
    var normalizingSpaces: String {
        replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
