import SwiftUI
import SwiftData

/// Entradas e saídas de dinheiro.
struct CashFlowView: View {
    @Query(filter: CashEntry.active, sort: \CashEntry.date, order: .reverse) private var entries: [CashEntry]

    let snapshot: GameSnapshot

    @State private var isAddingExpense = false
    @State private var isAddingGain = false

    var body: some View {
        NavigationStack {
            List {
                Section("Este mês") {
                    LabeledContent("Entradas") {
                        Text(snapshot.monthIncome.brl).foregroundStyle(.green)
                    }
                    LabeledContent("Saídas") {
                        Text(snapshot.monthExpense.brl).foregroundStyle(.red)
                    }
                    LabeledContent("Resultado") {
                        Text((snapshot.monthIncome - snapshot.monthExpense).brl).bold()
                    }
                    LabeledContent("Saldo livre", value: snapshot.freeBalance.brl)
                }

                Section("Lançamentos") {
                    if entries.isEmpty {
                        Text("Nenhum lançamento ainda. Toque em + para registrar um ganho ou um gasto.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                            .swipeActions {
                                Button("Apagar", systemImage: "trash", role: .destructive) {
                                    entry.softDelete()
                                }
                            }
                    }
                }
            }
            .navigationTitle("Fluxo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Adicionar", systemImage: "plus") {
                        Button("Novo ganho", systemImage: "arrow.down.circle") { isAddingGain = true }
                        Button("Novo gasto", systemImage: "arrow.up.circle") { isAddingExpense = true }
                    }
                }
            }
            .sheet(isPresented: $isAddingExpense) { EntryFormView() }
            .sheet(isPresented: $isAddingGain) { GainWizardView(snapshot: snapshot) }
        }
    }
}

private struct EntryRow: View {
    let entry: CashEntry

    var body: some View {
        HStack {
            Image(systemName: entry.category.symbol)
                .frame(width: 32)
                .foregroundStyle(entry.kind == .income ? .green : .red)
            VStack(alignment: .leading) {
                Text(entry.title)
                Text("\(entry.category.title) • \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((entry.kind == .income ? entry.amount : -entry.amount).brl)
                .monospacedDigit()
                .foregroundStyle(entry.kind == .income ? .green : .primary)
        }
    }
}
