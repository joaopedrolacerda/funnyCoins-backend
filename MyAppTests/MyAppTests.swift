import Foundation
import Testing
@testable import MyApp

@Suite("Formato de dinheiro brasileiro")
struct CurrencyFormatTests {
    @Test("Formata com R$, ponto no milhar e vírgula nos centavos")
    func formatsBrazilianCurrency() {
        #expect(TestSupport.reais(123_456).brl.normalizingSpaces == "R$ 1.234,56")
        #expect(Decimal(0).brl.normalizingSpaces == "R$ 0,00")
        #expect(Decimal(1_000_000).brl.normalizingSpaces == "R$ 1.000.000,00")
    }

    @Test("Valores negativos mantêm o padrão brasileiro")
    func formatsNegativeValues() {
        let text = Decimal(-50).brl.normalizingSpaces
        #expect(text.contains("-"))
        #expect(text.contains("R$"))
        #expect(text.contains("50,00"))
    }

    @Test("O formato não depende do idioma do aparelho")
    func ignoresDeviceLocale() {
        #expect(BRFormat.currency.locale.identifier == "pt_BR")
    }

    @Test("O que é digitado no formato brasileiro é lido corretamente")
    func parsesBrazilianInput() throws {
        let value = TestSupport.reais(123_456)
        let parsed = try BRFormat.currency.parseStrategy.parse(value.brl)
        #expect(parsed == value)
    }
}

@Suite("Modelos")
struct ModelTests {
    @Test("Categorias de ganho incluem vendas e presente")
    func incomeCategories() {
        let income = EntryCategory.cases(for: .income)
        #expect(income == [.salary, .freelance, .sales, .gift, .otherIncome])
        #expect(income.allSatisfy { $0.kind == .income })
        #expect(EntryCategory.cases(for: .expense).allSatisfy { $0.kind == .expense })
    }

    @Test("Lançamento guarda tipo e categoria")
    func cashEntryKind() {
        #expect(TestSupport.income(100).kind == .income)
        #expect(TestSupport.expense(100).kind == .expense)
        #expect(TestSupport.expense(100).category == .food)
    }

    @Test("Cursos são uma modalidade de investimento em você")
    func educationModality() {
        let education = InvestmentModality.education
        #expect(InvestmentModality.allCases.contains(education))
        #expect(education.title == "Cursos e educação")
        #expect(education.riskTitle == "Investimento em você")
        #expect(education.risk == 0)
        #expect(InvestmentModality(rawValue: "education") == education)
    }

    @Test("Risco das modalidades de mercado")
    func marketRisk() {
        #expect(InvestmentModality.tesouroSelic.riskTitle == "Risco baixo")
        #expect(InvestmentModality.fii.riskTitle == "Risco médio")
        #expect(InvestmentModality.crypto.riskTitle == "Risco alto")
    }

    @Test("Chave do mês das contas no formato aaaa-mm")
    func billMonthKey() {
        #expect(Bill.monthKey(for: TestSupport.date(2026, 3, 5)) == "2026-03")
        #expect(Bill.monthKey(for: TestSupport.date(2026, 12, 31)) == "2026-12")
    }

    @Test("Conta paga e conta atrasada")
    func billStatus() {
        let bill = Bill(name: "Luz", amount: 200, dueDay: 10)
        #expect(!bill.isPaid(in: TestSupport.today))
        #expect(bill.isOverdue(on: TestSupport.today))
        #expect(!bill.isOverdue(on: TestSupport.date(2026, 10, 5)))

        bill.paidMonthKeys.append(Bill.monthKey(for: TestSupport.today))
        #expect(bill.isPaid(in: TestSupport.today))
        #expect(!bill.isOverdue(on: TestSupport.today))
        #expect(!bill.isPaid(in: TestSupport.date(2026, 11, 15)))
    }

    @Test("Perfil tem bichinho padrão e cor editável")
    func profilePetDefaults() {
        let profile = PlayerProfile(monthlyEssentialCost: 1000)
        #expect(profile.petName == "Moedinha")
        #expect(profile.petColor == .green)
        profile.petColor = .purple
        #expect(profile.petColorRaw == "purple")
    }
}
