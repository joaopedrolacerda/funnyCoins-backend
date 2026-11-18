import SwiftUI
import SwiftData

/// Passo a passo amigável para registrar um ganho, em slides:
/// origem → valor → quanto guardar/investir → comemoração.
struct GainWizardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let snapshot: GameSnapshot

    private enum Step: Int, CaseIterable {
        case source, amount, split, done
    }

    @State private var step: Step = .source
    @State private var isMovingForward = true
    @State private var category: EntryCategory = .salary
    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var splitPercent = 0
    @State private var modality: InvestmentModality = .tesouroSelic
    @State private var earnedXP = 0
    @State private var didUnlockLevel2 = false
    @State private var celebrate = false
    /// Resultado congelado no momento de salvar, pois o snapshot muda logo depois.
    @State private var savedSplit: Decimal = 0
    @State private var savedToInvestments = false

    /// No Nível 1 a parte separada vai para a reserva; no Nível 2, para investimentos.
    private var isInvesting: Bool { snapshot.isLevel1Complete }

    private var splitAmount: Decimal {
        snapshot.suggestedSplit(of: amount, percent: splitPercent)
    }

    private var percentOptions: [Int] {
        let base = [0, 10, 20, 30, 50]
        return isInvesting ? Array(Set(base + [snapshot.profile.investPercent])).sorted() : base
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                StepDots(count: Step.allCases.count, current: step.rawValue)

                Group {
                    switch step {
                    case .source: sourceStep
                    case .amount: amountStep
                    case .split: splitStep
                    case .done: doneStep
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                bottomBar
            }
            .padding()
            .clipped()
            .navigationTitle("Novo ganho")
            .toolbar {
                if step != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
            }
            .onAppear {
                splitPercent = isInvesting ? snapshot.profile.investPercent : 20
            }
        }
        .sheetFrame()
    }

    // MARK: Passo 1 - origem

    private var sourceStep: some View {
        VStack(spacing: 20) {
            StepTitle(symbol: "dollarsign.circle.fill", tint: .green,
                      title: "De onde veio esse dinheiro?",
                      subtitle: "Registre cada ganho separado para enxergar todas as suas fontes de renda.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(EntryCategory.cases(for: .income)) { item in
                    Button {
                        category = item
                        go(to: .amount)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.symbol).font(.title)
                            Text(item.title).font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .background(.green.opacity(0.12), in: .rect(cornerRadius: 16))
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Passo 2 - valor

    private var amountStep: some View {
        VStack(spacing: 20) {
            StepTitle(symbol: category.symbol, tint: .green,
                      title: "Quanto você recebeu?",
                      subtitle: category.title)

            TextField("Valor", value: $amount, format: BRFormat.currency)
                .decimalKeyboard()
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)

            TextField("Descrição (opcional), ex: Salário outubro", text: $note)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Passo 3 - separar uma parte

    private var splitStep: some View {
        VStack(spacing: 20) {
            if isInvesting {
                StepTitle(symbol: "chart.line.uptrend.xyaxis", tint: .blue,
                          title: "Hora de investir uma parte!",
                          subtitle: "Sua meta é investir \(snapshot.profile.investPercent)% de cada ganho.")
            } else {
                StepTitle(symbol: "shield.fill", tint: .orange,
                          title: "Quer guardar uma parte na reserva?",
                          subtitle: "Faltam \(snapshot.reserveMissing.brl) para completar o Nível 1.")
            }

            HStack(spacing: 8) {
                ForEach(percentOptions, id: \.self) { option in
                    Button {
                        splitPercent = option
                    } label: {
                        Text(option == 0 ? "Agora não" : "\(option)%")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(splitPercent == option ? Color.accentColor : Color.secondary.opacity(0.15),
                                        in: .capsule)
                            .foregroundStyle(splitPercent == option ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if splitAmount > 0 {
                VStack(spacing: 4) {
                    Text(isInvesting ? "Vai para investimentos" : "Vai para a reserva")
                        .foregroundStyle(.secondary)
                    Text(splitAmount.brl)
                        .font(.title.bold())
                        .contentTransition(.numericText())
                    Text("Fica livre: \((amount - splitAmount).brl)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .animation(.default, value: splitAmount)

                if isInvesting {
                    Picker("Onde investir", selection: $modality) {
                        ForEach(InvestmentModality.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: Passo 4 - comemoração

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: didUnlockLevel2 ? "lock.open.fill" : "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce, value: celebrate)

            Text(didUnlockLevel2 ? "Nível 2 desbloqueado!" : "Ganho registrado!")
                .font(.title.bold())
            Text("+\(earnedXP) XP")
                .font(.title2.bold())
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                LabeledContent(category.title, value: amount.brl)
                if savedSplit > 0 {
                    LabeledContent(savedToInvestments ? "Investido em \(modality.title)" : "Guardado na reserva",
                                   value: savedSplit.brl)
                }
            }
            .card()

            if didUnlockLevel2 {
                Text("Sua reserva está completa. Agora você pode investir onde quiser!")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { celebrate.toggle() }
    }

    // MARK: Navegação

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if step == .amount || step == .split {
                Button("Voltar") { go(to: Step(rawValue: step.rawValue - 1) ?? .source) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Spacer()
            switch step {
            case .source:
                EmptyView()
            case .amount:
                Button("Próximo") { go(to: .split) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(amount <= 0)
            case .split:
                Button("Salvar ganho", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .done:
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func go(to newStep: Step) {
        isMovingForward = newStep.rawValue > step.rawValue
        withAnimation(.snappy) { step = newStep }
    }

    private func save() {
        let title = note.trimmingCharacters(in: .whitespaces).isEmpty ? category.title : note
        context.insert(CashEntry(title: title, amount: amount, category: category))
        var xp = 5
        savedSplit = splitAmount
        savedToInvestments = isInvesting

        if splitAmount > 0 {
            if isInvesting {
                context.insert(Investment(name: modality.title, modality: modality, amount: splitAmount))
                xp += 30
            } else {
                didUnlockLevel2 = splitAmount >= snapshot.reserveMissing
                context.insert(ReserveMovement(amount: splitAmount, note: "Do ganho: \(title)"))
                xp += 20
            }
        }
        earnedXP = xp
        go(to: .done)
    }
}

// MARK: - Componentes do passo a passo

private struct StepTitle: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Indicador de página em bolinhas.
struct StepDots: View {
    let count: Int
    let current: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .onTapGesture { onSelect?(index) }
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Página \(current + 1) de \(count)")
    }
}
