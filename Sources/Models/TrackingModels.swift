import Foundation
import SwiftUI

/// Un singolo movimento della spedizione (checkpoint dell'API).
struct TrackingEvent: Identifiable, Hashable, Codable {
    let id: String
    /// Momento del movimento (epoch, se fornito).
    let time: Date?
    /// Testo tempo grezzo dall'API (usato se il parsing data fallisce).
    let timeString: String
    /// Titolo del checkpoint (descTitle/standerdDesc).
    let title: String
    /// Descrizione DETTAGLIATA del movimento (desc).
    let detail: String
    /// Codice azione grezzo dell'API (es. INFO_RECEIVED).
    let actionCode: String
    /// Coordinate, se l'API le fornisse (opzionale, difensivo).
    let latitude: Double?
    let longitude: Double?

    var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }
}

/// Esito completo del tracciamento di una spedizione.
struct TrackingResult: Hashable {
    let number: String
    /// Stato grezzo dell'API (es. IN_TRANSIT).
    let status: String
    /// Descrizione stato in italiano.
    let statusDesc: String
    /// Descrizione quando non ci sono ancora movimenti.
    let emptyDescription: String
    /// Avanzamento 0...1 (se fornito).
    let progressRate: Double?
    /// Tappe del percorso (progressPointList).
    let progressPoints: [String]
    /// Paese di origine/destinazione (se forniti).
    let originCountry: String?
    let destCountry: String?
    /// Movimenti ordinati dal più recente.
    let events: [TrackingEvent]
    /// Fonte dati mostrata in UI (può essere annotata in fallback).
    var source: String

    /// Colore dello stato per la chip di riepilogo.
    var statusColor: Color {
        let s = status.uppercased()
        if s == "DELIVERED" { return .green }
        if s.contains("EXCEPTION") || s.contains("FAIL") { return .red }
        if s.contains("OUT_FOR_DELIVERY") || s.contains("PICKUP") { return .blue }
        if s.contains("INFO") || s.contains("PREPAR") { return .gray }
        return .orange
    }

    var statusIcon: String {
        let s = status.uppercased()
        if s == "DELIVERED" { return "checkmark.circle.fill" }
        if s.contains("EXCEPTION") || s.contains("FAIL") { return "exclamationmark.triangle.fill" }
        if s.contains("OUT_FOR_DELIVERY") { return "truck.box.fill" }
        return "arrow.triangle.2.circlepath"
    }
}

/// Errori del tracciamento, con messaggi in italiano.
enum TrackingError: LocalizedError {
    case invalidNumber
    case network(String)
    case http(Int)
    case emptyResponse
    case decoding(String)
    case config(String)

    var errorDescription: String? {
        switch self {
        case .invalidNumber:
            return "Numero di tracciamento non valido."
        case let .network(msg):
            return "Errore di rete: \(msg)"
        case let .http(code):
            return "L'API ha risposto con errore HTTP \(code)."
        case .emptyResponse:
            return "L'API non ha restituito dati per questo numero."
        case let .decoding(msg):
            return "Risposta dell'API non interpretabile: \(msg)"
        case let .config(msg):
            return msg
        }
    }
}
