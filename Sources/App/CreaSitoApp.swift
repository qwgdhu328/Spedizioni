import SwiftUI

@main
struct CreaSitoApp: App {
    @StateObject private var site = SiteStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(site)
        }
    }
}
