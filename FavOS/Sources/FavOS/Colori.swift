// Colori.swift — I colori di FavOS, in un solo punto (port di COLORI.py
// e della palette di kernel.py: due tabelle distinte come in Python).

import Foundation

/// Colore RGB packed 0xRRGGBB.
public typealias Colore = UInt32

public enum Colori {

    // Palette d'interfaccia usata da viste.py (COLORI._INTERFACCIA)
    private static let interfacciaViste: [String: Colore] = [
        "solo_sfondo": 0x10121A,
        "barra": 0x1C1E28,
        "celle": 0x282C3A,
        "celle_attivo": 0x3A4054,
        "celle_orlo": 0x4A5064,
        "acento": 0x468CFF,
    ]

    // Palette d'interfaccia di kernel.py (COLORI_INTERFACE), usata dalle
    // app che passano nomi tipo "celle" a os_disegna_rett
    private static let interfacciaKernel: [String: Colore] = [
        "CELL": 0x1C1E26, "CELLON": 0x2A2E3A, "CELLED": 0x5A6074,
        "BAR": 0x242832, "BG": 0x0E0E16, "ACCENT": 0x3C80FF,
    ]

    // Colori con nome, uguali in COLORI.py e kernel.py
    private static let nomi: [String: Colore] = [
        "nero": 0x000000, "bianco": 0xFFFFFF, "rosso": 0xDC2828,
        "verde": 0x3CC850, "blu": 0x3C64F0, "giallo": 0xF0DC3C,
        "ciano": 0x3CDCEC, "magenta": 0xDC3CC8, "arancione": 0xFA8C1E,
        "grigio": 0x808080, "grigio_chiaro": 0xBEBEBE,
        "grigio_scuro": 0x3C3C3C, "verde_acqua": 0x28B48C,
        "turchese": 0x28BEC8, "nero_blu": 0x0A0A28,
        "verde_scuro": 0x145A28,
    ]

    // Alias dell'interfaccia nella palette del kernel (kernel.COLORI_NOMI)
    private static let aliasKernel: [String: Colore] = [
        "celle": interfacciaKernel["CELL"]!,
        "celle_attivo": interfacciaKernel["CELLON"]!,
        "celle_orlo": interfacciaKernel["CELLED"]!,
        "barra": interfacciaKernel["BAR"]!,
        "solo_sfondo": interfacciaKernel["BG"]!,
        "acento": interfacciaKernel["ACCENT"]!,
    ]

    // Accento delle icone home (COLORI._ACCENTI_APP)
    private static let accentiApp: [String: String] = [
        "google": "blu", "youtube": "rosso", "snake": "verde",
        "sicurezza": "verde_scuro", "info": "ciano", "demo": "magenta",
        "calcolatore": "arancione", "note": "giallo", "ciao": "grigio",
        "prova": "turchese",
    ]

    /// Colore d'interfaccia per nome (COLORI.colore): viste usa questo.
    public static func interfaccia(_ nome: String) -> Colore {
        if let v = interfacciaViste[nome] { return v }
        if let v = nomi[nome] { return v }
        return 0xFF00FF   // magenta = colore sbagliato
    }

    /// Colore d'accento di un'app (COLORI.colore_app).
    public static func accentoApp(_ nome: String) -> Colore {
        interfaccia(accentiApp[nome] ?? "grigio_chiaro")
    }

    /// Colore passato dalle app a os_disegna_* (kernel.colore_tupla):
    /// nome testo oppure lista [r, g, b].
    public static func dagliApp(_ valore: Valore) -> Colore {
        switch valore {
        case .testo(let nome):
            let n = nome.lowercased()
            if let v = aliasKernel[n] { return v }
            if let v = nomi[n] { return v }
            return 0xFF00FF
        case .lista(let rgb) where rgb.count == 3:
            let r = max(0, min(255, rgb[0].numeroIntera))
            let g = max(0, min(255, rgb[1].numeroIntera))
            let b = max(0, min(255, rgb[2].numeroIntera))
            return UInt32((r << 16) | (g << 8) | b)
        default:
            return 0xFF00FF
        }
    }
}

extension Valore {
    /// Il valore come intero (per coordinate e colori); 0 se non e' numero.
    var numeroIntera: Int {
        guard case .numero(let d) = self else { return 0 }
        return Int(d.rounded())
    }
}
