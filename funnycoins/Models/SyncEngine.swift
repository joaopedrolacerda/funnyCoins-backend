import Foundation
import SwiftData

// MARK: - Requisição e resposta

/// Corpo de `POST /v1/sync`. Ver shared/API.md.
struct SyncRequest: Codable, Equatable {
    /// Cursor devolvido pela última sincronização, ou nil na primeira vez.
    var cursor: Int64?
    /// Registros alterados neste aparelho desde a última sincronização.
    var changes: [SyncRecord]
}

struct SyncResponse: Codable, Equatable {
    /// Novo cursor para guardar e enviar na próxima vez.
    var cursor: Int64
    /// Registros alterados no servidor desde o cursor enviado.
    var changes: [SyncRecord]
}

/// Canal de comunicação com o servidor. Nos testes é substituído por uma versão falsa.
protocol SyncTransport {
    func sync(_ request: SyncRequest) async throws -> SyncResponse
}

/// Onde o motor guarda o próprio progresso entre sincronizações.
protocol SyncStateStore: AnyObject {
    var cursor: Int64? { get set }
    var lastSyncedAt: Date? { get set }
}

/// Estado guardado em UserDefaults, usado no app.
final class UserDefaultsSyncState: SyncStateStore {
    private let defaults: UserDefaults
    private let cursorKey = "sync.cursor"
    private let lastSyncedKey = "sync.lastSyncedAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var cursor: Int64? {
        get { (defaults.object(forKey: cursorKey) as? NSNumber)?.int64Value }
        set { defaults.set(newValue.map(NSNumber.init(value:)), forKey: cursorKey) }
    }

    var lastSyncedAt: Date? {
        get { defaults.object(forKey: lastSyncedKey) as? Date }
        set { defaults.set(newValue, forKey: lastSyncedKey) }
    }
}

/// Estado em memória, para testes e previews.
final class InMemorySyncState: SyncStateStore {
    var cursor: Int64?
    var lastSyncedAt: Date?

    init(cursor: Int64? = nil, lastSyncedAt: Date? = nil) {
        self.cursor = cursor
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Resultado de uma sincronização.
struct SyncSummary: Equatable {
    /// Registros enviados ao servidor.
    var pushed: Int
    /// Registros do servidor aplicados aqui.
    var applied: Int
    /// Registros do servidor ignorados por serem mais antigos que a versão local.
    var ignored: Int
}

// MARK: - Motor

/// Sincroniza os dados locais com o servidor.
///
/// Regra de conflito: vence a alteração mais recente (`updatedAt`). Em empate, a versão local é mantida.
/// O servidor aplica a mesma regra, então todos os aparelhos convergem para o mesmo estado.
final class SyncEngine {
    private let context: ModelContext
    private let transport: any SyncTransport
    private let state: any SyncStateStore

    init(context: ModelContext, transport: any SyncTransport, state: any SyncStateStore) {
        self.context = context
        self.transport = transport
        self.state = state
    }

    @discardableResult
    func sync(now: Date = .now) async throws -> SyncSummary {
        // Marca o início: alterações feitas durante a sincronização serão enviadas na próxima.
        let startedAt = now.syncPrecision
        let changes = try pendingChanges()

        let response = try await transport.sync(SyncRequest(cursor: state.cursor, changes: changes))

        var applied = 0
        var ignored = 0
        for record in response.changes {
            if try merge(record) {
                applied += 1
            } else {
                ignored += 1
            }
        }
        try context.save()

        // Só avança o estado depois de tudo aplicado e salvo.
        state.cursor = response.cursor
        state.lastSyncedAt = startedAt
        return SyncSummary(pushed: changes.count, applied: applied, ignored: ignored)
    }

    /// Registros alterados desde a última sincronização, incluindo exclusões.
    func pendingChanges() throws -> [SyncRecord] {
        try collect(PlayerProfile.self)
            + collect(CashEntry.self)
            + collect(Bill.self)
            + collect(ReserveMovement.self)
            + collect(Investment.self)
    }

    private func collect<Model: SyncRecordConvertible>(_ type: Model.Type) throws -> [SyncRecord] {
        let lastSyncedAt = state.lastSyncedAt
        return try context.fetch(FetchDescriptor<Model>())
            .filter { model in lastSyncedAt.map { model.updatedAt > $0 } ?? true }
            .map(\.syncRecord)
    }

    /// Aplica um registro do servidor. Retorna false quando ele foi ignorado.
    private func merge(_ record: SyncRecord) throws -> Bool {
        switch record.kind {
        case .profile: try merge(record, as: PlayerProfile.self)
        case .cashEntry: try merge(record, as: CashEntry.self)
        case .bill: try merge(record, as: Bill.self)
        case .reserveMovement: try merge(record, as: ReserveMovement.self)
        case .investment: try merge(record, as: Investment.self)
        }
    }

    private func merge<Model: SyncRecordConvertible>(_ record: SyncRecord, as type: Model.Type) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Model>()).first { $0.syncID == record.id }

        guard let existing else {
            // Registro novo vindo de outro aparelho.
            guard let model = Model.make(from: record) else { return false }
            context.insert(model)
            return true
        }

        // A versão local é mais nova ou igual: mantém a local.
        guard record.updatedAt > existing.updatedAt else { return false }

        existing.apply(record.data)
        existing.updatedAt = record.updatedAt
        existing.deletedAt = record.deletedAt
        return true
    }
}

// MARK: - Manutenção

enum SyncMaintenance {
    /// Garante que cada registro tenha um `syncID` único.
    ///
    /// Quando o SwiftData migra registros antigos, ele pode dar o mesmo UUID padrão a todos.
    /// Sem esta correção, o servidor trataria registros diferentes como se fossem um só.
    /// Retorna quantos registros receberam um identificador novo.
    @discardableResult
    static func repairDuplicateIDs(in context: ModelContext) throws -> Int {
        let repaired = try repair(PlayerProfile.self, in: context)
            + repair(CashEntry.self, in: context)
            + repair(Bill.self, in: context)
            + repair(ReserveMovement.self, in: context)
            + repair(Investment.self, in: context)
        if repaired > 0 {
            try context.save()
        }
        return repaired
    }

    private static func repair<Model: Syncable>(_ type: Model.Type, in context: ModelContext) throws -> Int {
        var seen = Set<UUID>()
        var repaired = 0
        for model in try context.fetch(FetchDescriptor<Model>()) where !seen.insert(model.syncID).inserted {
            model.syncID = UUID()
            seen.insert(model.syncID)
            model.touch()
            repaired += 1
        }
        return repaired
    }
}
