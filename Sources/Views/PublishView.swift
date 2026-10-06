import SwiftUI

/// Tab **Pubblica**: crea il deploy su Vercel e mette il sito
/// online con dominio gratis `<nome>.vercel.app`.
///
/// Richiede il token Vercel (Impostazioni). Il deploy invia tutti
/// i file del sito in un colpo solo e attende lo stato `READY`.
struct PublishView: View {
    @EnvironmentObject private var store: SiteStore
    @State private var siteName = "mio-sito"
    @State private var publishing = false
    @State private var resultURL: URL?
    @State private var errorMessage: String?

    private var fileCount: Int { store.collectFiles().count }
    private var previewHost: String {
        "(VercelClient.sanitize(siteName)).vercel.app"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nome-sito", text: $siteName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Online su **\(previewHost)** (dominio gratis)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Nome del sito")
                }

                Section {
                    LabeledContent("File", value: "\(fileCount)")
                    LabeledContent(
                        "Token",
                        value: VercelKeychain.hasToken ? "attivo" : "mancante"
                    )
                    .foregroundStyle(
                        VercelKeychain.hasToken ? .secondary : .red
                    )
                } header: {
                    Text("Prima di pubblicare")
                } footer: {
                    Text("Il token si crea su vercel.com/account/tokens e va inserito in Impostazioni.")
                }

                Section {
                    Button {
                        publish()
                    } label: {
                        if publishing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Pubblicazione in corso…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Pubblica online", systemImage: "icloud.and.arrow.up.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(publishing)
                }

                if let resultURL {
                    Section {
                        Link(destination: resultURL) {
                            Label(resultURL.absoluteString, systemImage: "safari")
                        }
                        ShareLink(item: resultURL) {
                            Label("Condividi il sito", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Sito online 🎉")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } header: {
                        Text("Errore")
                    }
                }
            }
            .navigationTitle("Pubblica")
        }
    }

    // MARK: - Deploy

    @MainActor
    private func publish() {
        guard let token = VercelKeychain.token() else {
            errorMessage = VercelClient.VercelError.noToken.localizedDescription
            return
        }
        let files = store.collectFiles()
        let name = VercelClient.sanitize(siteName)
        publishing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let url = try await VercelClient.deploy(
                    name: name,
                    token: token,
                    files: files
                )
                resultURL = url
            } catch {
                errorMessage = error.localizedDescription
            }
            publishing = false
        }
    }
}

#Preview {
    PublishView()
        .environmentObject(SiteStore())
}
