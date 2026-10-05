import Foundation
import SwiftUI

/// Una spedizione tracciata dall'utente.
struct Shipment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Numero di tracciamento (qualsiasi formato).
    var trackingNumber: String
    /// Slug della rete (vedi `CarrierCatalog`).
    var carrierID: String
    /// Nome personalizzato mostrato in lista (es. "Auricolari").
    var label: String = ""
    /// Note libere.
    var notes: String = ""
    var status: Status = .inTransit
    var createdAt: Date = Date()

    enum Status: String, Codable, CaseIterable, Identifiable {
        case pending = "In attesa"
        case inTransit = "In transito"
        case delivered = "Consegnata"
        case problem = "Problema"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .pending: return "clock.fill"
            case .inTransit: return "arrow.triangle.2.circlepath"
            case .delivered: return "checkmark.circle.fill"
            case .problem: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .pending: return .gray
            case .inTransit: return .blue
            case .delivered: return .green
            case .problem: return .red
            }
        }
    }

    /// Rete associata (cerca nel catalogo).
    var carrier: Carrier? {
        CarrierCatalog.byId(carrierID)
    }

    /// Titolo mostrato in lista: etichetta personale o rete + numero.
    var displayTitle: String {
        if !label.isEmpty { return label }
        if let carrier { return "\(carrier.name) · \(trackingNumber)" }
        return trackingNumber
    }
}
