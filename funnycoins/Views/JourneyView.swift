import SwiftUI

/// Tela principal do jogo em slides: Nível 1 → Nível 2 → Conquistas.
struct JourneyView: View {
    let snapshot: GameSnapshot

    @State private var page: Int?
    @State private var reserveSheet: ReserveAction?
    @State private var isEditingProfile = false
    @State private var isAddingGain = false

    enum ReserveAction: Identifiable {
        case deposit, withdraw
        var id: Self { self }
    }

    private let slideCount = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                rankHeader
                    .padding(.horizontal)

                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<slideCount, id: \.self) { index in
                            slide(at: index)
                                .padding(.horizontal)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $page)

                StepDots(count: slideCount, current: page ?? 0) { index in
                    withAnimation { page = index }
                }

                Button {
                    isAddingGain = true
                } label: {
                    Label("Adicionar ganho", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Jornada")
            .toolbar {
                ToolbarItem {
                    Button("Perfil", systemImage: "person.crop.circle") { isEditingProfile = true }
                }
            }
            .onAppear {
                // Abre no slide do nível em que a pessoa está.
                if page == nil { page = snapshot.currentLevel - 1 }
            }
            .sheet(item: $reserveSheet) { action in
                ReserveFormView(isDeposit: action == .deposit, currentBalance: snapshot.reserveBalance)
            }
            .sheet(isPresented: $isEditingProfile) {
                NavigationStack { ProfileFormView(profile: snapshot.profile) }
                    .sheetFrame()
            }
            .sheet(isPresented: $isAddingGain) {
                GainWizardView(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func slide(at index: Int) -> some View {
        ScrollView {
            Group {
                switch index {
                case 0: level1Slide
                case 1: level2Slide
                default: achievementsSlide
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 28))
    }

    // MARK: Patente e XP

    private var rankHeader: some View {
        HStack(spacing: 12) {
            PetView(stage: snapshot.petStage, mood: snapshot.petMood,
                    color: snapshot.profile.petColor.color, size: 48, isAnimated: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.rankTitle).font(.headline)
                    Spacer()
                    Text("\(snapshot.xp) XP")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: snapshot.rankProgress)
                    .tint(.yellow)
            }
        }
    }

    // MARK: Slide 1 - Reserva

    private var level1Slide: some View {
        VStack(spacing: 20) {
            SlideHeader(level: "NÍVEL 1", title: "Reserva de emergência",
                        subtitle: "Sua base de proteção: \(snapshot.profile.targetMonths) meses do seu custo de vida guardados.",
                        isDone: snapshot.isLevel1Complete)

            ProgressRing(progress: snapshot.reserveProgress, lineWidth: 18, tint: .green, font: .title.bold())
                .frame(width: 170, height: 170)

            VStack(spacing: 4) {
                Text(snapshot.reserveBalance.brl).font(.title2.bold())
                Text("de \(snapshot.reserveGoal.brl)").foregroundStyle(.secondary)
                Text("Cobre \(snapshot.monthsCovered, format: .number.precision(.fractionLength(1))) meses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.isLevel1Complete {
                Label("Reserva completa! Deslize para o Nível 2", systemImage: "arrow.right.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.green)
            } else {
                Text("Faltam \(snapshot.reserveMissing.brl) para desbloquear o Nível 2")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Depositar", systemImage: "arrow.down.circle.fill") { reserveSheet = .deposit }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Retirar", systemImage: "arrow.up.circle") { reserveSheet = .withdraw }
                    .buttonStyle(.bordered)
                    .disabled(snapshot.reserveBalance <= 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Slide 2 - Investimentos

    @ViewBuilder
    private var level2Slide: some View {
        if snapshot.isLevel1Complete {
            VStack(spacing: 20) {
                SlideHeader(level: "NÍVEL 2", title: "Investimentos",
                            subtitle: "Separe \(snapshot.profile.investPercent)% de cada ganho e invista onde quiser.",
                            isDone: false)

                ProgressRing(progress: snapshot.monthlyInvestProgress, lineWidth: 18, tint: .blue, font: .title.bold())
                    .frame(width: 170, height: 170)

                VStack(spacing: 4) {
                    Text(snapshot.investedThisMonth.brl).font(.title2.bold())
                    Text("de \(snapshot.monthlyInvestTarget.brl) neste mês").foregroundStyle(.secondary)
                    Text("Total investido: \(snapshot.investedTotal.brl)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if snapshot.allocation.isEmpty {
                    Text("Adicione um ganho e escolha onde investir uma parte.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 8) {
                        ForEach(snapshot.allocation.prefix(3), id: \.modality) { item in
                            HStack {
                                Label(item.modality.title, systemImage: item.modality.symbol)
                                Spacer()
                                Text(item.amount.brl).monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 20) {
                SlideHeader(level: "NÍVEL 2", title: "Investimentos",
                            subtitle: "Bloqueado até você completar a reserva de emergência.",
                            isDone: false)

                Image(systemName: "lock.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                    .frame(height: 170)

                Text("Você está a \(snapshot.reserveMissing.brl) de desbloquear")
                    .font(.callout.bold())
                    .multilineTextAlignment(.center)

                Text("O que te espera aqui:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                    ForEach(InvestmentModality.allCases) { item in
                        Image(systemName: item.symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(item.title)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Slide 3 - Conquistas

    private var achievementsSlide: some View {
        VStack(spacing: 16) {
            let unlocked = snapshot.achievements.filter(\.isUnlocked).count
            SlideHeader(level: "TROFÉUS", title: "Conquistas",
                        subtitle: "\(unlocked) de \(snapshot.achievements.count) desbloqueadas",
                        isDone: unlocked == snapshot.achievements.count)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                ForEach(snapshot.achievements) { achievement in
                    VStack(spacing: 6) {
                        Image(systemName: achievement.symbol)
                            .font(.title)
                            .foregroundStyle(achievement.isUnlocked ? Color.orange : Color.secondary)
                        Text(achievement.title).font(.subheadline.bold())
                        Text(achievement.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .padding(8)
                    .background(.background.tertiary, in: .rect(cornerRadius: 14))
                    .opacity(achievement.isUnlocked ? 1 : 0.5)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(achievement.isUnlocked ? "Desbloqueada" : "Bloqueada")
                }
            }
        }
    }
}

/// Cabeçalho de cada slide de nível.
private struct SlideHeader: View {
    let level: String
    let title: String
    let subtitle: String
    let isDone: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(level)
                if isDone { Image(systemName: "checkmark.circle.fill") }
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isDone ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15), in: .capsule)

            Text(title).font(.title.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview("Jornada - Nível 1") {
    JourneyView(snapshot: GameSnapshot(
        profile: PlayerProfile(monthlyEssentialCost: 3000),
        entries: [CashEntry(title: "Salário", amount: 5000, category: .salary)],
        bills: [],
        reserveMovements: [ReserveMovement(amount: 7200)],
        investments: []))
}

#Preview("Novo ganho") {
    GainWizardView(snapshot: GameSnapshot(
        profile: PlayerProfile(monthlyEssentialCost: 3000),
        entries: [], bills: [], reserveMovements: [], investments: []))
}
