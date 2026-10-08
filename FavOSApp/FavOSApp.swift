// FavOSApp.swift — La shell iOS di FavOS.
//
// Non fa altro che montare la vista del wrapper (FavOSSchermo) con una
// sessione di fabbrica: kernel con le app .fvb del bundle, ciclo di
// schedula a 50 ms e render del framebuffer 320x240.
// Tutta la logica vive nel package FavOS; qui c'e' solo l'ingresso.

import SwiftUI
import FavOS

@main
struct FavOSApp: App {
    @StateObject private var sessione = Sessione(kernel: Risorse.kernelDiFabbrica())

    var body: some Scene {
        WindowGroup {
            FavOSSchermo(sessione: sessione)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
