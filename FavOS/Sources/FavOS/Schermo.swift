// Schermo.swift — La vista SwiftUI del wrapper: mostra il framebuffer
// 320x240 (pixel art, nessuna interpolazione), traduce i tocchi in
// coordinate FavOS e i tasti hardware nei tasti del sistema.

import SwiftUI

public struct FavOSSchermo: View {
    @ObservedObject private var sessione: Sessione
    @FocusState private var foco: Bool

    public init(sessione: Sessione) {
        self.sessione = sessione
    }

    public var body: some View {
        GeometryReader { geo in
            let scala = min(geo.size.width / CGFloat(Kernel.larghezza),
                            geo.size.height / CGFloat(Kernel.altezza))
            let w = CGFloat(Kernel.larghezza) * scala
            let h = CGFloat(Kernel.altezza) * scala
            let ox = (geo.size.width - w) / 2
            let oy = (geo.size.height - h) / 2
            ZStack {
                Color.black
                if let img = sessione.schermo {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: w, height: h)
                        .position(x: ox + w / 2, y: oy + h / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { valore in
                    guard scala > 0 else { return }
                    let x = Int((valore.location.x - ox) / scala)
                    let y = Int((valore.location.y - oy) / scala)
                    if x >= 0, x < Kernel.larghezza,
                       y >= 0, y < Kernel.altezza {
                        sessione.tocco(x: x, y: y)
                    }
                }
            )
        }
        .focusable()
        .focused($foco)
        .onAppear {
            sessione.avvia()
            foco = true
        }
        // Tasti hardware -> tasti FavOS (KeyPress: iOS 17 / macOS 14)
        .onKeyPress { press in
            let k = press.key
            if k == .delete {
                sessione.premiTasto("CANCELLA")
                return KeyPress.Result.handled
            }
            if k == .escape {
                sessione.premiTasto("ESC")
                return KeyPress.Result.handled
            }
            if k == KeyEquivalent("\r") || k == KeyEquivalent("\n") {
                sessione.premiTasto("INVIO")
                return KeyPress.Result.handled
            }
            // caratteri stampabili (spazio compreso): il kernel
            // normalizza da solo \r / \n in INVIO
            let chars = press.characters
            guard !chars.isEmpty else { return KeyPress.Result.ignored }
            for ch in chars { sessione.premiTasto(String(ch)) }
            return KeyPress.Result.handled
        }
#if os(macOS)
        // le frecce non passano da onKeyPress: onMoveCommand (solo macOS)
        .onMoveCommand { direzione in
            switch direzione {
            case .up: sessione.premiTasto("SU")
            case .down: sessione.premiTasto("GIU")
            case .left: sessione.premiTasto("SINISTRA")
            case .right: sessione.premiTasto("DESTRA")
            @unknown default: break
            }
        }
#endif
    }
}
