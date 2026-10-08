// Valore.swift — Il valore dinamico di Favilla lato Swift, le conversioni
// con la struct C FavVal e il router delle syscalls (la C chiama qui
// quando il bytecode invoca una syscall registrata).

import Foundation
import CFavOSVM

/// Valore che passa fra il bytecode e il kernel Swift.
public enum Valore: Equatable {
    case niente
    case numero(Double)
    case testo(String)
    case lista([Valore])
}

// ---------------------------------------------------------------
// FavVal (struct C) -> Valore
// ---------------------------------------------------------------
extension FavVal {
    /// Il campo testo (tupla CChar di 64) come Swift String.
    public var stringa: String {
        withUnsafeBytes(of: testo) { raw in
            String(cString: raw.baseAddress!
                .assumingMemoryBound(to: CChar.self))
        }
    }

    /// Una FavVal di testo (scrive in coda, il resto resta zero).
    public static func diTesto(_ s: String) -> FavVal {
        var v = FavVal()
        v.tipo = 2
        let bytes = Array(s.utf8)
        let max = Int(FAV_VAL_TESTO) - 1
        let n = min(bytes.count, max)
        withUnsafeMutableBytes(of: &v.testo) { raw in
            let dst = raw.bindMemory(to: UInt8.self)
            for i in 0..<n { dst[i] = bytes[i] }
        }
        return v
    }
}

extension Valore {
    /// Converte l'argomento C ricevuto dalla VM (le liste sono giunte
    /// dalla VM col limite di profondita' del ponte C).
    public init(fav v: FavVal) {
        switch v.tipo {
        case 1:
            self = .numero(v.num)
        case 2:
            self = .testo(v.stringa)
        case 3:
            guard let elem = v.elementi, v.n_elementi > 0 else {
                self = .lista([])
                return
            }
            var items: [Valore] = []
            items.reserveCapacity(Int(v.n_elementi))
            for i in 0..<Int(v.n_elementi) {
                items.append(Valore(fav: elem[i]))
            }
            self = .lista(items)
        default:
            self = .niente
        }
    }

    /// Versione testo del valore (VM._testo di Python).
    public var comeTesto: String {
        switch self {
        case .testo(let s): return s
        case .numero(let d):
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        case .lista: return "lista"
        case .niente: return "niente"
        }
    }
}

// ---------------------------------------------------------------
// Valore -> FavVal (scrittura della risposta nel pool dell'host)
// ---------------------------------------------------------------
extension Valore {
    /// Scrive la risposta della syscall: `pool` e' la memoria dell'host
    /// (valida solo durante la chiamata) in cui appoggio le liste.
    public func scriviRisposta(_ risposta: UnsafeMutablePointer<FavVal>,
                               pool: UnsafeMutablePointer<FavVal>?,
                               cap: Int32) {
        risposta.pointee = FavVal()
        switch self {
        case .niente:
            risposta.pointee.tipo = 0
        case .numero(let d):
            risposta.pointee.tipo = 1
            risposta.pointee.num = d
        case .testo(let s):
            risposta.pointee = .diTesto(s)
        case .lista(let items):
            guard let pool = pool, cap > 0 else { return }
            var cursore: Int32 = 0
            let (ptr, n) = self.compila(items, in: pool, cap: cap,
                                        cursore: &cursore)
            risposta.pointee.tipo = 3
            risposta.pointee.elementi = ptr
            risposta.pointee.n_elementi = n
        }
    }

    /// Pre-alloca `items.count` celle contigue nel pool e le riempie
    /// (le sottoliste occupano le celle dopo, cosi' il blocco resta
    /// continuo come si aspetta il ponte C).
    private func compila(_ items: [Valore],
                         in pool: UnsafeMutablePointer<FavVal>,
                         cap: Int32, cursore: inout Int32)
        -> (UnsafeMutablePointer<FavVal>?, Int32) {
        let inizio = cursore
        var n: Int32 = 0
        for _ in items where cursore < cap {
            cursore += 1
            n += 1
        }
        for i in 0..<Int(n) {
            switch items[i] {
            case .niente:
                pool[Int(inizio) + i] = FavVal()
            case .numero(let d):
                var c = FavVal()
                c.tipo = 1
                c.num = d
                pool[Int(inizio) + i] = c
            case .testo(let s):
                pool[Int(inizio) + i] = .diTesto(s)
            case .lista(let sotto):
                let (ptr, k) = compila(sotto, in: pool, cap: cap,
                                       cursore: &cursore)
                var c = FavVal()
                c.tipo = 3
                c.elementi = ptr
                c.n_elementi = k
                pool[Int(inizio) + i] = c
            }
        }
        return (pool.advanced(by: Int(inizio)), n)
    }
}

// ---------------------------------------------------------------
// Router: la C chiama questa funzione per ogni syscall del bytecode
// ---------------------------------------------------------------
let routerFavOS: FavChiamata = { utente, nomeC, n, arg, risposta, pool, cap in
    guard let utente = utente, let nomeC = nomeC,
          let risposta = risposta else { return }
    let processo = Unmanaged<Processo>.fromOpaque(utente)
        .takeUnretainedValue()
    let nome = String(cString: nomeC)
    var args: [Valore] = []
    if let arg = arg, n > 0 {
        for i in 0..<Int(n) { args.append(Valore(fav: arg[i])) }
    }
    let esito = processo.syscall(nome, args)
    esito.scriviRisposta(risposta, pool: pool, cap: cap)
}
