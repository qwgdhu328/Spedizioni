import Foundation
import SwiftUI

/// Una rete (corriere o po statale) supportata dall'app.
struct Carrier: Identifiable, Hashable, Codable {
    /// Slug stabile usato come chiave nelle spedizioni.
    let id: String
    let name: String
    /// Emoji della bandiera del paese principale.
    let flag: String
    /// Paese (sezione del catalogo).
    let country: String
    let category: CarrierCategory
    /// URL di tracciamento con `{NUM}` sostituito dal numero.
    let trackURL: String
    /// La rete accetta solo numeri di un formato particolare
    /// (es. ID ordine per i marketplace); utile come nota in UI.
    let note: String?

    init(
        id: String,
        name: String,
        flag: String,
        country: String,
        category: CarrierCategory,
        trackURL: String,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.flag = flag
        self.country = country
        self.category = category
        self.trackURL = trackURL
        self.note = note
    }

    /// URL di tracciamento per il numero dato (percent-encoded).
    func trackingURL(for number: String) -> URL? {
        let encoded = number.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? number
        return URL(string: trackURL.replacingOccurrences(of: "{NUM}", with: encoded))
    }

    /// Fallback universale: 17Track supporta centinaia di reti.
    static func universalTrackingURL(for number: String) -> URL? {
        let encoded = number.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? number
        return URL(string: "https://www.17track.net/en?nums=\(encoded)")
    }
}

/// Categoria della rete: determina icona SF Symbol e colore.
enum CarrierCategory: String, Codable, CaseIterable, Identifiable {
    case postale
    case corriere
    case espress
    case ecommerce
    case logistica

    var id: String { rawValue }

    var title: String {
        switch self {
        case .postale: return "Postale"
        case .corriere: return "Corriere"
        case .espress: return "Espress"
        case .ecommerce: return "E-commerce"
        case .logistica: return "Logistica"
        }
    }

    var systemImage: String {
        switch self {
        case .postale: return "envelope.fill"
        case .corriere: return "shippingbox.fill"
        case .espress: return "bolt.fill"
        case .ecommerce: return "cart.fill"
        case .logistica: return "truck.box.fill"
        }
    }

    var color: Color {
        switch self {
        case .postale: return .blue
        case .corriere: return .orange
        case .espress: return .red
        case .ecommerce: return .purple
        case .logistica: return .teal
        }
    }
}
