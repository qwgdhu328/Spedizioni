import SwiftUI

/// Tab **Impostazioni**: token di accesso Vercel (Access Token),
/// salvato nel Keychain del dispositivo.
struct SettingsView: View {
    @State private var token = ""
    @State private var saved = VercelKeychain.hasToken
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("incolla il token Vercel", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Salva nel Keychain") {
                        VercelKeychain.save(token)
                        let ok = VercelKeychain.hasToken
                        saved = ok
                        token = ""
                        message = ok
                            ? "Token salvato nel Keychain."
                            : "Token vuoto: incollalo prima di salvare."
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

                    if saved {
                        Label("Token configurato ✓", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Rimuovi token", role: .destructive) {
                            VercelKeychain.delete()
                            saved = false
                            message = "Token rimosso."
                        }
                    }
                } header: {
                    Text("Token Vercel")
                } footer: {
                    Text("Crea un Access Token gratuito su vercel.com/account/tokens (piano Hobby gratis, con dominio incluso). Il token resta solo nel Keychain del telefono.")
                }

                Section {
                    Link(destination: URL(string: "https://vercel.com/account/tokens")!) {
                        Label("Apri vercel.com per creare il token", systemImage: "link")
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("""
                    Come funziona:
                    1. crea il token su vercel.com,
                    2. incollalo qui sopra,
                    3. scrivi il tuo sito nel tab Sito,
                    4. pubblica dal tab Pubblica.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Guida rapida")
                }
            }
            .navigationTitle("Impostazioni")
        }
    }
}

#Preview {
    SettingsView()
}
