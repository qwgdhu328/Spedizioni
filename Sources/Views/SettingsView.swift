import SwiftUI

/// Tab "Impostazioni": informazioni, azioni su dati e stato del
/// design Liquid Glass.
struct SettingsView: View {
    @EnvironmentObject private var store: ShipmentStore
    @State private var showDeleteAll = false
    @State private var inpostClientID = ""
    @State private var inpostClientSecret = ""
    @State private var inpostSaved = false

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

                Section("API InPost (ufficiale)") {
                    LabeledContent(
                        "Credenziali OAuth",
                        value: inpostSaved ? "Salvate nel Keychain ✓" : "Non configurate"
                    )
                    TextField("Client ID", text: $inpostClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Client Secret", text: $inpostClientSecret)
                    HStack {
                        Button("Salva credenziali") {
                            KeychainStore.save(
                                clientID: inpostClientID.trimmingCharacters(in: .whitespaces),
                                clientSecret: inpostClientSecret.trimmingCharacters(in: .whitespaces)
                            )
                            inpostClientSecret = ""
                            inpostSaved = KeychainStore.hasCredentials
                        }
                        .disabled(
                            inpostClientID.trimmingCharacters(in: .whitespaces).isEmpty
                                || inpostClientSecret.isEmpty
                        )
                        .buttonStyle(.glassProminent)

                        if inpostSaved {
                            Button("Rimuovi", role: .destructive) {
                                KeychainStore.delete()
                                inpostClientID = ""
                                inpostClientSecret = ""
                                inpostSaved = false
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    Text("""
                    Client OAuth 2.1 con scope api:tracking:read \
                    (developers.inpost-group.com: team InPost o \
                    merchant.inpost-group.com). Con esse le spedizioni \
                    InPost usano l'API ufficiale con tutti i 114 \
                    eventi catalogati; senza, si usa il provider generico.
                    """)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            .task {
                if let creds = KeychainStore.credentials() {
                    inpostClientID = creds.clientID
                    inpostSaved = true
                }
            }
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
