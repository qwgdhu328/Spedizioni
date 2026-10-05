import Foundation
import SwiftUI

/// Stato condiviso: lista spedizioni con persistenza JSON
/// nel container dell'app (Application Support/Spedizioni).
@MainActor
final class ShipmentStore: ObservableObject {
    static let shared = ShipmentStore()

    @Published private(set) var shipments: [Shipment] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Spedizioni", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("shipments.json")
        load()
    }

    // MARK: - CRUD

    func add(trackingNumber: String, carrierID: String, label: String) {
        let shipment = Shipment(
            trackingNumber: trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            carrierID: carrierID,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        shipments.insert(shipment, at: 0)
        save()
    }

    func update(_ shipment: Shipment) {
        guard let idx = shipments.firstIndex(where: { $0.id == shipment.id }) else { return }
        shipments[idx] = shipment
        save()
    }

    func delete(at offsets: IndexSet) {
        shipments.remove(atOffsets: offsets)
        save()
    }

    func delete(_ shipment: Shipment) {
        shipments.removeAll { $0.id == shipment.id }
        save()
    }

    func deleteAll() {
        shipments.removeAll()
        save()
    }

    // MARK: - Persistenza

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Shipment].self, from: data)
        else { return }
        shipments = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(shipments).write(to: fileURL, options: .atomic)
        } catch {
            print("Salvataggio spedizioni fallito: \(error)")
        }
    }
}
