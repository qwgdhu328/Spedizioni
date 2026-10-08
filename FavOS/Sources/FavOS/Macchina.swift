// Macchina.swift — Il wrapper Swift della VM Favilla C++: ogni app in
// esecuzione ha la sua Macchina (FavHost*). Il bytecode viene copiato
// dal ponte C, quindi il Data puo' essere subito rilasciato.

import Foundation
import CFavOSVM

public final class Macchina {
    private let host: OpaquePointer

    public init?() {
        guard let h = favhost_crea() else { return nil }
        host = h
    }

    deinit {
        favhost_distruggi(host)
    }

    /// Imposta il contesto delle syscalls: `utente` arriva intatto nella
    /// callback (ci mettiamo il Processo che chiama la syscall).
    public func contesto(_ utente: UnsafeMutableRawPointer?) {
        favhost_contesto(host, utente, routerFavOS)
    }

    /// Registra il nome di una syscall (la funzione C e' un thunk per
    /// slot scelto dal ponte): va registrata OGNI nome usabile.
    @discardableResult
    public func registra(_ nome: String) -> Bool {
        nome.withCString { favhost_registra(host, $0) != 0 }
    }

    public func carica(_ dati: Data) -> Bool {
        dati.withUnsafeBytes { buf in
            guard let base = buf.baseAddress?
                .assumingMemoryBound(to: UInt8.self) else { return 0 }
            return favhost_carica(host, base, buf.count)
        } != 0
    }

    public func avvia() {
        favhost_avvia(host)
    }

    /// Esegue fino a `istruzioni` istruzioni. Ritorna false se il
    /// programma e' finito (o la VM ha fallito).
    @discardableResult
    public func esegui(_ istruzioni: UInt32) -> Bool {
        favhost_esegui(host, istruzioni) != 0
    }

    public var ok: Bool { favhost_ok(host) != 0 }
    public var finito: Bool { favhost_finito(host) != 0 }

    public var errore: String {
        guard let p = favhost_errore(host) else { return "errore sconosciuto" }
        return String(cString: p)
    }
}
