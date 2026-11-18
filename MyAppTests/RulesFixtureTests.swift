import Foundation
import Testing
@testable import MyApp

/// Formato de MyAppTests/Fixtures/rules-fixtures.json.
/// O mesmo arquivo será lido pelos testes do backend em Rust, para as regras não divergirem.
struct RulesFixtureFile: Decodable {
    let version: Int
    let cases: [RulesFixture]
}

struct RulesFixture: Decodable, CustomTestStringConvertible {
    struct Profile: Decodable {
        let monthlyEssentialCostCents: Int64
        let targetMonths: Int
        let investPercent: Int
    }

    struct Entry: Decodable {
        let category: String
        let amountCents: Int64
        let date: String
    }

    struct BillInput: Decodable {
        let name: String
        let amountCents: Int64
        let dueDay: Int
        let paidMonths: [String]
    }

    struct Movement: Decodable {
        let amountCents: Int64
        let date: String
    }

    struct InvestmentInput: Decodable {
        let modality: String
        let amountCents: Int64
        let date: String
    }

    struct Expected: Decodable {
        let reserveGoalCents: Int64
        let reserveBalanceCents: Int64
        let reserveProgress: Double
        let currentLevel: Int
        let xp: Int
        let rank: String
        let achievements: [String]
        let petStage: String
        let petMood: String
    }

    let name: String
    let now: String
    let profile: Profile
    let entries: [Entry]
    let bills: [BillInput]
    let reserveMovements: [Movement]
    let investments: [InvestmentInput]
    let expected: Expected

    var testDescription: String { name }
}

/// Token para achar o bundle de testes, onde o JSON é copiado como recurso.
private final class FixtureBundleToken {}

enum RulesFixtures {
    static func load() throws -> [RulesFixture] {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: "rules-fixtures", withExtension: "json") else {
            return []
        }
        return try JSONDecoder().decode(RulesFixtureFile.self, from: Data(contentsOf: url)).cases
    }

    /// Converte "aaaa-mm-dd" para o meio-dia local, como nos outros testes.
    static func date(_ text: String) throws -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        try #require(parts.count == 3, "Data inválida no fixture: \(text)")
        return TestSupport.date(parts[0], parts[1], parts[2])
    }

    static func snapshot(for fixture: RulesFixture) throws -> GameSnapshot {
        let entries = try fixture.entries.map { input in
            let category = try #require(EntryCategory(rawValue: input.category), "Categoria desconhecida: \(input.category)")
            return CashEntry(title: category.title, amount: Decimal(cents: input.amountCents),
                             date: try date(input.date), category: category)
        }
        let bills = fixture.bills.map { input in
            let bill = Bill(name: input.name, amount: Decimal(cents: input.amountCents), dueDay: input.dueDay)
            bill.paidMonthKeys = input.paidMonths
            return bill
        }
        let movements = try fixture.reserveMovements.map {
            ReserveMovement(amount: Decimal(cents: $0.amountCents), date: try date($0.date))
        }
        let investments = try fixture.investments.map { input in
            let modality = try #require(InvestmentModality(rawValue: input.modality), "Modalidade desconhecida: \(input.modality)")
            return Investment(name: modality.title, modality: modality,
                              amount: Decimal(cents: input.amountCents), date: try date(input.date))
        }
        return TestSupport.snapshot(
            monthlyCost: Decimal(cents: fixture.profile.monthlyEssentialCostCents),
            targetMonths: fixture.profile.targetMonths,
            investPercent: fixture.profile.investPercent,
            entries: entries, bills: bills, reserve: movements, investments: investments,
            now: try date(fixture.now))
    }
}

@Suite("Regras compartilhadas com o backend")
struct RulesFixtureTests {
    @Test("O arquivo de casos compartilhados existe e tem casos")
    func fixturesAreBundled() throws {
        let fixtures = try RulesFixtures.load()
        #expect(fixtures.count >= 5)
    }

    @Test("O app calcula exatamente o que os casos compartilhados esperam", arguments: try RulesFixtures.load())
    func matchesFixture(_ fixture: RulesFixture) throws {
        let snapshot = try RulesFixtures.snapshot(for: fixture)
        let expected = fixture.expected

        #expect(snapshot.reserveGoal.cents == expected.reserveGoalCents)
        #expect(snapshot.reserveBalance.cents == expected.reserveBalanceCents)
        #expect(abs(snapshot.reserveProgress - expected.reserveProgress) < 0.0001)
        #expect(snapshot.currentLevel == expected.currentLevel)
        #expect(snapshot.xp == expected.xp)
        #expect(snapshot.rankTitle == expected.rank)
        #expect(snapshot.achievements.filter(\.isUnlocked).map(\.id) == expected.achievements)
        #expect("\(snapshot.petStage)" == expected.petStage)
        #expect("\(snapshot.petMood)" == expected.petMood)
    }
}
