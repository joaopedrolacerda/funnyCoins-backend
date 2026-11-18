import SwiftUI
import SwiftData

/// Raiz do app: mostra o onboarding até existir um perfil, depois as abas.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                NavigationStack {
                    ProfileFormView(profile: nil)
                }
            }
        }
        .task {
            // Corrige identificadores repetidos deixados pela migração de dados antigos.
            // Uma falha aqui não impede o uso do app e será tentada de novo na próxima abertura.
            _ = try? SyncMaintenance.repairDuplicateIDs(in: context)
        }
    }
}

/// Carrega todos os dados e monta o estado do jogo compartilhado entre as abas.
struct MainTabView: View {
    let profile: PlayerProfile

    // Registros excluídos ficam guardados para sincronizar, mas não entram no jogo.
    @Query(filter: CashEntry.active) private var entries: [CashEntry]
    @Query(filter: Bill.active) private var bills: [Bill]
    @Query(filter: ReserveMovement.active) private var reserveMovements: [ReserveMovement]
    @Query(filter: Investment.active) private var investments: [Investment]

    private var snapshot: GameSnapshot {
        GameSnapshot(profile: profile, entries: entries, bills: bills,
                     reserveMovements: reserveMovements, investments: investments)
    }

    var body: some View {
        let snapshot = snapshot
        TabView {
            Tab(profile.petName, systemImage: "pawprint.fill") {
                PetHomeView(snapshot: snapshot)
            }
            // Avisa na aba quando o bichinho precisa de cuidado.
            .badge(snapshot.petMood == .hungry || snapshot.petMood == .sick ? Text("!") : nil)
            Tab("Jornada", systemImage: "map.fill") {
                JourneyView(snapshot: snapshot)
            }
            Tab("Fluxo", systemImage: "arrow.left.arrow.right") {
                CashFlowView(snapshot: snapshot)
            }
            Tab("Contas", systemImage: "doc.text.fill") {
                BillsView()
            }
            .badge(snapshot.pendingBillsThisMonth.count)
            Tab("Investimentos", systemImage: snapshot.isLevel1Complete ? "chart.line.uptrend.xyaxis" : "lock.fill") {
                InvestmentsView(snapshot: snapshot)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PlayerProfile.self, CashEntry.self, Bill.self,
                              ReserveMovement.self, Investment.self], inMemory: true)
}
