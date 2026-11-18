import SwiftUI

/// Casa do bichinho: estilo Tamagotchi. Ele reage ao que você faz com o dinheiro.
struct PetHomeView: View {
    let snapshot: GameSnapshot

    @State private var tapCount = 0
    @State private var tip: String?
    @State private var isFeeding = false
    @State private var isProtecting = false
    @State private var isEditingProfile = false

    private var profile: PlayerProfile { snapshot.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    speechBubble
                    pet
                    needs
                    actions
                }
                .padding()
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(profile.petName)
            .toolbar {
                ToolbarItem {
                    Button("Personalizar", systemImage: "paintpalette") { isEditingProfile = true }
                }
            }
            .sheet(isPresented: $isFeeding) { GainWizardView(snapshot: snapshot) }
            .sheet(isPresented: $isProtecting) {
                ReserveFormView(isDeposit: true, currentBalance: snapshot.reserveBalance)
            }
            .sheet(isPresented: $isEditingProfile) {
                NavigationStack { ProfileFormView(profile: profile) }
                    .sheetFrame()
            }
        }
    }

    private var header: some View {
        HStack {
            Label(snapshot.petStage.title, systemImage: "sparkles")
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(profile.petColor.color.opacity(0.2), in: .capsule)
            Spacer()
            Label(snapshot.petMood.title, systemImage: snapshot.petMood.symbol)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }

    private var speechBubble: some View {
        Text(tip ?? snapshot.petMessage)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: .rect(cornerRadius: 18))
            .overlay(alignment: .bottom) {
                // Rabinho do balão apontando para o bichinho
                Image(systemName: "arrowtriangle.down.fill")
                    .foregroundStyle(.background.secondary)
                    .offset(y: 10)
            }
            .contentTransition(.opacity)
            .animation(.default, value: tip)
    }

    private var pet: some View {
        PetView(stage: snapshot.petStage, mood: snapshot.petMood,
                color: profile.petColor.color, size: 230)
            // Pulinho a cada toque
            .keyframeAnimator(initialValue: 0.0, trigger: tapCount) { content, jump in
                content.offset(y: -jump)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(36, duration: 0.18)
                    SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                }
            }
            .onTapGesture {
                tapCount += 1
                tip = GameSnapshot.petTips.filter { $0 != tip }.randomElement()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Toque para ouvir uma dica")
    }

    private var needs: some View {
        VStack(spacing: 14) {
            NeedBar(title: "Fome", symbol: "fork.knife", value: snapshot.petNeeds.hunger, tint: .orange,
                    detail: hungerDetail)
            NeedBar(title: "Proteção", symbol: "shield.fill", value: snapshot.petNeeds.protection, tint: .green,
                    detail: "Cresce com a reserva de emergência")
            NeedBar(title: "Alegria", symbol: "heart.fill", value: snapshot.petNeeds.joy, tint: .pink,
                    detail: "Contas em dia e guardar dinheiro no mês")

            if let hint = snapshot.nextEvolutionHint {
                Label(hint, systemImage: "arrow.up.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(profile.petColor.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .card()
    }

    private var hungerDetail: String {
        switch snapshot.daysSinceLastEntry {
        case nil: "Ainda não comeu nada"
        case 0: "Comeu hoje"
        case 1: "Último registro foi ontem"
        case let days?: "Último registro há \(days) dias"
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            ActionButton(title: snapshot.petStage == .egg ? "Chocar" : "Alimentar",
                         subtitle: "Registrar ganho", symbol: "fork.knife", tint: .orange) {
                isFeeding = true
            }
            if !snapshot.isLevel1Complete {
                ActionButton(title: "Proteger", subtitle: "Guardar na reserva",
                             symbol: "shield.fill", tint: .green) {
                    isProtecting = true
                }
            }
        }
    }
}

private struct NeedBar: View {
    let title: String
    let symbol: String
    let value: Double
    let tint: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: value)
                .tint(value < 0.3 ? .red : tint)
                .animation(.spring, value: value)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(tint.gradient, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PetHomeView(snapshot: GameSnapshot(
        profile: PlayerProfile(monthlyEssentialCost: 3000, petName: "Moedinha", petColor: .purple),
        entries: [CashEntry(title: "Salário", amount: 5000, category: .salary)],
        bills: [],
        reserveMovements: [ReserveMovement(amount: 10000)],
        investments: []))
}
