import SwiftUI

@main
struct SpedizioniApp: App {
    @StateObject private var store = ShipmentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
