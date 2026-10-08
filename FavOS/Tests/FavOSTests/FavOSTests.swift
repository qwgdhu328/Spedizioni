// FavOSTests.swift — I test del wrapper Swift: la stessa strada che
// percorre l'app (kernel -> VM C++ -> syscalls -> framebuffer).

import XCTest
@testable import FavOS

final class FavOSTests: XCTestCase {

    // -----------------------------------------------------------
    // App: avvio, esecuzione, output in shell
    // -----------------------------------------------------------
    func testAppCiaoEsegue() {
        let kernel = Risorse.kernelDiFabbrica()
        XCTAssertFalse(kernel.apps.isEmpty, "bundle Apps vuoto")

        XCTAssertNil(kernel.avviaApp("ciao"))
        XCTAssertFalse(kernel.pronto)
        XCTAssertEqual(kernel.processi.count, 1)

        var giri = 0
        while !kernel.pronto && giri < 200 {
            kernel.schedula()
            giri += 1
        }
        XCTAssertTrue(kernel.pronto, "l'app non e' terminata")

        let out = kernel.shellOutput.joined(separator: "\n")
        XCTAssertTrue(out.contains("--- ciao ---"))
        XCTAssertTrue(out.contains("=== App Ciao, in Favilla ==="))
        XCTAssertTrue(out.contains("Ciao Davide!"))
        XCTAssertTrue(out.contains("tra 14 anni sara' il 2050"))
        XCTAssertTrue(out.contains("Oggi e' il 17 ottobre"))
        XCTAssertTrue(out.contains("Prova di matematica: 7 * 6 = 42"))
        XCTAssertTrue(out.contains("Ciao app finita. ESC per tornare alla shell."))
    }

    func testAppSconosciuta() {
        let kernel = Risorse.kernelDiFabbrica()
        XCTAssertEqual(kernel.avviaApp("boh"), "App sconosciuta: boh")
    }

    // -----------------------------------------------------------
    // Shell: dalla home si scrive un comando e si esegue
    // -----------------------------------------------------------
    func testShellAiuto() {
        let kernel = Risorse.kernelDiFabbrica()
        XCTAssertTrue(kernel.home)
        for ch in "aiuto" { kernel.premiTasto(String(ch)) }
        XCTAssertFalse(kernel.home, "la prima lettera apre la shell")
        XCTAssertEqual(kernel.shellRiga, "aiuto")
        kernel.premiTasto("INVIO")
        XCTAssertEqual(kernel.shellRiga, "")
        XCTAssertTrue(kernel.shellOutput.contains {
            $0.hasPrefix("Comandi:") })
        XCTAssertTrue(kernel.shellOutput.contains("favos> aiuto"))
    }

    func testShellAppsECancellazione() {
        let kernel = Risorse.kernelDiFabbrica()
        kernel.apriShell()
        for ch in "apps" { kernel.premiTasto(String(ch)) }
        kernel.premiTasto("INVIO")
        XCTAssertTrue(kernel.shellOutput.contains {
            $0.hasPrefix("App: ") && $0.contains("snake") })
        // CANCELLA toglie un carattere dalla riga
        for ch in "abc" { kernel.premiTasto(String(ch)) }
        kernel.premiTasto("CANCELLA")
        XCTAssertEqual(kernel.shellRiga, "ab")
    }

    func testShellFileScriviLeggi() {
        let kernel = Risorse.kernelDiFabbrica()
        kernel.apriShell()
        func comando(_ s: String) {
            for ch in s { kernel.premiTasto(String(ch)) }
            kernel.premiTasto("INVIO")
        }
        comando("scrivi memo ciao dal wrapper")
        comando("leggi memo")
        XCTAssertTrue(kernel.shellOutput.contains("Scritto /favos/memo"))
        XCTAssertTrue(kernel.shellOutput.contains("ciao dal wrapper"))
    }

    // -----------------------------------------------------------
    // Home: tocco su una cella -> l'app parte; ESC torna alla shell
    // -----------------------------------------------------------
    func testToccoCellaAvviaApp() {
        let kernel = Risorse.kernelDiFabbrica()
        let primo = kernel.nomiHome[0]
        let c = Kernel.homeCelle[0]
        kernel.tocco(x: c.x + 10, y: c.y + 10)
        XCTAssertFalse(kernel.pronto)
        XCTAssertEqual(kernel.processi.last?.nome, primo)
        XCTAssertTrue(kernel.shellOutput.contains("> " + primo))

        kernel.premiTasto("ESC")
        XCTAssertTrue(kernel.pronto)
        XCTAssertTrue(kernel.processi.isEmpty)
    }

    func testRigaNavigazione() {
        let kernel = Risorse.kernelDiFabbrica()
        kernel.apriShell()
        XCTAssertFalse(kernel.home)
        // zona 0 (< home) nella riga di navigazione
        kernel.tocco(x: 10, y: Kernel.rigaNavY + 4)
        XCTAssertTrue(kernel.home)
        // zona 1 (console)
        kernel.tocco(x: Kernel.larghezza / 3 + 10, y: Kernel.rigaNavY + 4)
        XCTAssertFalse(kernel.home)
    }

    func testTastieraASchermo() {
        let kernel = Risorse.kernelDiFabbrica()
        kernel.apriShell()
        // il tasto 'q' (primo della prima riga) e' in (0..32, 192..206)
        kernel.tocco(x: 5, y: 195)
        XCTAssertEqual(kernel.shellRiga, "q")
        // INVIO: x 236..278, y 220..234
        kernel.tocco(x: 250, y: 225)
        XCTAssertTrue(kernel.shellOutput.contains("favos> q"))
        XCTAssertTrue(kernel.shellOutput.contains {
            $0.hasPrefix("Comando sconosciuto: q") })
    }

    // -----------------------------------------------------------
    // Liste: os_tocco ritorna una lista, testo_unisci la riceve
    // -----------------------------------------------------------
    func testListeOsTocco() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "lista_tocco", withExtension: "fvb"))
        let dati = try Data(contentsOf: url)
        let kernel = Kernel(apps: ["lista_tocco": (dati, "console")])
        XCTAssertNil(kernel.avviaApp("lista_tocco"))
        // tocco in coordinate libere: arriva a os_tocco()
        kernel.tocco(x: 33, y: 44)
        var giri = 0
        while !kernel.pronto && giri < 200 {
            kernel.schedula()
            giri += 1
        }
        XCTAssertTrue(kernel.pronto)
        let out = kernel.shellOutput.joined(separator: "\n")
        XCTAssertTrue(out.contains("tocco 33,44"), out)
        XCTAssertTrue(out.contains("lista: 2"), out)
        XCTAssertTrue(out.contains("ciao-mondo"), out)
        XCTAssertTrue(out.contains("fine"), out)
    }

    // -----------------------------------------------------------
    // Render: la home usa gli stessi colori di COLORI.py
    // -----------------------------------------------------------
    func testRenderHome() {
        let kernel = Risorse.kernelDiFabbrica()
        let fb = Viste.renderSchermo(kernel)
        // sfondo home: solo_sfondo (16, 18, 26)
        XCTAssertEqual(fb.pixel[0], 0x10121A)
        // riga di navigazione: barra (28, 30, 40)
        let nav = Kernel.rigaNavY * Kernel.larghezza + 10
        XCTAssertEqual(fb.pixel[nav], 0x1C1E28)
        // tastiera a schermo: barra
        let tasti = Kernel.tastiY * Kernel.larghezza + 10
        XCTAssertEqual(fb.pixel[tasti], 0x1C1E28)
        // l'immagine CGImage si crea
        XCTAssertNotNil(fb.cgImage())
    }

    func testRenderShellEApp() {
        let kernel = Risorse.kernelDiFabbrica()
        kernel.apriShell()
        kernel.scrivi("pronta")
        var fb = Viste.renderSchermo(kernel)
        // la shell scrive col font 5x7: deve esserci almeno un pixel acceso
        let acceso = fb.pixel.prefix(Kernel.rigaNavY * Kernel.larghezza)
            .contains { $0 == 0xBEBEBE }
        XCTAssertTrue(acceso, "testo della shell non renderizzato")

        XCTAssertNil(kernel.avviaApp("ciao"))
        kernel.schedula()
        fb = Viste.renderSchermo(kernel)
        XCTAssertNotNil(fb.cgImage())
    }

    // -----------------------------------------------------------
    // Firma del bytecode (HMAC-SHA256, formato FVS1)
    // -----------------------------------------------------------
    func testFirma() {
        let chiave = Data("chiave_di_test_per_i_unit".utf8)
        let bytecode = Data([0x46, 0x56, 0x42, 0x31, 0x01, 0x02, 0x03, 0x04])

        let pacchetto = Firma.firma(bytecode, chiave: chiave)
        XCTAssertNotNil(pacchetto.starts(with: Firma.magico))

        let (d1, s1) = Firma.verifica(pacchetto: pacchetto, chiave: chiave)
        XCTAssertEqual(s1, .firmato)
        XCTAssertEqual(d1, bytecode)

        // senza chiave la verifica salta: non_firmato ma gira
        let (_, s2) = Firma.verifica(pacchetto: pacchetto, chiave: nil)
        XCTAssertEqual(s2, .nonFirmato)

        // bytecode crudo: non firmato
        let (_, s3) = Firma.verifica(pacchetto: bytecode, chiave: chiave)
        XCTAssertEqual(s3, .nonFirmato)

        // un byte manomesso -> alterato, avvio rifiutato
        var manomesso = pacchetto
        manomesso[manomesso.count - 1] ^= 0xFF
        let (d4, s4) = Firma.verifica(pacchetto: manomesso, chiave: chiave)
        XCTAssertEqual(s4, .alterato)
        XCTAssertEqual(d4.count, bytecode.count)
    }

    func testAvvioRifiutaBytecodeManomesso() {
        let chiave = Data("chiave_di_test_per_i_unit".utf8)
        let kernel = Risorse.kernelDiFabbrica(chiaveFirma: chiave)
        guard let (raw, _) = kernel.apps["ciao"] else {
            return XCTFail("app ciao nel bundle")
        }
        // firma bene, poi manometti UN byte dentro il pacchetto
        var firmato = Firma.firma(raw, chiave: chiave)
        firmato[firmato.count - 1] ^= 0xFF
        kernel.apps["ciao"] = (firmato, "console")
        XCTAssertEqual(kernel.avviaApp("ciao"), "bytecode alterato")
        XCTAssertTrue(kernel.shellOutput.contains {
            $0.contains("bytecode manomesso, avvio rifiutato") })
        XCTAssertTrue(kernel.pronto)
        XCTAssertTrue(kernel.processi.isEmpty)
    }

    // -----------------------------------------------------------
    // Syscall di rete: negate senza permesso, gestite con permesso
    // -----------------------------------------------------------
    func testReteNegata() throws {
        let kernel = Risorse.kernelDiFabbrica()
        // "ciao" non ha il permesso rete nel manifesto
        XCTAssertNil(kernel.avviaApp("ciao"))
        let p = try XCTUnwrap(kernel.processi.first)
        let esito = p.syscall("os_web_cerca_google", [.testo("partita")])
        XCTAssertEqual(esito, .testo("negato"))
    }
}
