import SwiftUI

/// Tab "Impostazioni": informazioni, azioni su dati e stato del
/// design Liquid Glass.
struct SettingsView: View {
    @EnvironmentObject private var store: ShipmentStore
    @State private var showDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section("Dati") {
                    LabeledContent("Spedizioni salvate", value: "\(store.shipments.count)")
                    LabeledContent("Reti disponibili", value: "\(CarrierCatalog.all.count)")

                    Button(role: .destructive) {
                        showDeleteAll = true
                    } label: {
                        Label("Elimina tutte le spedizioni", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(store.shipments.isEmpty)
                }

                Section("Info") {
                    LabeledContent("App", value: "Spedizioni")
                    LabeledContent("Design", value: "Liquid Glass (iOS 26)")
                    LabeledContent("Versione", value: appVersion)
                    LabeledContent("Dati", value: "Solo su dispositivo")
                }

                Section {
                    Text("""
                    Le spedizioni sono salvate in locale \
                    (JSON nel container dell'app): nessun dato \
                    lascia il dispositivo. Il tracciamento apre \
                    il sito ufficiale della rete scelta; \
                    17Track è il piano B universale.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Impostazioni")
            .confirmationDialog(
                "Eliminare tutte le spedizioni?",
                isPresented: $showDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Elimina tutto", role: .destructive) {
                    store.deleteAll()
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ShipmentStore())
}
