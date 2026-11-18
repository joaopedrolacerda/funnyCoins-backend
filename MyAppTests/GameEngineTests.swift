import Foundation
import Testing
@testable import MyApp

@Suite("Nível 1: reserva de emergência")
struct ReserveTests {
    @Test("Meta é o custo mensal vezes os meses")
    func reserveGoal() {
        let snapshot = TestSupport.snapshot(monthlyCost: 2500, targetMonths: 6)
        #expect(snapshot.reserveGoal == 15_000)
    }

    @Test("Progresso, valor que falta e meses cobertos")
    func reserveProgress() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(1500)])
        #expect(snapshot.reserveBalance == 1500)
        #expect(snapshot.reserveProgress == 0.25)
        #expect(snapshot.reserveMissing == 4500)
        #expect(snapshot.monthsCovered == 1.5)
        #expect(!snapshot.isLevel1Complete)
        #expect(snapshot.currentLevel == 1)
    }

    @Test("Retirada diminui a reserva")
    func withdrawal() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(3000), TestSupport.deposit(-1000)])
        #expect(snapshot.reserveBalance == 2000)
    }

    @Test("Completar a meta libera o Nível 2")
    func unlocksLevel2() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(6000)])
        #expect(snapshot.isLevel1Complete)
        #expect(snapshot.currentLevel == 2)
        #expect(snapshot.reserveMissing == 0)
    }

    @Test("Progresso nunca passa de 100%")
    func progressIsClamped() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(9000)])
        #expect(snapshot.reserveProgress == 1)
    }

    @Test("Sem custo mensal não existe meta")
    func zeroGoal() {
        let snapshot = TestSupport.snapshot(monthlyCost: 0, reserve: [TestSupport.deposit(100)])
        #expect(snapshot.reserveProgress == 0)
        #expect(!snapshot.isLevel1Complete)
    }
}

@Suite("Fluxo de caixa")
struct CashFlowTests {
    @Test("Totais do mês ignoram outros meses")
    func monthTotals() {
        let snapshot = TestSupport.snapshot(entries: [
            TestSupport.income(5000),
            TestSupport.income(800, on: TestSupport.date(2026, 9, 20)),
            TestSupport.expense(1200),
            TestSupport.expense(300, on: TestSupport.date(2026, 9, 1))
        ])
        #expect(snapshot.monthIncome == 5000)
        #expect(snapshot.monthExpense == 1200)
        #expect(snapshot.totalIncome == 5800)
        #expect(snapshot.totalExpense == 1500)
    }

    @Test("Saldo livre desconta gastos, reserva e investimentos")
    func freeBalance() {
        let snapshot = TestSupport.snapshot(
            entries: [TestSupport.income(5000), TestSupport.expense(1000)],
            reserve: [TestSupport.deposit(1500)],
            investments: [TestSupport.investment(500, in: .cdb)])
        #expect(snapshot.freeBalance == 2000)
    }

    @Test("Contas pendentes do mês")
    func pendingBills() {
        let paid = Bill(name: "Aluguel", amount: 1500, dueDay: 5)
        paid.paidMonthKeys = [Bill.monthKey(for: TestSupport.today)]
        let pending = Bill(name: "Internet", amount: 100, dueDay: 20)
        let snapshot = TestSupport.snapshot(bills: [paid, pending])
        #expect(snapshot.pendingBillsThisMonth.map(\.name) == ["Internet"])
    }
}

@Suite("Nível 2: investimentos")
struct InvestmentTests {
    @Test("Meta mensal é o percentual das entradas do mês")
    func monthlyTarget() {
        let snapshot = TestSupport.snapshot(
            investPercent: 20,
            entries: [TestSupport.income(5000)],
            investments: [TestSupport.investment(500, in: .tesouroSelic)])
        #expect(snapshot.monthlyInvestTarget == 1000)
        #expect(snapshot.investedThisMonth == 500)
        #expect(snapshot.monthlyInvestProgress == 0.5)
    }

    @Test("Carteira agrupada por modalidade, da maior para a menor")
    func allocation() {
        let snapshot = TestSupport.snapshot(investments: [
            TestSupport.investment(300, in: .education),
            TestSupport.investment(1000, in: .cdb),
            TestSupport.investment(200, in: .cdb)
        ])
        #expect(snapshot.allocation.map(\.modality) == [.cdb, .education])
        #expect(snapshot.allocation.map(\.amount) == [1200, 300])
        #expect(snapshot.investedTotal == 1500)
    }

    @Test("No Nível 1 a parte separada não passa do que falta na reserva")
    func splitCappedAtReserve() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(5800)])
        #expect(snapshot.suggestedSplit(of: 1000, percent: 10) == 100)
        #expect(snapshot.suggestedSplit(of: 1000, percent: 50) == 200)
    }

    @Test("No Nível 2 a parte separada é o percentual inteiro")
    func splitWhenInvesting() {
        let snapshot = TestSupport.snapshot(reserve: [TestSupport.deposit(6000)])
        #expect(snapshot.suggestedSplit(of: 1000, percent: 50) == 500)
    }

    @Test("Sem percentual ou sem valor não separa nada")
    func noSplit() {
        let snapshot = TestSupport.snapshot()
        #expect(snapshot.suggestedSplit(of: 1000, percent: 0) == 0)
        #expect(snapshot.suggestedSplit(of: 0, percent: 30) == 0)
    }
}

@Suite("Gamificação")
struct GamificationTests {
    private func isUnlocked(_ id: String, in snapshot: GameSnapshot) -> Bool {
        snapshot.achievements.first { $0.id == id }?.isUnlocked ?? false
    }

    @Test("Começo do jogo: nada desbloqueado")
    func freshStart() {
        let snapshot = TestSupport.snapshot()
        #expect(snapshot.achievements.allSatisfy { !$0.isUnlocked })
        #expect(snapshot.xp == 0)
        #expect(snapshot.rankTitle == "Aprendiz")
        #expect(snapshot.nextRankXP == 200)
    }

    @Test("XP soma ações e conquistas e define a patente")
    func xpAndRank() {
        // 1 lançamento (5) + 1 depósito (20) + 3 conquistas (300): primeiro passo, 25% e 50%.
        let snapshot = TestSupport.snapshot(entries: [TestSupport.income(5000)],
                                            reserve: [TestSupport.deposit(3000)])
        #expect(snapshot.xp == 325)
        #expect(snapshot.rankTitle == "Poupador")
        #expect(snapshot.nextRankXP == 600)
        #expect(snapshot.rankProgress == 0.3125)
    }

    @Test("Contas em dia só com todas as contas do mês pagas")
    func billsAchievement() {
        let bill = Bill(name: "Luz", amount: 200, dueDay: 10)
        #expect(!isUnlocked("bills-ok", in: TestSupport.snapshot(bills: [bill])))
        bill.paidMonthKeys = [Bill.monthKey(for: TestSupport.today)]
        #expect(isUnlocked("bills-ok", in: TestSupport.snapshot(bills: [bill])))
    }

    @Test("Curso conta para a conquista de diversificação")
    func diversificationWithEducation() {
        let snapshot = TestSupport.snapshot(investments: [
            TestSupport.investment(100, in: .cdb),
            TestSupport.investment(100, in: .fii),
            TestSupport.investment(100, in: .education)
        ])
        #expect(isUnlocked("diversified", in: snapshot))
        #expect(isUnlocked("first-investment", in: snapshot))
    }

    @Test("Meta do mês batida")
    func monthlyGoalAchievement() {
        let snapshot = TestSupport.snapshot(entries: [TestSupport.income(1000)],
                                            investments: [TestSupport.investment(100, in: .cdb)])
        #expect(isUnlocked("monthly-goal", in: snapshot))
    }
}
