// Viste.swift — Le schermate di FavOS, disegnate una volta per tutte
// (port fedele di viste.py). Un solo punto disegna lo schermo 320x240:
// il wrapper Swift non fa che mostrare questo framebuffer, quindi
// l'interfaccia e' identica al PC e all'ESP32, per costruzione.

import Foundation

public enum Viste {

    // -----------------------------------------------------------
    // HOME
    // -----------------------------------------------------------
    static func home(_ k: Kernel, _ fb: Framebuffer) {
        fb.rett(0, 0, Kernel.larghezza, Kernel.rigaNavY,
                Colori.interfaccia("solo_sfondo"))
        fb.testo(6, 5, "FavOS", Colori.interfaccia("bianco"), scala: 2)
        fb.testo(46, 11, "1.0", Colori.interfaccia("acento"), scala: 1)
        let nomi = k.nomiHome
        for (i, nome) in nomi.enumerated() {
            let c = Kernel.homeCelle[i]
            let ac = Colori.accentoApp(nome)
            fb.rett(c.x, c.y, c.w, c.h, Colori.interfaccia("celle"))
            fb.rett(c.x, c.y, 3, c.h, ac)
            let primo = String(nome.prefix(1)).uppercased()
            fb.testo(c.x + 14, c.y + 10, primo, ac, scala: 3)
            fb.testo(c.x + 40, c.y + 12, String(nome.prefix(9)),
                     Colori.interfaccia("bianco"), scala: 1)
        }
        fb.testo(6, 164,
                 "tocco su un'app, tasti 1-9; INVIO o console = shell",
                 Colori.interfaccia("grigio"), scala: 1)
    }

    // -----------------------------------------------------------
    // SHELL
    // -----------------------------------------------------------
    static func shell(_ k: Kernel, _ fb: Framebuffer) {
        fb.rett(0, 0, Kernel.larghezza, Kernel.rigaNavY,
                Colori.interfaccia("solo_sfondo"))
        var y = 2
        for riga in k.shellOutput.suffix(14) {
            fb.testo(2, y, riga, Colori.interfaccia("grigio_chiaro"),
                     scala: 1)
            y += 12
        }
        fb.rett(0, Kernel.rigaNavY - 10, Kernel.larghezza, 1,
                Colori.interfaccia("celle_orlo"))
        let cursore = Int(Date().timeIntervalSince1970 * 2) % 2 == 0
            ? "_" : " "
        fb.testo(2, Kernel.rigaNavY - 8, "> " + k.shellRiga + cursore,
                 Colori.interfaccia("acento"), scala: 1)
    }

    // -----------------------------------------------------------
    // RIGA DI NAVIGAZIONE (176..192): home | console | titolo
    // -----------------------------------------------------------
    static func nav(_ k: Kernel, _ fb: Framebuffer) {
        fb.rett(0, Kernel.rigaNavY, Kernel.larghezza,
                Kernel.tastiY - Kernel.rigaNavY,
                Colori.interfaccia("barra"))
        let zona = Kernel.larghezza / 3
        fb.rett(2, Kernel.rigaNavY + 2, zona - 4, 12,
                Colori.interfaccia("celle"))
        fb.testo(6, Kernel.rigaNavY + 4, "< home",
                 Colori.interfaccia("bianco"), scala: 1)
        fb.rett(zona + 2, Kernel.rigaNavY + 2, zona - 4, 12,
                Colori.interfaccia("celle"))
        fb.testo(zona + 6, Kernel.rigaNavY + 4, "console",
                 Colori.interfaccia("bianco"), scala: 1)
        var titolo = "FavOS 1.0"
        if let p = k.processi.last { titolo = String(p.nome.prefix(16)) }
        if k.statoRete == "attiva" {
            titolo = "rete: " + String((k.reteAttivaPer ?? "?").prefix(9))
        }
        fb.rett(2 * zona + 2, Kernel.rigaNavY + 2, zona - 4, 12,
                Colori.interfaccia("celle_attivo"))
        fb.testo(2 * zona + 6, Kernel.rigaNavY + 4, titolo,
                 Colori.interfaccia("bianco"), scala: 1)
    }

    // -----------------------------------------------------------
    // TASTIERA A SCHERMO (192..234) + striscia di fondo (234..240)
    // -----------------------------------------------------------
    static func tastiera(_ fb: Framebuffer) {
        fb.rett(0, Kernel.tastiY, Kernel.larghezza,
                Kernel.altezza - Kernel.tastiY,
                Colori.interfaccia("barra"))
        for k in Kernel.tastiPos {
            fb.rett(k.x, k.y, k.w, k.h, Colori.interfaccia("celle"))
            if k.etichetta == "SPAZIO" {
                fb.rett(k.x + 10, k.y + 6, k.w - 20, 2,
                        Colori.interfaccia("grigio_chiaro"))
                continue
            }
            fb.testo(k.x + (k.w - 6 * k.etichetta.count) / 2, k.y + 4,
                     k.etichetta, Colori.interfaccia("bianco"), scala: 1)
        }
        fb.rett(0, 234, Kernel.larghezza, 2,
                Colori.interfaccia("celle_orlo"))
    }

    // -----------------------------------------------------------
    // RENDER COMPLETO: lo schermo intero 320x240
    // -----------------------------------------------------------
    public static func renderSchermo(_ k: Kernel) -> Framebuffer {
        let fb = Framebuffer(larghezza: Kernel.larghezza,
                             altezza: Kernel.altezza)
        if !k.pronto, let p = k.processi.last {
            fb.copiaRighe(da: p.framebuffer)
        } else if k.home {
            home(k, fb)
        } else {
            shell(k, fb)
        }
        nav(k, fb)
        tastiera(fb)
        return fb
    }
}
