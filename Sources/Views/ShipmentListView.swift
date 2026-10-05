import SwiftUI

/// Tab "Spedizioni": riepilogo su vetro, lista delle spedizioni
/// e pulsante + (glass) per aggiungerne una nuova.
struct ShipmentListView: View {
    @EnvironmentObject private var store: ShipmentStore
    @State private var showAdd = false
    @State private var searchText = ""

    private var filtered: [Shipment] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.shipments }
        return store.shipments.filter {
            $0.label.lowercased().contains(q)
                || $0.trackingNumber.lowercased().contains(q)
                || ($0.carrier?.name.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.shipments.isEmpty {
                    Section {
                        summaryCard
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Le tue spedizioni") {
                    if filtered.isEmpty {
                        ContentUnavailableView {
                            Label("Nessuna spedizione", systemImage: "shippingbox")
                        } description: {
                            Text(searchText.isEmpty
                                 ? "Tocca + per aggiungere il tuo primo pacco."
                                 : "Nessun risultato per “\(searchText)”.")
                        }
                    }
                    ForEach(filtered) { shipment in
                        NavigationLink {
                            ShipmentDetailView(shipment: shipment)
                        } label: {
                            row(for: shipment)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach { store.delete($0) }
                    }
                }
            }
            .navigationTitle("Spedizioni")
            .searchable(text: $searchText, prompt: "Cerca pacco, rete, numero…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Aggiungi spedizione")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddShipmentView()
            }
        }
    }

    // MARK: - Riepilogo su vetro

    private var summaryCard: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                stat(
                    value: "\(store.shipments.count)",
                    label: "Totali",
                    systemImage: "shippingbox.fill",
                    tint: .blue
                )
                stat(
                    value: "\(store.shipments.filter { $0.status == .inTransit }.count)",
                    label: "In transito",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .orange
                )
                stat(
                    value: "\(store.shipments.filter { $0.status == .delivered }.count)",
                    label: "Consegnati",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func stat(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Riga

    private func row(for shipment: Shipment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shipment.carrier?.category.systemImage ?? "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    (shipment.carrier?.category.color ?? .gray).gradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(shipment.displayTitle)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(shipment.carrier?.flag ?? "📦") \(shipment.carrier?.name ?? "Rete sconosciuta")")
                    Text("·")
                    Text(shipment.trackingNumber)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: shipment.status.systemImage)
                .foregroundStyle(shipment.status.color)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ShipmentListView()
        .environmentObject(ShipmentStore())
}
