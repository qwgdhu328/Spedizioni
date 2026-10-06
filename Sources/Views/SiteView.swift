import SwiftUI

/// Tab **Sito**: alberatura di cartelle e file del sito.
///
/// - naviga nelle cartelle (tocca per entrare),
/// - `+` per creare cartella o file,
/// - tocca un file per aprirlo nell'editor di codice,
/// - swipe per rinominare/eliminare.
///
/// Un solo `.alert` gestito da un enum di stato (più alert
/// sovrapposti sulla stessa vista non sono affidabili).
struct SiteView: View {
    @EnvironmentObject private var store: SiteStore

    private enum PendingAlert: Identifiable {
        case create
        case rename(SiteItem)
        case error(String)

        var id: String {
            switch self {
            case .create: return "create"
            case let .rename(item): return "rename-\(item.path)"
            case .error: return "error"
            }
        }
    }

    @State private var alert: PendingAlert?
    @State private var newName = ""
    @State private var newIsFile = false
    @State private var deleteTarget: SiteItem?

    var body: some View {
        NavigationStack {
            List {
                if !store.currentPath.isEmpty {
                    Button {
                        store.goUp()
                    } label: {
                        Label("Cartella superiore", systemImage: "arrow.uturn.left")
                    }
                }

                if store.items.isEmpty {
                    Text("Cartella vuota: tocca `+` per creare cartelle e file di codice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.items) { item in
                    row(item)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newIsFile = false
                            newName = ""
                            alert = .create
                        } label: {
                            Label("Nuova cartella", systemImage: "folder.badge.plus")
                        }
                        Button {
                            newIsFile = true
                            newName = ""
                            alert = .create
                        } label: {
                            Label("Nuovo file", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Crea cartella o file")
                }
            }
            .sheet(isPresented: Binding(
                get: { store.openFile != nil },
                set: { if !$0 { store.closeFile() } }
            )) {
                EditorView()
                    .environmentObject(store)
            }
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                ),
                presenting: alert
            ) { pending in
                switch pending {
                case .create:
                    TextField(newIsFile ? "pagina.html" : "nome", text: $newName)
                    Button("Crea") { create() }
                    Button("Annulla", role: .cancel) { }
                case let .rename(item):
                    TextField("Nuovo nome", text: $newName)
                    Button("Rinomina") { rename(item) }
                    Button("Annulla", role: .cancel) { }
                case .error:
                    Button("OK", role: .cancel) { }
                }
            } message: { pending in
                switch pending {
                case .error(let msg):
                    Text(msg)
                case .create:
                    Text(newIsFile
                         ? "Estensione inclusa: es. `pagina.html`, `stile.css`."
                         : "Niente barre nel nome.")
                case .rename:
                    Text("Niente barre nel nome.")
                }
            }
            .confirmationDialog(
                "Eliminare \(deleteTarget?.name ?? "")?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) { delete() }
                Button("Annulla", role: .cancel) { }
            } message: {
                Text("L'operazione non è reversibile.")
            }
        }
    }

    private var alertTitle: String {
        guard let current = alert else { return "" }
        switch current {
        case .create: return newIsFile ? "Nuovo file" : "Nuova cartella"
        case .rename: return "Rinomina"
        case .error: return "Errore"
        }
    }

    private var title: String {
        store.currentPath.isEmpty
            ? "Il mio sito"
            : ((store.currentPath as NSString).lastPathComponent)
    }

    private func row(_ item: SiteItem) -> some View {
        Button {
            if item.isDirectory {
                store.open(item.path)
            } else {
                store.openEditor(item.path)
            }
        } label: {
            Label(item.name, systemImage: item.systemImage)
                .foregroundStyle(item.isDirectory ? Color.accentColor : Color.primary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTarget = item
            } label: {
                Label("Elimina", systemImage: "trash")
            }
            Button {
                newName = item.name
                alert = .rename(item)
            } label: {
                Label("Rinomina", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    // MARK: - Azioni

    private func create() {
        do {
            try store.create(name: newName, in: store.currentPath, isFile: newIsFile)
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func rename(_ item: SiteItem) {
        do {
            try store.rename(item.path, to: newName)
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func delete() {
        guard let target = deleteTarget else { return }
        do {
            try store.delete(target.path)
        } catch {
            alert = .error(error.localizedDescription)
        }
    }
}

#Preview {
    SiteView()
        .environmentObject(SiteStore())
}
