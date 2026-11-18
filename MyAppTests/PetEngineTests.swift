import Foundation
import Testing
@testable import MyApp

@Suite("Bichinho")
struct PetEngineTests {
    @Test("Começa como ovo e choca com o primeiro lançamento")
    func hatches() {
        #expect(TestSupport.snapshot().petStage == .egg)
        #expect(TestSupport.snapshot(entries: [TestSupport.income(100)]).petStage == .baby)
    }

    @Test("Evolui conforme a reserva e os investimentos", arguments: [
        (Decimal(2999), [InvestmentModality](), PetStage.baby),
        (Decimal(3000), [], PetStage.young),
        (Decimal(6000), [], PetStage.adult),
        (Decimal(6000), [.cdb, .fii, .education], PetStage.legend)
    ])
    func evolution(reserve: Decimal, modalities: [InvestmentModality], expected: PetStage) {
        let snapshot = TestSupport.snapshot(
            entries: [TestSupport.income(100)],
            reserve: [TestSupport.deposit(reserve)],
            investments: modalities.map { TestSupport.investment(100, in: $0) })
        #expect(snapshot.petStage == expected)
    }

    @Test("Sem 3 modalidades, só vira lendário se tiver muito XP")
    func legendNeedsDiversification() {
        let snapshot = TestSupport.snapshot(
            entries: [TestSupport.income(100)],
            reserve: [TestSupport.deposit(6000)],
            investments: [TestSupport.investment(100, in: .cdb)])
        #expect(snapshot.petStage == .adult)
        #expect(snapshot.nextEvolutionHint == "Invista em 3 modalidades para virar Lendário")
    }

    @Test("Fome cai 20% por dia sem registro", arguments: [
        (0, 1.0), (1, 0.8), (3, 0.4), (5, 0.0), (10, 0.0)
    ])
    func hunger(daysAgo: Int, expected: Double) {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: TestSupport.today) ?? TestSupport.today
        let snapshot = TestSupport.snapshot(entries: [TestSupport.expense(10, on: day)])
        #expect(snapshot.daysSinceLastEntry == daysAgo)
        #expect(abs(snapshot.petNeeds.hunger - expected) < 0.0001)
    }

    @Test("Sem nenhum registro a fome é total")
    func hungerWithoutEntries() {
        let snapshot = TestSupport.snapshot()
        #expect(snapshot.daysSinceLastEntry == nil)
        #expect(snapshot.petNeeds.hunger == 0)
    }

    @Test("Conta atrasada deixa o bichinho doente e ele cita a conta")
    func sickWithOverdueBill() {
        let bill = Bill(name: "Internet", amount: 100, dueDay: 10)
        let snapshot = TestSupport.snapshot(entries: [TestSupport.income(100)], bills: [bill])
        #expect(snapshot.petMood == .sick)
        #expect(snapshot.petMessage.contains("Internet"))
        #expect(snapshot.petNeeds.joy == 0.25)
    }

    @Test("Muitos dias sem registro deixam com fome")
    func hungryMood() {
        let snapshot = TestSupport.snapshot(entries: [TestSupport.income(100, on: TestSupport.date(2026, 10, 1))])
        #expect(snapshot.petMood == .hungry)
    }

    @Test("Bem cuidado fica feliz")
    func happyMood() {
        let bill = Bill(name: "Luz", amount: 200, dueDay: 10)
        bill.paidMonthKeys = [Bill.monthKey(for: TestSupport.today)]
        let snapshot = TestSupport.snapshot(entries: [TestSupport.income(5000)],
                                            bills: [bill],
                                            reserve: [TestSupport.deposit(4000)])
        #expect(snapshot.petNeeds.joy == 1)
        #expect(snapshot.petMood == .happy)
    }

    @Test("Proteção acompanha a reserva")
    func protection() {
        #expect(TestSupport.snapshot(reserve: [TestSupport.deposit(1500)]).petNeeds.protection == 0.25)
        #expect(TestSupport.snapshot(reserve: [TestSupport.deposit(6000)]).petNeeds.protection == 1)
    }
}
