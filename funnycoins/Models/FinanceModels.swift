import Foundation
import SwiftData

// MARK: - Enums

/// Tipo de lançamento no fluxo de caixa.
enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: "Entrada"
        case .expense: "Saída"
        }
    }
}

/// Categorias de lançamentos. Cada categoria pertence a um tipo (entrada ou saída).
enum EntryCategory: String, Codable, CaseIterable, Identifiable {
    case salary
    case freelance
    case sales
    case gift
    case otherIncome
    case housing
    case food
    case transport
    case health
    case education
    case leisure
    case bills
    case otherExpense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salary: "Salário"
        case .freelance: "Renda extra"
        case .sales: "Vendas"
        case .gift: "Presente"
        case .otherIncome: "Outras entradas"
        case .housing: "Moradia"
        case .food: "Alimentação"
        case .transport: "Transporte"
        case .health: "Saúde"
        case .education: "Educação"
        case .leisure: "Lazer"
        case .bills: "Contas fixas"
        case .otherExpense: "Outras saídas"
        }
    }

    var symbol: String {
        switch self {
        case .salary: "briefcase.fill"
        case .freelance: "sparkles"
        case .sales: "bag.fill"
        case .gift: "gift.fill"
        case .otherIncome: "plus.circle.fill"
        case .housing: "house.fill"
        case .food: "fork.knife"
        case .transport: "car.fill"
        case .health: "cross.case.fill"
        case .education: "book.fill"
        case .leisure: "gamecontroller.fill"
        case .bills: "doc.text.fill"
        case .otherExpense: "minus.circle.fill"
        }
    }

    var kind: EntryKind {
        switch self {
        case .salary, .freelance, .sales, .gift, .otherIncome: .income
        default: .expense
        }
    }

    static func cases(for kind: EntryKind) -> [EntryCategory] {
        allCases.filter { $0.kind == kind }
    }
}

/// Modalidades de investimento disponíveis no Nível 2.
enum InvestmentModality: String, Codable, CaseIterable, Identifiable {
    case tesouroSelic
    case cdb
    case lciLca
    case tesouroIPCA
    case fii
    case stocks
    case etf
    case crypto
    case pension
    /// Investimento em si mesmo: cursos, livros, certificações.
    case education
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .education: "Cursos e educação"
        case .tesouroSelic: "Tesouro Selic"
        case .cdb: "CDB"
        case .lciLca: "LCI / LCA"
        case .tesouroIPCA: "Tesouro IPCA+"
        case .fii: "Fundos Imobiliários"
        case .stocks: "Ações"
        case .etf: "ETFs"
        case .crypto: "Criptomoedas"
        case .pension: "Previdência"
        case .other: "Outros"
        }
    }

    var symbol: String {
        switch self {
        case .tesouroSelic: "building.columns.fill"
        case .cdb: "banknote.fill"
        case .lciLca: "leaf.fill"
        case .tesouroIPCA: "chart.line.uptrend.xyaxis"
        case .fii: "building.2.fill"
        case .stocks: "chart.bar.fill"
        case .etf: "square.stack.3d.up.fill"
        case .crypto: "bitcoinsign.circle.fill"
        case .pension: "figure.walk"
        case .education: "graduationcap.fill"
        case .other: "star.fill"
        }
    }

    /// Nível de risco de 1 (baixo) a 3 (alto). 0 indica investimento em si mesmo, sem risco de mercado.
    var risk: Int {
        switch self {
        case .education: 0
        case .tesouroSelic, .cdb, .lciLca: 1
        case .tesouroIPCA, .fii, .pension, .other: 2
        case .stocks, .etf, .crypto: 3
        }
    }

    var riskTitle: String {
        switch risk {
        case 0: "Investimento em você"
        case 1: "Risco baixo"
        case 2: "Risco médio"
        default: "Risco alto"
        }
    }
}

// MARK: - Models

/// Perfil do jogador: define a meta da reserva e o percentual a investir.
@Model
final class PlayerProfile: Syncable {
    // Campos de sincronização. Valores padrão permitem a migração automática.
    var syncID: UUID = UUID()
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var monthlyEssentialCost: Decimal
    var targetMonths: Int
    var investPercent: Int
    var createdAt: Date
    // Valores padrão permitem migração automática de perfis já salvos.
    var petName: String = "Moedinha"
    var petColorRaw: String = PetColor.green.rawValue

    init(monthlyEssentialCost: Decimal, targetMonths: Int = 6, investPercent: Int = 10,
         petName: String = "Moedinha", petColor: PetColor = .green) {
        self.monthlyEssentialCost = monthlyEssentialCost
        self.targetMonths = targetMonths
        self.investPercent = investPercent
        self.createdAt = .now
        self.petName = petName
        self.petColorRaw = petColor.rawValue
    }

    var petColor: PetColor {
        get { PetColor(rawValue: petColorRaw) ?? .green }
        set { petColorRaw = newValue.rawValue }
    }
}

/// Lançamento de entrada ou saída de dinheiro.
@Model
final class CashEntry: Syncable {
    // Campos de sincronização. Valores padrão permitem a migração automática.
    var syncID: UUID = UUID()
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var title: String
    var amount: Decimal
    var date: Date
    var kindRaw: String
    var categoryRaw: String

    init(title: String, amount: Decimal, date: Date = .now, category: EntryCategory) {
        self.title = title
        self.amount = amount
        self.date = date
        self.kindRaw = category.kind.rawValue
        self.categoryRaw = category.rawValue
    }

    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .expense }
    var category: EntryCategory { EntryCategory(rawValue: categoryRaw) ?? .otherExpense }
}

/// Conta fixa mensal (aluguel, luz, internet...).
@Model
final class Bill: Syncable {
    // Campos de sincronização. Valores padrão permitem a migração automática.
    var syncID: UUID = UUID()
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var name: String
    var amount: Decimal
    var dueDay: Int
    /// Meses pagos no formato "aaaa-mm".
    var paidMonthKeys: [String]
    var createdAt: Date

    init(name: String, amount: Decimal, dueDay: Int) {
        self.name = name
        self.amount = amount
        self.dueDay = dueDay
        self.paidMonthKeys = []
        self.createdAt = .now
    }

    func isPaid(in date: Date = .now) -> Bool {
        paidMonthKeys.contains(Bill.monthKey(for: date))
    }

    /// Conta não paga cujo dia de vencimento já passou no mês atual.
    func isOverdue(on date: Date = .now) -> Bool {
        !isPaid(in: date) && Calendar.current.component(.day, from: date) > dueDay
    }

    static func monthKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// Depósito (valor positivo) ou retirada (valor negativo) da reserva de emergência.
@Model
final class ReserveMovement: Syncable {
    // Campos de sincronização. Valores padrão permitem a migração automática.
    var syncID: UUID = UUID()
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var amount: Decimal
    var date: Date
    var note: String

    init(amount: Decimal, date: Date = .now, note: String = "") {
        self.amount = amount
        self.date = date
        self.note = note
    }
}

/// Aporte em uma modalidade de investimento.
@Model
final class Investment: Syncable {
    // Campos de sincronização. Valores padrão permitem a migração automática.
    var syncID: UUID = UUID()
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var name: String
    var modalityRaw: String
    var amount: Decimal
    var date: Date

    init(name: String, modality: InvestmentModality, amount: Decimal, date: Date = .now) {
        self.name = name
        self.modalityRaw = modality.rawValue
        self.amount = amount
        self.date = date
    }

    var modality: InvestmentModality { InvestmentModality(rawValue: modalityRaw) ?? .other }
}

// MARK: - Formato brasileiro

/// Formatação fixa no padrão brasileiro, independente do idioma do aparelho.
/// Toda exibição e digitação de dinheiro no app deve passar por aqui.
enum BRFormat {
    static let locale = Locale(identifier: "pt_BR")

    /// Ex: R$ 1.234,56
    static var currency: Decimal.FormatStyle.Currency {
        .currency(code: "BRL").locale(locale)
    }
}

extension Decimal {
    var brl: String { formatted(BRFormat.currency) }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
