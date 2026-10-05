import SwiftUI

/// Dettaglio spedizione: stato, tracciamento IN-APP
/// (API + mappa live) e note.
struct ShipmentDetailView: View {
    @EnvironmentObject private var store: ShipmentStore
    @Environment(\.dismiss) private var dismiss

    @State private var shipment: Shipment
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

            // ── Tracciamento in-app ──
            Section {
                GlassEffectContainer(spacing: 12) {
                    NavigationLink {
                        TrackingView(
                            number: shipment.trackingNumber,
                            carrier: carrier
                        )
                    } label: {
                        Label(
                            "Traccia in-app — ogni movimento in dettaglio",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
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
