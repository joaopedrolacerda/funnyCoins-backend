import SwiftUI
import SwiftData

/// Contas fixas mensais com status de pagamento do mês atual.
struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: Bill.active, sort: \Bill.dueDay) private var bills: [Bill]

    @State private var isAdding = false

    private var monthTotal: Decimal { bills.reduce(0) { $0 + $1.amount } }
    private var paidTotal: Decimal { bills.filter { $0.isPaid() }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            List {
                if !bills.isEmpty {
                    Section {
                        LabeledContent("Total do mês", value: monthTotal.brl)
                        LabeledContent("Já pago", value: paidTotal.brl)
                        ProgressView(value: monthTotal > 0 ? (paidTotal / monthTotal).doubleValue : 0)
                            .tint(.green)
                    }
                }

                Section("Contas fixas") {
                    if bills.isEmpty {
                        Text("Cadastre aluguel, luz, internet e outras contas. Pagar em dia rende XP.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(bills) { bill in
                        BillRow(bill: bill) { pay(bill) }
                            .swipeActions {
                                Button("Apagar", systemImage: "trash", role: .destructive) {
                                    bill.softDelete()
                                }
                            }
                    }
                }
            }
            .navigationTitle("Contas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Adicionar", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) { BillFormView() }
        }
    }

    /// Marca a conta como paga no mês e registra a saída no fluxo.
    private func pay(_ bill: Bill) {
        bill.paidMonthKeys.append(Bill.monthKey(for: .now))
        bill.touch()
        context.insert(CashEntry(title: bill.name, amount: bill.amount, category: .bills))
    }
}

private struct BillRow: View {
    let bill: Bill
    let onPay: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bill.name)
                Text(bill.amount.brl).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if bill.isPaid() {
                Label("Paga", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(bill.isOverdue() ? "Atrasada" : "Vence dia \(bill.dueDay)")
                        .font(.caption)
                        .foregroundStyle(bill.isOverdue() ? .red : .secondary)
                    Button("Pagar", action: onPay)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}
