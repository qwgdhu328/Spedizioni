// Firma.swift — La firma del bytecode di FavOS (port di sicurezza.py).
// Formato del pacchetto firmato:
//   FVS1 | u16 little-endian | firma HMAC-SHA256 | bytecode
// Se un byte del bytecode cambia, la firma non torna piu' e
// l'avvio viene rifiutato ("alterato").

import Foundation
import CryptoKit

public enum Firma {

    public enum Stato: String {
        case firmato
        case nonFirmato = "non_firmato"
        case alterato
    }

    public static let magico = Data("FVS1".utf8)

    /// Verifica un pacchetto .fvbs: ritorna lo stato e il bytecode nudo.
    /// Senza chiave la verifica non e' possibile: il pacchetto firmato
    /// viene trattato come "non_firmato" (gira comunque, come in Python
    /// un'app non firmata).
    public static func verifica(pacchetto: Data,
                                chiave: Data?) -> (Data, Stato) {
        guard pacchetto.count >= 6, pacchetto.prefix(4) == magico else {
            return (pacchetto, .nonFirmato)
        }
        let lung = Int(pacchetto[4]) | (Int(pacchetto[5]) << 8)
        guard lung > 0, pacchetto.count >= 6 + lung else {
            return (pacchetto, .nonFirmato)
        }
        let firma = pacchetto.subdata(in: 6..<(6 + lung))
        let dati = pacchetto.subdata(in: (6 + lung)..<pacchetto.count)
        guard let chiave = chiave, !chiave.isEmpty else {
            return (dati, .nonFirmato)
        }
        let attesa = Data(HMAC<SHA256>.authenticationCode(
            for: dati, using: SymmetricKey(data: chiave)))
        return (dati, uguale(firma, attesa) ? .firmato : .alterato)
    }

    /// Firma dei bytecode crudi: ritorna il pacchetto .fvbs.
    public static func firma(_ dati: Data, chiave: Data) -> Data {
        let mac = Data(HMAC<SHA256>.authenticationCode(
            for: dati, using: SymmetricKey(data: chiave)))
        var out = magico
        out.append(UInt8(mac.count & 0xFF))
        out.append(UInt8((mac.count >> 8) & 0xFF))
        out.append(mac)
        out.append(dati)
        return out
    }

    /// Confronto a tempo costante (hmac.compare_digest di Python).
    private static func uguale(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
