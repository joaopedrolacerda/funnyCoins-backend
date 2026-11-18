import Foundation
import SwiftData
import Testing
@testable import MyApp

/// Banco em memória para testes que precisam do SwiftData.
enum TestStore {
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PlayerProfile.self, CashEntry.self, Bill.self, ReserveMovement.self, Investment.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

/// Servidor falso: guarda o que recebeu e devolve uma resposta programada.
final class FakeTransport: SyncTransport {
    var requests: [SyncRequest] = []
    var response = SyncResponse(cursor: 1, changes: [])
    var error: (any Error)?

    func sync(_ request: SyncRequest) async throws -> SyncResponse {
        requests.append(request)
        if let error { throw error }
        return response
    }
}

private struct OfflineError: Error {}

@Suite("Campos de sincronização")
struct SyncFieldsTests {
    @Test("Cada registro novo nasce com identificador próprio e sem exclusão")
    func newRecordsHaveUniqueIDs() {
        let first = TestSupport.income(100)
        let second = TestSupport.income(100)
        #expect(first.syncID != second.syncID)
        #expect(first.deletedAt == nil)
        #expect(!first.isSoftDeleted)
    }

    @Test("Alterar atualiza a data com precisão de milissegundos")
    func touchUsesMilliseconds() {
        let entry = TestSupport.income(100)
        let moment = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        entry.touch(at: moment)
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 1_700_000_000.123))
    }

    @Test("Excluir só marca o registro e atualiza a data de alteração")
    func softDelete() {
        let entry = TestSupport.income(100)
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        entry.softDelete(at: moment)
        #expect(entry.isSoftDeleted)
        #expect(entry.deletedAt == moment)
        #expect(entry.updatedAt == moment)
    }

    @Test("As telas não enxergam registros excluídos")
    func activeFilterHidesDeleted() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let kept = TestSupport.income(100)
        let removed = TestSupport.income(200)
        context.insert(kept)
        context.insert(removed)
        removed.softDelete()
        try context.save()

        let visible = try context.fetch(FetchDescriptor(predicate: CashEntry.active))
        #expect(visible.map(\.syncID) == [kept.syncID])
        #expect(try context.fetchCount(FetchDescriptor<CashEntry>()) == 2)
    }

    @Test("O filtro de ativos vale para todos os tipos")
    func activeFilterForAllTypes() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let bill = Bill(name: "Luz", amount: 100, dueDay: 10)
        let movement = TestSupport.deposit(100)
        let investment = TestSupport.investment(100, in: .cdb)
        context.insert(bill)
        context.insert(movement)
        context.insert(investment)
        bill.softDelete()
        movement.softDelete()
        investment.softDelete()

        #expect(try context.fetch(FetchDescriptor(predicate: Bill.active)).isEmpty)
        #expect(try context.fetch(FetchDescriptor(predicate: ReserveMovement.active)).isEmpty)
        #expect(try context.fetch(FetchDescriptor(predicate: Investment.active)).isEmpty)
    }
}

@Suite("Dinheiro em centavos")
struct CentsTests {
    @Test("Converte reais para centavos", arguments: [
        (123_456, Int64(123_456)), (-5000, Int64(-5000)), (0, Int64(0)), (1, Int64(1))
    ])
    func toCents(cents: Int, expected: Int64) {
        #expect(TestSupport.reais(cents).cents == expected)
    }

    @Test("Frações de centavo são arredondadas")
    func roundsFractions() {
        // 10,005 vira 1.001 centavos; 10,004 vira 1.000.
        #expect((Decimal(10_005) / 1000).cents == 1001)
        #expect((Decimal(10_004) / 1000).cents == 1000)
    }

    @Test("Centavos voltam para o valor exato")
    func fromCents() {
        #expect(Decimal(cents: 123_456) == TestSupport.reais(123_456))
        #expect(Decimal(cents: -1) == TestSupport.reais(-1))
    }
}

@Suite("Formato da API")
struct SyncFormatTests {
    private func roundTrip(_ record: SyncRecord) throws -> SyncRecord {
        let data = try SyncJSON.encoder.encode(record)
        return try SyncJSON.decoder.decode(SyncRecord.self, from: data)
    }

    @Test("O JSON traz tipo, centavos e datas em milissegundos")
    func jsonShape() throws {
        let entry = CashEntry(title: "Salário", amount: TestSupport.reais(123_456),
                              date: Date(timeIntervalSince1970: 1_700_000_000), category: .salary)
        entry.touch(at: Date(timeIntervalSince1970: 1_700_000_001))
        let data = try SyncJSON.encoder.encode(entry.syncRecord)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try #require(json["data"] as? [String: Any])

        #expect(json["id"] as? String == entry.syncID.uuidString)
        #expect(json["kind"] as? String == "cashEntry")
        #expect((json["updatedAt"] as? NSNumber)?.int64Value == 1_700_000_001_000)
        #expect(json["deletedAt"] == nil)
        #expect((payload["amountCents"] as? NSNumber)?.int64Value == 123_456)
        #expect(payload["kind"] as? String == "income")
        #expect(payload["category"] as? String == "salary")
    }

    @Test("Todos os tipos fazem ida e volta pelo JSON sem perder nada")
    func allKindsRoundTrip() throws {
        let profile = PlayerProfile(monthlyEssentialCost: TestSupport.reais(250_050), targetMonths: 9,
                                    investPercent: 15, petName: "Bolota", petColor: .purple)
        let bill = Bill(name: "Internet", amount: 120, dueDay: 7)
        bill.paidMonthKeys = ["2026-09", "2026-10"]
        let movement = ReserveMovement(amount: -300, note: "Dentista")
        let investment = TestSupport.investment(TestSupport.reais(99_990), in: .education)
        let entry = TestSupport.expense(TestSupport.reais(4_590))
        investment.softDelete(at: Date(timeIntervalSince1970: 1_700_000_000))

        let records = [profile.syncRecord, entry.syncRecord, bill.syncRecord,
                       movement.syncRecord, investment.syncRecord]
        #expect(Set(records.map(\.kind)) == Set(SyncKind.allCases))
        for record in records {
            #expect(try roundTrip(record) == record)
        }
    }

    @Test("Modelo criado a partir do registro é igual ao original")
    func modelRoundTrip() throws {
        let bill = Bill(name: "Aluguel", amount: 1500, dueDay: 5)
        bill.paidMonthKeys = ["2026-10"]
        let record = bill.syncRecord
        let copy = try #require(Bill.make(from: record))
        #expect(copy.syncRecord == record)
        #expect(copy.isPaid(in: TestSupport.today))
    }

    @Test("Registro de outro tipo não vira modelo")
    func wrongKindIsRejected() {
        let record = TestSupport.income(100).syncRecord
        #expect(Bill.make(from: record) == nil)
        #expect(CashEntry.make(from: record) != nil)
    }

    @Test("JSON com tipo e conteúdo incompatíveis é recusado")
    func mismatchedJSONFails() throws {
        let data = try SyncJSON.encoder.encode(TestSupport.income(100).syncRecord)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["kind"] = "bill"
        let tampered = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            try SyncJSON.decoder.decode(SyncRecord.self, from: tampered)
        }
    }
}

@Suite("Motor de sincronização")
struct SyncEngineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A primeira sincronização envia tudo e guarda o cursor")
    func firstSyncPushesEverything() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        context.insert(PlayerProfile(monthlyEssentialCost: 1000))
        context.insert(TestSupport.income(5000))
        context.insert(Bill(name: "Luz", amount: 200, dueDay: 10))
        let transport = FakeTransport()
        transport.response = SyncResponse(cursor: 42, changes: [])
        let state = InMemorySyncState()

        let summary = try await SyncEngine(context: context, transport: transport, state: state).sync(now: start)

        #expect(summary == SyncSummary(pushed: 3, applied: 0, ignored: 0))
        #expect(transport.requests.first?.cursor == nil)
        #expect(Set(transport.requests.first?.changes.map(\.kind) ?? []) == [.profile, .cashEntry, .bill])
        #expect(state.cursor == 42)
        #expect(state.lastSyncedAt == start)
    }

    @Test("Depois envia só o que mudou, incluindo exclusões")
    func laterSyncPushesOnlyChanges() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let kept = TestSupport.income(100)
        let edited = TestSupport.income(200)
        let removed = TestSupport.income(300)
        [kept, edited, removed].forEach(context.insert)
        let transport = FakeTransport()
        let state = InMemorySyncState()
        let engine = SyncEngine(context: context, transport: transport, state: state)
        try await engine.sync(now: start)

        edited.amount = 250
        edited.touch(at: start.addingTimeInterval(10))
        removed.softDelete(at: start.addingTimeInterval(20))
        try await engine.sync(now: start.addingTimeInterval(30))

        let second = try #require(transport.requests.last)
        #expect(second.cursor == 1)
        #expect(Set(second.changes.map(\.id)) == [edited.syncID, removed.syncID])
        #expect(second.changes.first { $0.id == removed.syncID }?.deletedAt != nil)
    }

    @Test("Sem alterações, não envia nada")
    func nothingToPush() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        context.insert(TestSupport.income(100))
        let transport = FakeTransport()
        let engine = SyncEngine(context: context, transport: transport, state: InMemorySyncState())
        try await engine.sync(now: start)
        let summary = try await engine.sync(now: start.addingTimeInterval(5))
        #expect(summary.pushed == 0)
        #expect(transport.requests.last?.changes.isEmpty == true)
    }

    @Test("Registro novo de outro aparelho é criado aqui")
    func insertsRemoteRecord() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let remote = CashEntry(title: "Freela", amount: 800, date: TestSupport.today, category: .freelance)
        remote.touch(at: start)
        let transport = FakeTransport()
        transport.response = SyncResponse(cursor: 2, changes: [remote.syncRecord])

        let summary = try await SyncEngine(context: context, transport: transport, state: InMemorySyncState())
            .sync(now: start)

        let local = try context.fetch(FetchDescriptor<CashEntry>())
        #expect(summary.applied == 1)
        #expect(local.count == 1)
        #expect(local.first?.syncID == remote.syncID)
        #expect(local.first?.amount == 800)
        #expect(local.first?.category == .freelance)
    }

    @Test("Vence a alteração mais recente; em empate, fica a local", arguments: [
        (10.0, true), (-10.0, false), (0.0, false)
    ])
    func lastWriteWins(remoteOffset: TimeInterval, remoteWins: Bool) async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let local = TestSupport.income(100)
        local.touch(at: start)
        context.insert(local)

        let remoteVersion = try #require(CashEntry.make(from: local.syncRecord))
        remoteVersion.amount = 999
        remoteVersion.touch(at: start.addingTimeInterval(remoteOffset))
        let transport = FakeTransport()
        transport.response = SyncResponse(cursor: 3, changes: [remoteVersion.syncRecord])
        let state = InMemorySyncState(lastSyncedAt: start.addingTimeInterval(60))

        let summary = try await SyncEngine(context: context, transport: transport, state: state)
            .sync(now: start.addingTimeInterval(60))

        #expect(local.amount == (remoteWins ? 999 : 100))
        #expect(summary.applied == (remoteWins ? 1 : 0))
        #expect(summary.ignored == (remoteWins ? 0 : 1))
    }

    @Test("Exclusão feita em outro aparelho some daqui também")
    func appliesRemoteDeletion() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let local = TestSupport.investment(500, in: .cdb)
        local.touch(at: start)
        context.insert(local)

        let remoteVersion = try #require(Investment.make(from: local.syncRecord))
        remoteVersion.softDelete(at: start.addingTimeInterval(5))
        let transport = FakeTransport()
        transport.response = SyncResponse(cursor: 4, changes: [remoteVersion.syncRecord])

        try await SyncEngine(context: context, transport: transport, state: InMemorySyncState(lastSyncedAt: start))
            .sync(now: start.addingTimeInterval(10))

        #expect(local.isSoftDeleted)
        #expect(try context.fetch(FetchDescriptor(predicate: Investment.active)).isEmpty)
    }

    @Test("Sem conexão, nada é perdido e o estado não avança")
    func failureKeepsState() async throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        context.insert(TestSupport.income(100))
        let transport = FakeTransport()
        transport.error = OfflineError()
        let state = InMemorySyncState(cursor: 7, lastSyncedAt: nil)
        let engine = SyncEngine(context: context, transport: transport, state: state)

        await #expect(throws: OfflineError.self) {
            try await engine.sync(now: start)
        }
        #expect(state.cursor == 7)
        #expect(state.lastSyncedAt == nil)
        #expect(try engine.pendingChanges().count == 1)
    }
}

@Suite("Correção de identificadores")
struct SyncMaintenanceTests {
    @Test("Identificadores repetidos ganham um novo, sem tocar nos únicos")
    func repairsDuplicates() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        let shared = UUID()
        let entries = (0..<3).map { _ in TestSupport.income(100) }
        entries.forEach { $0.syncID = shared }
        let unique = TestSupport.income(100)
        let uniqueID = unique.syncID
        (entries + [unique]).forEach(context.insert)

        let repaired = try SyncMaintenance.repairDuplicateIDs(in: context)

        let ids = try context.fetch(FetchDescriptor<CashEntry>()).map(\.syncID)
        #expect(repaired == 2)
        #expect(Set(ids).count == 4)
        #expect(ids.contains(shared))
        #expect(unique.syncID == uniqueID)
    }

    @Test("Sem repetidos, nada muda")
    func noDuplicates() throws {
        let container = try TestStore.makeContainer()
        let context = container.mainContext
        context.insert(TestSupport.income(100))
        context.insert(Bill(name: "Luz", amount: 100, dueDay: 1))
        #expect(try SyncMaintenance.repairDuplicateIDs(in: context) == 0)
    }
}
