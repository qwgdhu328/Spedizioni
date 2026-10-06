import SwiftUI

/// Radice dell'app: tab bar Liquid Glass (iOS 26) con
/// Sito (cartelle e codice), Pubblica (deploy online) e
/// Impostazioni (token Vercel).
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Sito", systemImage: "folder.fill.badge.gearshape") {
                SiteView()
            }
            Tab("Pubblica", systemImage: "icloud.and.arrow.up.fill") {
                PublishView()
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
        .environmentObject(SiteStore())
}
