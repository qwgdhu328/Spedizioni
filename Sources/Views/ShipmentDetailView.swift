import SwiftUI

/// Dettaglio spedizione: stato, tracciamento su vetro
/// (rete + 17Track universale) e note.
struct ShipmentDetailView: View {
    @EnvironmentObject private var store: ShipmentStore
    @Environment(\.dismiss) private var dismiss

    @State private var shipment: Shipment
    @State private var safariURL: URL?
    @State private var showDeleteConfirm = false

    init(shipment: Shipment) {
        _shipment = State(initialValue: shipment)
    }

    private var carrier: Carrier? { shipment.carrier }

    var body: some View {
        List {
            // ── Intestazione ──
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(carrier?.flag ?? "📦")
                            .font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shipment.label.isEmpty ? (carrier?.name ?? "Rete sconosciuta") : shipment.label)
                                .font(.title3.bold())
                            Text(shipment.trackingNumber)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let carrier {
                        Label("\(carrier.category.title) · \(carrier.country)", systemImage: carrier.category.systemImage)
                            .font(.caption)
                            .foregroundStyle(carrier.category.color)
                    }
                    Label("Aggiunta il \(shipment.createdAt.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // ── Azioni glass ──
            Section {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 10) {
                        Button {
                            if let carrier,
                               let url = carrier.trackingURL(for: shipment.trackingNumber) {
                                safariURL = url
                            } else if let url = Carrier.universalTrackingURL(for: shipment.trackingNumber) {
                                safariURL = url
                            }
                        } label: {
                        Label(
                            carrier.map { "Traccia su \($0.name)" } ?? "Traccia spedizione",
                            systemImage: "magnifyingglass"
                        )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)

                        Button {
                            if let url = Carrier.universalTrackingURL(for: shipment.trackingNumber) {
                                safariURL = url
                            }
                        } label: {
                            Label("17Track (universale)", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
            }

            // ── Stato ──
            Section("Stato") {
                Picker("Stato", selection: $shipment.status) {
                    ForEach(Shipment.Status.allCases) { status in
                        Label(status.rawValue, systemImage: status.systemImage)
                            .tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: shipment.status) {
                    store.update(shipment)
                }
            }

            // ── Dati ──
            Section("Etichetta") {
                TextField("Es. Auricolari, Regalo…", text: $shipment.label)
                    .onChange(of: shipment.label) {
                        store.update(shipment)
                    }
            }

            Section("Note") {
                TextField("Aggiungi note…", text: $shipment.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: shipment.notes) {
                        store.update(shipment)
                    }
            }

            // ── Elimina ──
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Elimina spedizione", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .navigationTitle(carrier?.name ?? "Spedizione")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { safariURL.map { IdentifiedURL(url: $0) } },
            set: { safariURL = $0?.url }
        )) { item in
            SafariView(url: item.url)
        }
        .confirmationDialog(
            "Eliminare questa spedizione?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                store.delete(shipment)
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        }
    }
}

/// Wrapper per usare URL in `.sheet(item:)`.
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview {
    NavigationStack {
        ShipmentDetailView(shipment: Shipment(
            trackingNumber: "1Z999AA10123456784",
            carrierID: "ups",
            label: "Prova"
        ))
    }
    .environmentObject(ShipmentStore())
}
