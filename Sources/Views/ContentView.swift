import SwiftUI

/// Radice dell'app: tab bar Liquid Glass nativa (iOS 26) con
/// Spedizioni, Reti (tutte le reti di spedizione) e Impostazioni.
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Spedizioni", systemImage: "shippingbox.fill") {
                ShipmentListView()
            }
            Tab("Reti", systemImage: "network") {
                CarriersView()
            }
            Tab("Impostazioni", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.never)
    }
}

#Preview {
    ContentView()
        .environmentObject(ShipmentStore())
}
