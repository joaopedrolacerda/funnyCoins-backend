import SwiftUI
import SwiftData

// MARK: - Perfil

/// Configuração do jogador. Usado no onboarding e para editar o perfil.
struct ProfileFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Perfil existente para editar, ou nil para criar um novo.
    let profile: PlayerProfile?

    @State private var monthlyCost: Decimal = 0
    @State private var targetMonths = 6
    @State private var investPercent = 10
    @State private var petName = "Moedinha"
    @State private var petColor: PetColor = .green

    private var goal: Decimal { monthlyCost * Decimal(targetMonths) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PetView(stage: .baby, mood: .happy, color: petColor.color, size: 120)
                    Spacer()
                }
                TextField("Nome do bichinho", text: $petName)
                HStack(spacing: 12) {
                    ForEach(PetColor.allCases) { option in
                        Button {
                            petColor = option
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if option == petColor {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(option == petColor ? .isSelected : [])
                    }
                }
            } header: {
                Text("Seu bichinho")
            } footer: {
                Text("Ele cresce e fica feliz conforme você cuida bem do seu dinheiro.")
            }

            Section {
                CurrencyField(title: "Custo de vida mensal", value: $monthlyCost)
            } header: {
                Text("Quanto você gasta por mês com o essencial?")
            } footer: {
                Text("Some moradia, alimentação, transporte, saúde e contas fixas.")
            }

            Section {
                Stepper("\(targetMonths) meses de reserva", value: $targetMonths, in: 3...24)
                LabeledContent("Meta do Nível 1", value: goal.brl)
            } header: {
                Text("Nível 1: Reserva de emergência")
            } footer: {
                Text("O recomendado é entre 6 e 12 meses do seu custo de vida.")
            }

            Section {
                Stepper("Investir \(investPercent)% das entradas", value: $investPercent, in: 5...80, step: 5)
            } header: {
                Text("Nível 2: Investimentos")
            } footer: {
                Text("Liberado quando a reserva estiver completa.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile == nil ? "Comece sua jornada" : "Editar perfil")
        .toolbar {
            if profile != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(profile == nil ? "Começar" : "Salvar", action: save)
                    .disabled(monthlyCost <= 0)
            }
        }
        .onAppear {
            if let profile {
                monthlyCost = profile.monthlyEssentialCost
                targetMonths = profile.targetMonths
                investPercent = profile.investPercent
                petName = profile.petName
                petColor = profile.petColor
            }
        }
    }

    private func save() {
        let name = petName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? "Moedinha" : name
        if let profile {
            profile.monthlyEssentialCost = monthlyCost
            profile.targetMonths = targetMonths
            profile.investPercent = investPercent
            profile.petName = finalName
            profile.petColor = petColor
            profile.touch()
            dismiss()
        } else {
            context.insert(PlayerProfile(monthlyEssentialCost: monthlyCost,
                                         targetMonths: targetMonths,
                                         investPercent: investPercent,
                                         petName: finalName,
                                         petColor: petColor))
        }
    }
}

// MARK: - Lançamento

struct EntryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: EntryKind = .expense
    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var category: EntryCategory = .food
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $kind) {
                    ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Descrição", text: $title)
                CurrencyField(title: "Valor", value: $amount)
                Picker("Categoria", selection: $category) {
                    ForEach(EntryCategory.cases(for: kind)) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .formStyle(.grouped)
            .navigationTitle("Novo lançamento")
            .onChange(of: kind) { _, newKind in
                category = EntryCategory.cases(for: newKind).first ?? .otherExpense
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let name = title.isEmpty ? category.title : title
                        context.insert(CashEntry(title: name, amount: amount, date: date, category: category))
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .sheetFrame()
    }
}

// MARK: - Conta fixa

struct BillFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var dueDay = 10

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (ex: Aluguel, Internet)", text: $name)
                CurrencyField(title: "Valor mensal", value: $amount)
                Stepper("Vence todo dia \(dueDay)", value: $dueDay, in: 1...31)
            }
            .formStyle(.grouped)
            .navigationTitle("Nova conta fixa")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        context.insert(Bill(name: name, amount: amount, dueDay: dueDay))
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0)
                }
            }
        }
        .sheetFrame()
    }
}

// MARK: - Reserva

struct ReserveFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// true para depósito, false para retirada.
    let isDeposit: Bool
    let currentBalance: Decimal

    @State private var amount: Decimal = 0
    @State private var note = ""

    private var isValid: Bool {
        amount > 0 && (isDeposit || amount <= currentBalance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CurrencyField(title: "Valor", value: $amount)
                    TextField(isDeposit ? "Observação (opcional)" : "Qual foi a emergência?", text: $note)
                } footer: {
                    if isDeposit {
                        Text("Cada depósito rende XP e aproxima você do Nível 2.")
                    } else {
                        Text("Use a reserva só em emergências reais. Saldo atual: \(currentBalance.brl)")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isDeposit ? "Depositar na reserva" : "Retirar da reserva")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") {
                        context.insert(ReserveMovement(amount: isDeposit ? amount : -amount, note: note))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .sheetFrame()
    }
}

// MARK: - Investimento

struct InvestmentFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var modality: InvestmentModality = .tesouroSelic
    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Modalidade") {
                    Picker("Modalidade", selection: $modality) {
                        ForEach(InvestmentModality.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    LabeledContent("Perfil", value: modality.riskTitle)
                }
                Section("Aporte") {
                    TextField("Onde? (ex: banco, corretora, ativo)", text: $name)
                    CurrencyField(title: "Valor", value: $amount)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Novo aporte")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let label = name.isEmpty ? modality.title : name
                        context.insert(Investment(name: label, modality: modality, amount: amount, date: date))
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .sheetFrame()
    }
}
