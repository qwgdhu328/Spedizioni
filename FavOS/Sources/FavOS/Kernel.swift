// Kernel.swift — Il kernel di FavOS in Swift (port di kernel.py).
//
// Gestisce: processi (una VM per app), shell, console, filesystem,
// tastiera (coda eventi) e syscalls. Il kernel NON disegna: espone lo
// stato che Viste trasforma nel framebuffer 320x240, esattamente come
// in Python (cosi' l'interfaccia e' identica ovunque, per costruzione).

import Foundation

public final class Kernel {

    // -----------------------------------------------------------
    // GEOMETRIA DELL'INTERFACCIA (un solo punto: kernel + viste)
    // Zona bassa: riga nav 176..192, tastiera 192..234, striscia 234..240
    // -----------------------------------------------------------
    public static let larghezza = 320
    public static let altezza = 240
    public static let altezzaApp = 176           // zona app
    public static let rigaNavY = 176
    public static let tastiY = 192
    public static let rigaAlta = 12
    public static let righeConsole = altezzaApp / rigaAlta   // 14

    public static let tastiPos: [(x: Int, y: Int, w: Int, h: Int,
                                  etichetta: String)] = {
        var t: [(x: Int, y: Int, w: Int, h: Int, etichetta: String)] = []
        for (i, c) in Array("qwertyuiop").enumerated() {
            t.append((x: i * 32, y: 192, w: 32, h: 14,
                      etichetta: String(c)))
        }
        for (i, c) in Array("asdfghjkl").enumerated() {
            t.append((x: 16 + i * 32, y: 206, w: 32, h: 14,
                      etichetta: String(c)))
        }
        for (i, c) in Array("zxcvbnm").enumerated() {
            t.append((x: i * 28, y: 220, w: 28, h: 14,
                      etichetta: String(c)))
        }
        t.append((x: 196, y: 220, w: 40, h: 14, etichetta: "SPAZIO"))
        t.append((x: 236, y: 220, w: 42, h: 14, etichetta: "INVIO"))
        t.append((x: 278, y: 220, w: 42, h: 14, etichetta: "CANC"))
        return t
    }()

    /// Celle della home: 9 app in griglia 3x3 (coordinate y 4..156)
    public static let homeCelle: [(x: Int, y: Int, w: Int, h: Int)] =
        (0..<9).map {
            (x: 4 + ($0 % 3) * 106, y: 4 + ($0 / 3) * 52, w: 100, h: 48)
        }

    /// L'etichetta disegnata diventa il tasto FavOS vero.
    public static func tastoDaEtichetta(_ etichetta: String) -> String {
        switch etichetta {
        case "SPAZIO": return " "
        case "CANC": return "CANCELLA"
        default: return etichetta
        }
    }

    // -----------------------------------------------------------
    // TUTTE LE SYSCALL REGISTRABILI (35 <= FAV_SYSCALLS_MAX 48)
    // -----------------------------------------------------------
    public static let nomiSyscall: [String] = [
        // builtins_base di vm.py (liste/dict li gestisce la VM C++)
        "stampa", "num_testo", "testo_num", "testo_lunghezza", "testo_pezzo",
        "testo_trova", "testo_dividi", "testo_unisci", "testo_maiuscolo",
        "testo_minuscolo", "num_assoluto", "num_intero", "num_min",
        "num_max",
        // syscalls del kernel
        "os_scrivi", "os_disegna_rett", "os_disegna_testo",
        "os_schermo_pulisci", "os_tasti_num", "os_leggi_tasto",
        "os_tempo_ms", "os_pausa", "os_random", "os_file_leggi",
        "os_file_scrivi", "os_file_cancella", "os_file_lista", "os_avvia",
        "os_titolo", "os_bip", "os_tocco",
        "os_web_cerca_google", "os_web_cerca_youtube", "os_web_apri",
        "os_web_stato",
    ]

    // Permessi predefiniti per app (PERMESSI_PREDEFINITI di sicurezza.py)
    public static let permessiPredefiniti: [String: [String]] = [
        "google": ["rete", "grafica"],
        "youtube": ["rete", "grafica", "suono"],
        "security": ["file_leggi", "file_scrivi", "avvia_app"],
        "snake": ["grafica", "suono"],
        "demo": ["grafica"],
        "info": ["grafica"],
        "note": ["file_leggi", "file_scrivi"],
        "calcolatore": ["grafica"],
        "ciao": [],
        "prova": [],
    ]

    /// Domini che le app possono contattare (rete filtrata).
    public static let dominiConsentiti = [
        "google.com", "www.google.com", "youtube.com", "www.youtube.com",
        "img.youtube.com",
    ]

    // -----------------------------------------------------------
    // STATO
    // -----------------------------------------------------------
    /// nome app -> (bytecode, tipo)
    public var apps: [String: (Data, String)]
    public private(set) var processi: [Processo] = []
    public var pronto = true                  // True = shell in primo piano
    public var home = true                    // True = schermata home
    public var shellOutput: [String] = []
    public var shellRiga = ""
    public var filesystem: [String: String]
    public var permessi: [String: [String]]
    public var statoRete = "inattiva"         // inattiva | attiva | errore
    public var reteAttivaPer: String? = nil   // nome app mentre la rete gira
    public var toccoIndicato: (x: Int, y: Int)? = nil   // ultimo tocco libero
    /// Chiave di firma (.fvbs): senza chiave la verifica salta.
    public var chiaveFirma: Data? = nil
    public let tempoAvvio: TimeInterval       // epoch di avvio

    private var prossimoPid = 1

    // -----------------------------------------------------------
    // INIT
    // -----------------------------------------------------------
    public init(apps: [String: (Data, String)] = [:],
                chiaveFirma: Data? = nil) {
        self.apps = apps
        self.chiaveFirma = chiaveFirma
        self.permessi = Kernel.permessiPredefiniti
        self.filesystem = [
            "/favos/leggi.txt":
                "Benvenuto in FavOS!\nIl linguaggio e' Favilla:\n"
                + "impara saluta()\n    stampa(\"ciao\")\nfine",
            "/favos/appunti.txt": "",
        ]
        self.tempoAvvio = Date().timeIntervalSince1970
    }

    /// Orologio monotono (per le pause: time.monotonic di Python).
    static var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // -----------------------------------------------------------
    // INTERFACCIA: apertura home/shell
    // -----------------------------------------------------------
    public func homeAperta() -> Bool { pronto && home }

    public func apriHome() {
        if !pronto { terminaPrimoPiano() }
        home = true
    }

    public func apriShell() {
        if !pronto { terminaPrimoPiano() }
        home = false
    }

    @discardableResult
    public func avviaDaTocco(_ nome: String) -> String? {
        home = false
        return avviaApp(nome)
    }

    /// Le prime 9 app in ordine alfabetico (icone della home).
    public var nomiHome: [String] {
        Array(apps.keys.sorted().prefix(9))
    }

    // -----------------------------------------------------------
    // OUTPUT DI TESTO (shell o processo in primo piano)
    // -----------------------------------------------------------
    public func scrivi(_ testo: String) {
        if pronto {
            shellOutput.append(contentsOf: testo.components(separatedBy: "\n"))
            if shellOutput.count > 300 { shellOutput.removeFirst(shellOutput.count - 300) }
        } else {
            processi.last?.scriviConsole(testo)
        }
    }

    // -----------------------------------------------------------
    // APP: avvio / chiusura
    // -----------------------------------------------------------
    @discardableResult
    public func avviaApp(_ nome: String) -> String? {
        home = false
        guard let (pacchetto, tipo) = apps[nome] else {
            return "App sconosciuta: \(nome)"
        }
        // SICUREZZA: verifica firma del bytecode
        let (bytecode, stato) = Firma.verifica(pacchetto: pacchetto,
                                               chiave: chiaveFirma)
        if stato == .alterato {
            scrivi("[SICUREZZA] \(nome): bytecode manomesso, avvio rifiutato")
            return "bytecode alterato"
        }
        guard let p = Processo(pid: prossimoPid, nome: nome, tipo: tipo,
                               kernel: self) else {
            return "App corrotta: memoria esaurita"
        }
        prossimoPid += 1
        p.firma = stato.rawValue
        p.permessi = permessi[nome] ?? []
        guard p.macchina.carica(bytecode) else {
            return "App corrotta: \(p.macchina.errore)"
        }
        p.macchina.contesto(Unmanaged.passUnretained(p).toOpaque())
        for nome2 in Kernel.nomiSyscall { p.macchina.registra(nome2) }
        processi.append(p)
        pronto = false
        p.macchina.avvia()
        return nil
    }

    public func terminaPrimoPiano() {
        if !processi.isEmpty {
            archiviaOutput(processi.removeLast())
        }
        pronto = true
    }

    /// Quando un'app chiude, la sua console finisce nel registro shell.
    private func archiviaOutput(_ p: Processo) {
        var righe = p.output
        if !p.rigaInCorso.isEmpty { righe.append(p.rigaInCorso) }
        if !righe.isEmpty {
            shellOutput.append("--- \(p.nome) ---")
            shellOutput.append(contentsOf: righe)
        }
        if shellOutput.count > 300 {
            shellOutput.removeFirst(shellOutput.count - 300)
        }
    }

    // -----------------------------------------------------------
    // SCHEDULATORE: d'a ogni app una fetta di istruzioni
    // -----------------------------------------------------------
    public func schedula() {
        guard !pronto, let p = processi.last else {
            if processi.isEmpty { pronto = true }
            return
        }
        if Kernel.uptime < p.pausaFino { return }
        let ancora = p.macchina.esegui(3000)
        if !ancora {
            let morto = processi.removeLast()
            pronto = true
            archiviaOutput(morto)
            if !morto.macchina.ok, morto.errore == nil {
                morto.errore = morto.macchina.errore
            }
            if let err = morto.errore {
                scrivi("[Errore in \(morto.nome)] \(err)")
            }
        }
    }

    // -----------------------------------------------------------
    // INPUT DA TASTIERA
    // -----------------------------------------------------------
    public func premiTasto(_ testoRaw: String) {
        var testo = testoRaw
        if testo == "\r" || testo == "\n" {
            testo = "INVIO"
        } else if testo == "\u{08}" || testo == "\u{7f}" {
            testo = "CANCELLA"
        }
        if testo == "ESC" {
            if !pronto { terminaPrimoPiano() }
            return
        }
        if testo == "HOME" {
            apriHome()
            return
        }
        if home {
            toccoHome(testo)
            return
        }
        if pronto {
            tastoShell(testo)
        } else {
            processi.last?.codaInput.append(testo)
        }
    }

    /// Dalla home: un tasto numerico 1-9 avvia l'app di quella riga.
    private func toccoHome(_ testo: String) {
        let digit = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        if digit.contains(testo) {
            let nomi = nomiHome
            let i = Int(testo)! - 1
            if i < nomi.count {
                scrivi("> " + nomi[i])
                avviaDaTocco(nomi[i])
            } else {
                apriShell()
            }
        } else if testo == "INVIO" {
            apriShell()
        } else {
            // una lettera dalla home: passa alla shell e comincia a scrivere
            apriShell()
            tastoShell(testo)
        }
    }

    private func tastoShell(_ testo: String) {
        if testo == "INVIO" {
            let riga = shellRiga
            shellRiga = ""
            shellOutput.append("favos> " + riga)
            eseguiComando(riga)
        } else if testo == "CANCELLA" {
            if !shellRiga.isEmpty { shellRiga.removeLast() }
        } else {
            shellRiga += testo
        }
    }

    private func eseguiComando(_ riga: String) {
        let parole = riga.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard let primo = parole.first else { return }
        let cmd = primo.lowercased()
        let args = Array(parole.dropFirst())
        switch cmd {
        case "aiuto":
            scrivi("Comandi: aiuto | apps | app <nome> | file | leggi <f> | "
                   + "scrivi <f> <testo> | cancella <f> | info | pulisci")
        case "sicurezza":
            scrivi("Permessi attivi:")
            for nomeApp in apps.keys.sorted() {
                let elenco = permessi[nomeApp] ?? []
                scrivi("  \(nomeApp): "
                       + (elenco.joined(separator: ", ").isEmpty
                          ? "nessuno" : elenco.joined(separator: ", ")))
            }
            scrivi("Domini di rete ammessi: "
                   + Kernel.dominiConsentiti.sorted().joined(separator: ", "))
        case "apps":
            scrivi("App: " + apps.keys.sorted().joined(separator: ", "))
        case "app" where !args.isEmpty:
            if let errore = avviaApp(args[0]) { scrivi(errore) }
        case "file":
            let nomi = filesystem.keys.filter { $0.hasPrefix("/favos/") }
                .map { String($0.dropFirst("/favos/".count)) }.sorted()
            scrivi("File in /favos: "
                   + (nomi.isEmpty ? "(vuoto)" : nomi.joined(separator: ", ")))
        case "leggi" where !args.isEmpty:
            let percorso = percorsoSicuro(args[0])
            if let c = filesystem[percorso] { scrivi(c) }
            else { scrivi("File non trovato: " + args[0]) }
        case "scrivi" where !args.isEmpty:
            let percorso = percorsoSicuro(args[0])
            filesystem[percorso] = args.dropFirst().joined(separator: " ")
            scrivi("Scritto " + percorso)
        case "cancella" where !args.isEmpty:
            let percorso = percorsoSicuro(args[0])
            if filesystem.removeValue(forKey: percorso) != nil {
                scrivi("Cancellato " + percorso)
            } else {
                scrivi("File non trovato: " + args[0])
            }
        case "info":
            scrivi("FavOS 1.0 - kernel italiano per microcontrollori")
        case "pulisci":
            shellOutput = []
        default:
            scrivi("Comando sconosciuto: \(cmd) (usa: aiuto)")
        }
    }

    public func percorsoSicuro(_ percorsoRaw: String) -> String {
        var p = percorsoRaw.replacingOccurrences(of: "..", with: "")
        if !p.hasPrefix("/") { p = "/favos/" + p }
        return p
    }

    // -----------------------------------------------------------
    // INTERFACCIA: il chiamante (wrapper) tocca lo schermo.
    // coordinate FavOS 320x240.
    // -----------------------------------------------------------
    public func tocco(x xRaw: Int, y yRaw: Int) {
        let x = xRaw, y = yRaw
        if !pronto {
            if let tasto = toccoTasti(x, y) {
                premiTasto(tasto)
                return
            }
            toccoIndicato = (x, y)      // le app leggono con os_tocco()
            return
        }
        if y >= Kernel.rigaNavY && y < Kernel.tastiY {
            // riga di navigazione: [ < home | console | titolo ]
            let zona = x / (Kernel.larghezza / 3)
            if zona == 0 { apriHome() }
            else if zona == 1 { apriShell() }
            else { apriHome() }
            return
        }
        if let tasto = toccoTasti(x, y) {
            premiTasto(tasto)
            return
        }
        // widget (home: icone app)
        toccoIndicato = (x, y)
        if home { toccoCellHome(x, y) }
    }

    /// Il tasto FavOS premuto sulla tastiera a schermo, se dentro.
    private func toccoTasti(_ x: Int, _ y: Int) -> String? {
        for k in Kernel.tastiPos {
            if x >= k.x, x < k.x + k.w, y >= k.y, y < k.y + k.h {
                return Kernel.tastoDaEtichetta(k.etichetta)
            }
        }
        return nil
    }

    /// Tocco sulla home: lancia l'app della cella toccata.
    private func toccoCellHome(_ x: Int, _ y: Int) {
        let nomi = nomiHome
        for (i, c) in Kernel.homeCelle.enumerated()
        where x >= c.x, x < c.x + c.w, y >= c.y, y < c.y + c.h {
            if i < nomi.count {
                scrivi("> " + nomi[i])
                avviaDaTocco(nomi[i])
            }
            return
        }
    }
}

// ===============================================================
// PROCESSO — un'app in esecuzione, con la sua VM e i suoi buffer
// ===============================================================
public final class Processo {
    public let pid: Int
    public let nome: String
    public let macchina: Macchina
    public let tipo: String                   // "console" | "grafica"
    public var errore: String?
    public var firma = "non_firmato"
    public var permessi: [String] = []
    public var output: [String] = []
    public var rigaInCorso = ""
    public let framebuffer: Framebuffer       // zona app 320x176
    public var codaInput: [String] = []
    public var pausaFino: TimeInterval = 0
    public var suono: (freq: Int, ms: Int)?
    public var titolo = ""

    unowned let kernel: Kernel

    init?(pid: Int, nome: String, tipo: String, kernel: Kernel) {
        guard let m = Macchina() else { return nil }
        self.pid = pid
        self.nome = nome
        self.tipo = tipo
        self.macchina = m
        self.kernel = kernel
        self.framebuffer = Framebuffer(larghezza: Kernel.larghezza,
                                       altezza: Kernel.altezzaApp)
    }

    public func scriviConsole(_ testo: String) {
        rigaInCorso += testo
        while let nl = rigaInCorso.firstIndex(of: "\n") {
            output.append(String(rigaInCorso[..<nl]))
            rigaInCorso = String(rigaInCorso[rigaInCorso.index(after: nl)...])
        }
        if output.count > 300 { output.removeFirst(output.count - 300) }
    }

    /// Nota: in Python gli errori dei builtins (es. testo_lunghezza su un
    /// numero) uccidono l'app; qui il ponte non puo' lanciare eccezioni
    /// dentro la VM C++, quindi l'errore finisce in console e la syscall
    /// ritorna niente.
    private func logErrore(_ messaggio: String) {
        scriviConsole("[errore] " + messaggio)
    }

    // -----------------------------------------------------------
    // TUTTE LE SYSCALL DEL BYTECODE
    // -----------------------------------------------------------
    func syscall(_ nome: String, _ args: [Valore]) -> Valore {
        let a = args
        switch nome {

        // ---- builtins_base (vm.py) ----
        case "stampa", "os_scrivi":
            scriviConsole(a.map { $0.comeTesto }.joined(separator: " "))
            return .niente

        case "num_testo":
            return .testo(a.first?.comeTesto ?? "")

        case "testo_num":
            guard let s = a.first?.comeTesto, let d = Double(s) else {
                return .niente
            }
            return .numero(d)

        case "testo_lunghezza":
            guard case .testo(let s)? = a.first else {
                logErrore("testo_lunghezza vuole un testo")
                return .niente
            }
            return .numero(Double(s.count))

        case "testo_pezzo":
            guard case .testo(let s)? = a.first, a.count >= 3 else {
                logErrore("testo_pezzo vuole un testo")
                return .niente
            }
            let chars = Array(s)
            let i = max(0, min(chars.count, a[1].numeroIntera))
            let f = max(i, min(chars.count, a[2].numeroIntera))
            return .testo(String(chars[i..<f]))

        case "testo_trova":
            guard case .testo(let s)? = a.first, a.count >= 2,
                  case .testo(let cerca) = a[1] else {
                logErrore("testo_trova vuole un testo")
                return .niente
            }
            guard let r = s.range(of: cerca) else { return .numero(-1) }
            return .numero(Double(s.distance(from: s.startIndex,
                                             to: r.lowerBound)))

        case "testo_dividi":
            guard case .testo(let s)? = a.first, a.count >= 2 else {
                logErrore("testo_dividi vuole un testo")
                return .niente
            }
            let pezzi = s.components(separatedBy: a[1].comeTesto)
            return .lista(pezzi.map { .testo($0) })

        case "testo_unisci":
            guard case .lista(let l)? = a.first, a.count >= 2 else {
                logErrore("testo_unisci vuole una lista")
                return .niente
            }
            let sep = a[1].comeTesto
            return .testo(l.map { $0.comeTesto }.joined(separator: sep))

        case "testo_maiuscolo":
            guard case .testo(let s)? = a.first else {
                logErrore("testo_maiuscolo vuole un testo")
                return .niente
            }
            return .testo(s.uppercased())

        case "testo_minuscolo":
            guard case .testo(let s)? = a.first else {
                logErrore("testo_minuscolo vuole un testo")
                return .niente
            }
            return .testo(s.lowercased())

        case "num_assoluto":
            guard case .numero(let d)? = a.first else {
                logErrore("num_assoluto vuole un numero")
                return .niente
            }
            return .numero(abs(d))

        case "num_intero":
            guard case .numero(let d)? = a.first else {
                logErrore("num_intero vuole un numero")
                return .niente
            }
            return .numero(d.rounded(.towardZero))

        case "num_min":
            guard a.count >= 2, case .numero(let x) = a[0],
                  case .numero(let y) = a[1] else { return a.first ?? .niente }
            return .numero(min(x, y))

        case "num_max":
            guard a.count >= 2, case .numero(let x) = a[0],
                  case .numero(let y) = a[1] else { return a.first ?? .niente }
            return .numero(max(x, y))

        // ---- disegno ----
        case "os_disegna_rett":
            guard a.count >= 5 else { return .niente }
            framebuffer.rett(a[0].numeroIntera, a[1].numeroIntera,
                             a[2].numeroIntera, a[3].numeroIntera,
                             Colori.dagliApp(a[4]))
            return .niente

        case "os_disegna_testo":
            guard a.count >= 3 else { return .niente }
            let colore = a.count >= 4
                ? Colori.dagliApp(a[3])
                : Colori.dagliApp(.testo("bianco"))
            let scala = a.count >= 5 ? a[4].numeroIntera : 1
            framebuffer.testo(a[0].numeroIntera, a[1].numeroIntera,
                              a[2].comeTesto, colore, scala: scala)
            return .niente

        case "os_schermo_pulisci":
            let colore = a.isEmpty
                ? Colori.dagliApp(.testo("nero"))
                : Colori.dagliApp(a[0])
            framebuffer.riempi(colore)
            return .niente

        // ---- tastiera / tempo ----
        case "os_tasti_num":
            return .numero(Double(codaInput.count))

        case "os_leggi_tasto":
            if codaInput.isEmpty { return .niente }
            return .testo(codaInput.removeFirst())

        case "os_tempo_ms":
            let ms = (Date().timeIntervalSince1970 - kernel.tempoAvvio) * 1000
            return .numero(ms.rounded())

        case "os_pausa":
            let ms = max(0, a.first?.numeroIntera ?? 0)
            pausaFino = Kernel.uptime + Double(ms) / 1000.0
            return .niente

        case "os_random":
            let n = a.first?.numeroIntera ?? 0
            guard n > 0 else { return .numero(0) }
            return .numero(Double(Int.random(in: 0..<n)))

        // ---- filesystem ----
        case "os_file_leggi":
            guard let percorso = a.first else { return .niente }
            guard let c = kernel.filesystem[kernel.percorsoSicuro(percorso.comeTesto)]
            else { return .niente }
            return .testo(c)

        case "os_file_scrivi":
            guard a.count >= 2 else { return .niente }
            kernel.filesystem[kernel.percorsoSicuro(a[0].comeTesto)] =
                a[1].comeTesto
            return .niente

        case "os_file_cancella":
            guard let percorso = a.first else { return .niente }
            guard let v = kernel.filesystem
                .removeValue(forKey: kernel.percorsoSicuro(percorso.comeTesto))
            else { return .niente }
            return .testo(v)

        case "os_file_lista":
            let percorso = kernel.percorsoSicuro(
                a.first?.comeTesto ?? "/favos")
            let prefisso = percorso.hasSuffix("/")
                ? percorso : percorso + "/"
            let nomi = kernel.filesystem.keys
                .filter { $0.hasPrefix(prefisso) }
                .map { String($0.dropFirst(prefisso.count)) }
                .sorted()
            return .lista(nomi.map { .testo($0) })

        // ---- sistema ----
        case "os_avvia":
            guard let nomeApp = a.first else { return .niente }
            if let errore = kernel.avviaApp(nomeApp.comeTesto) {
                return .testo(errore)
            }
            return .niente

        case "os_titolo":
            titolo = a.first?.comeTesto ?? ""
            return .niente

        case "os_bip":
            let freq = a.first?.numeroIntera ?? 440
            let ms = a.count >= 2 ? a[1].numeroIntera : 80
            suono = (freq, ms)
            return .niente

        case "os_tocco":
            guard let t = kernel.toccoIndicato else { return .niente }
            kernel.toccoIndicato = nil
            return .lista([.numero(Double(t.x)), .numero(Double(t.y))])

        // ---- rete (nel wrapper Swift v1 non e' implementata) ----
        case "os_web_cerca_google", "os_web_cerca_youtube", "os_web_apri":
            guard permessi.contains("rete") else { return .testo("negato") }
            codaInput.append(
                "WEBERRORE:rete non disponibile nel wrapper Swift")
            return .testo("partita")

        case "os_web_stato":
            return .testo(kernel.statoRete)

        default:
            return .niente
        }
    }
}
