import SwiftUI
import SwiftData

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Números, porcentagens e datas sempre no padrão brasileiro.
                .environment(\.locale, BRFormat.locale)
        }
        .modelContainer(for: [PlayerProfile.self, CashEntry.self, Bill.self,
                              ReserveMovement.self, Investment.self])
    }
}
