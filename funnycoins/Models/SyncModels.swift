import Foundation
import SwiftData

// MARK: - Registro sincronizável

/// Modelo que pode ser sincronizado com o servidor.
/// Exclusões são "suaves": o registro fica marcado em `deletedAt` para a exclusão chegar aos outros aparelhos.
protocol Syncable: PersistentModel {
    var syncID: UUID { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension Syncable {
    /// Marca o registro como alterado. Chame sempre que editar um registro existente.
    func touch(at date: Date = .now) {
        updatedAt = date.syncPrecision
    }

    /// Exclui de forma sincronizável. As telas escondem registros com `deletedAt`.
    func softDelete(at date: Date = .now) {
        deletedAt = date.syncPrecision
        touch(at: date)
    }

    var isSoftDeleted: Bool { deletedAt != nil }
}

extension Date {
    /// Datas viajam em milissegundos. Truncar aqui evita que o mesmo registro pareça diferente após ida e volta.
    var syncPrecision: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }
}

extension Decimal {
    /// Valor em centavos, arredondado. É assim que o dinheiro trafega e fica no banco do servidor.
    var cents: Int64 {
        var value = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    init(cents: Int64) {
        self = Decimal(cents) / 100
    }
}

// MARK: - Registros ativos

// Filtros usados pelas telas para esconder registros excluídos.
extension CashEntry {
    static var active: Predicate<CashEntry> { #Predicate { $0.deletedAt == nil } }
}

extension Bill {
    static var active: Predicate<Bill> { #Predicate { $0.deletedAt == nil } }
}

extension ReserveMovement {
    static var active: Predicate<ReserveMovement> { #Predicate { $0.deletedAt == nil } }
}

extension Investment {
    static var active: Predicate<Investment> { #Predicate { $0.deletedAt == nil } }
}

// MARK: - Contrato com o servidor

/// Tipo de registro no contrato de sincronização. Os valores crus fazem parte da API: não renomeie.
enum SyncKind: String, Codable, CaseIterable {
    case profile, cashEntry, bill, reserveMovement, investment
}

struct ProfileData: Codable, Equatable {
    var monthlyEssentialCostCents: Int64
    var targetMonths: Int
    var investPercent: Int
    var petName: String
    var petColor: String
    var createdAt: Date
}

struct CashEntryData: Codable, Equatable {
    var title: String
    var amountCents: Int64
    var date: Date
    var kind: String
    var category: String
}

struct BillData: Codable, Equatable {
    var name: String
    var amountCents: Int64
    var dueDay: Int
    var paidMonths: [String]
    var createdAt: Date
}

struct ReserveMovementData: Codable, Equatable {
    /// Positivo para depósito, negativo para retirada.
    var amountCents: Int64
    var date: Date
    var note: String
}

struct InvestmentData: Codable, Equatable {
    var name: String
    var modality: String
    var amountCents: Int64
    var date: Date
}

/// Conteúdo de um registro, de acordo com o tipo.
enum SyncData: Equatable {
    case profile(ProfileData)
    case cashEntry(CashEntryData)
    case bill(BillData)
    case reserveMovement(ReserveMovementData)
    case investment(InvestmentData)

    var kind: SyncKind {
        switch self {
        case .profile: .profile
        case .cashEntry: .cashEntry
        case .bill: .bill
        case .reserveMovement: .reserveMovement
        case .investment: .investment
        }
    }
}

/// Um registro como trafega na API: `{ id, kind, updatedAt, deletedAt, data }`.
struct SyncRecord: Codable, Equatable {
    var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var data: SyncData

    var kind: SyncKind { data.kind }

    private enum CodingKeys: String, CodingKey {
        case id, kind, updatedAt, deletedAt, data
    }

    init(id: UUID, updatedAt: Date, deletedAt: Date?, data: SyncData) {
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.data = data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        switch try container.decode(SyncKind.self, forKey: .kind) {
        case .profile: data = .profile(try container.decode(ProfileData.self, forKey: .data))
        case .cashEntry: data = .cashEntry(try container.decode(CashEntryData.self, forKey: .data))
        case .bill: data = .bill(try container.decode(BillData.self, forKey: .data))
        case .reserveMovement: data = .reserveMovement(try container.decode(ReserveMovementData.self, forKey: .data))
        case .investment: data = .investment(try container.decode(InvestmentData.self, forKey: .data))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        switch data {
        case .profile(let value): try container.encode(value, forKey: .data)
        case .cashEntry(let value): try container.encode(value, forKey: .data)
        case .bill(let value): try container.encode(value, forKey: .data)
        case .reserveMovement(let value): try container.encode(value, forKey: .data)
        case .investment(let value): try container.encode(value, forKey: .data)
        }
    }
}

/// Codificação JSON usada na API: datas em milissegundos desde 1970.
enum SyncJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

// MARK: - Conversão entre modelos e registros

/// Modelo que sabe se transformar em registro da API e vice-versa.
protocol SyncRecordConvertible: Syncable {
    static var syncKind: SyncKind { get }
    var syncData: SyncData { get }
    /// Cria um modelo novo a partir de um registro vindo do servidor. Retorna nil se o tipo não bater.
    static func make(from record: SyncRecord) -> Self?
    /// Aplica os campos de um registro vindo do servidor.
    func apply(_ data: SyncData)
}

extension SyncRecordConvertible {
    var syncRecord: SyncRecord {
        SyncRecord(id: syncID, updatedAt: updatedAt.syncPrecision, deletedAt: deletedAt?.syncPrecision, data: syncData)
    }

    /// Copia identidade e metadados de sincronização do registro.
    fileprivate func adoptMetadata(of record: SyncRecord) {
        syncID = record.id
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
    }
}

extension PlayerProfile: SyncRecordConvertible {
    static var syncKind: SyncKind { .profile }

    var syncData: SyncData {
        .profile(ProfileData(monthlyEssentialCostCents: monthlyEssentialCost.cents,
                             targetMonths: targetMonths, investPercent: investPercent,
                             petName: petName, petColor: petColorRaw, createdAt: createdAt.syncPrecision))
    }

    static func make(from record: SyncRecord) -> PlayerProfile? {
        guard case .profile = record.data else { return nil }
        let profile = PlayerProfile(monthlyEssentialCost: 0)
        profile.apply(record.data)
        profile.adoptMetadata(of: record)
        return profile
    }

    func apply(_ data: SyncData) {
        guard case .profile(let value) = data else { return }
        monthlyEssentialCost = Decimal(cents: value.monthlyEssentialCostCents)
        targetMonths = value.targetMonths
        investPercent = value.investPercent
        petName = value.petName
        petColorRaw = value.petColor
        createdAt = value.createdAt
    }
}

extension CashEntry: SyncRecordConvertible {
    static var syncKind: SyncKind { .cashEntry }

    var syncData: SyncData {
        .cashEntry(CashEntryData(title: title, amountCents: amount.cents, date: date.syncPrecision,
                                 kind: kindRaw, category: categoryRaw))
    }

    static func make(from record: SyncRecord) -> CashEntry? {
        guard case .cashEntry = record.data else { return nil }
        let entry = CashEntry(title: "", amount: 0, category: .otherExpense)
        entry.apply(record.data)
        entry.adoptMetadata(of: record)
        return entry
    }

    func apply(_ data: SyncData) {
        guard case .cashEntry(let value) = data else { return }
        title = value.title
        amount = Decimal(cents: value.amountCents)
        date = value.date
        kindRaw = value.kind
        categoryRaw = value.category
    }
}

extension Bill: SyncRecordConvertible {
    static var syncKind: SyncKind { .bill }

    var syncData: SyncData {
        .bill(BillData(name: name, amountCents: amount.cents, dueDay: dueDay,
                       paidMonths: paidMonthKeys, createdAt: createdAt.syncPrecision))
    }

    static func make(from record: SyncRecord) -> Bill? {
        guard case .bill = record.data else { return nil }
        let bill = Bill(name: "", amount: 0, dueDay: 1)
        bill.apply(record.data)
        bill.adoptMetadata(of: record)
        return bill
    }

    func apply(_ data: SyncData) {
        guard case .bill(let value) = data else { return }
        name = value.name
        amount = Decimal(cents: value.amountCents)
        dueDay = value.dueDay
        paidMonthKeys = value.paidMonths
        createdAt = value.createdAt
    }
}

extension ReserveMovement: SyncRecordConvertible {
    static var syncKind: SyncKind { .reserveMovement }

    var syncData: SyncData {
        .reserveMovement(ReserveMovementData(amountCents: amount.cents, date: date.syncPrecision, note: note))
    }

    static func make(from record: SyncRecord) -> ReserveMovement? {
        guard case .reserveMovement = record.data else { return nil }
        let movement = ReserveMovement(amount: 0)
        movement.apply(record.data)
        movement.adoptMetadata(of: record)
        return movement
    }

    func apply(_ data: SyncData) {
        guard case .reserveMovement(let value) = data else { return }
        amount = Decimal(cents: value.amountCents)
        date = value.date
        note = value.note
    }
}

extension Investment: SyncRecordConvertible {
    static var syncKind: SyncKind { .investment }

    var syncData: SyncData {
        .investment(InvestmentData(name: name, modality: modalityRaw, amountCents: amount.cents,
                                   date: date.syncPrecision))
    }

    static func make(from record: SyncRecord) -> Investment? {
        guard case .investment = record.data else { return nil }
        let investment = Investment(name: "", modality: .other, amount: 0)
        investment.apply(record.data)
        investment.adoptMetadata(of: record)
        return investment
    }

    func apply(_ data: SyncData) {
        guard case .investment(let value) = data else { return }
        name = value.name
        modalityRaw = value.modality
        amount = Decimal(cents: value.amountCents)
        date = value.date
    }
}
