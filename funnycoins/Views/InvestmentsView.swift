import SwiftUI
import SwiftData

/// Nível 2: aportes em várias modalidades. Bloqueado até a reserva estar completa.
struct InvestmentsView: View {
    @Query(filter: Investment.active, sort: \Investment.date, order: .reverse) private var investments: [Investment]

    let snapshot: GameSnapshot

    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.isLevel1Complete {
                    unlockedContent
                } else {
                    ContentUnavailableView {
                        Label("Nível 2 bloqueado", systemImage: "lock.fill")
                    } description: {
                        Text("Complete sua reserva de emergência primeiro. Faltam \(snapshot.reserveMissing.brl).")
                    } actions: {
                        ProgressView(value: snapshot.reserveProgress)
                            .frame(maxWidth: 220)
                            .tint(.green)
                    }
                }
            }
            .navigationTitle("Investimentos")
            .toolbar {
                if snapshot.isLevel1Complete {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Novo aporte", systemImage: "plus") { isAdding = true }
                    }
                }
            }
            .sheet(isPresented: $isAdding) { InvestmentFormView() }
        }
    }

    private var unlockedContent: some View {
        List {
            Section("Meta do mês") {
                LabeledContent("Investir \(snapshot.profile.investPercent)% das entradas",
                               value: snapshot.monthlyInvestTarget.brl)
                LabeledContent("Aportado no mês", value: snapshot.investedThisMonth.brl)
                ProgressView(value: snapshot.monthlyInvestProgress).tint(.blue)
            }

            if !snapshot.allocation.isEmpty {
                Section("Carteira • \(snapshot.investedTotal.brl)") {
                    ForEach(snapshot.allocation, id: \.modality) { item in
                        let share = snapshot.investedTotal > 0
                            ? (item.amount / snapshot.investedTotal).doubleValue : 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(item.modality.title, systemImage: item.modality.symbol)
                                Spacer()
                                Text(item.amount.brl).monospacedDigit()
                            }
                            ProgressView(value: share)
                            Text("\(share, format: .percent.precision(.fractionLength(0))) • \(item.modality.riskTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Aportes") {
                if investments.isEmpty {
                    Text("Escolha uma modalidade e registre seu primeiro aporte.")
                        .foregroundStyle(.secondary)
                }
                ForEach(investments) { investment in
                    HStack {
                        Image(systemName: investment.modality.symbol).frame(width: 32)
                        VStack(alignment: .leading) {
                            Text(investment.name)
                            Text("\(investment.modality.title) • \(investment.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(investment.amount.brl).monospacedDigit()
                    }
                    .swipeActions {
                        Button("Apagar", systemImage: "trash", role: .destructive) {
                            investment.softDelete()
                        }
                    }
                }
            }
        }
    }
}
