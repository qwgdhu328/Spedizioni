import SwiftUI

/// Foglio di aggiunta: numero, rete (tutte le reti nel picker)
/// ed etichetta. Bottoni glass nativi iOS 26.
struct AddShipmentView: View {
    @EnvironmentObject private var store: ShipmentStore
    @Environment(\.dismiss) private var dismiss

    @State private var trackingNumber = ""
    @State private var carrierID = ""
    @State private var label = ""

    private var selectedCarrier: Carrier? {
        CarrierCatalog.byId(carrierID)
    }

    private var canSave: Bool {
        !trackingNumber.trimmingCharacters(in: .whitespaces).isEmpty && !carrierID.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rete di spedizione") {
                    NavigationLink {
                        CarrierPickerView(selection: $carrierID)
                    } label: {
                        HStack {
                            Text("Scegli la rete")
                            Spacer()
                            if let carrier = selectedCarrier {
                                Text("\(carrier.flag) \(carrier.name)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Obbligatoria")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let note = selectedCarrier?.note {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Spedizione") {
                    TextField("Numero di tracciamento", text: $trackingNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Etichetta (es. Auricolari, Regalo…)", text: $label)
                }
            }
            .navigationTitle("Nuova spedizione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .buttonStyle(.glass)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        store.add(
                            trackingNumber: trackingNumber,
                            carrierID: carrierID,
                            label: label
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

#Preview {
    AddShipmentView()
        .environmentObject(ShipmentStore())
}
