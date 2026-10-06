import Foundation

/// Un elemento dell'albero del sito: cartella o file.
struct SiteItem: Identifiable, Hashable {
    /// Percorso relativo dalla radice (es. `css/stile.css`).
    let path: String
    let name: String
    let isDirectory: Bool
    var id: String { path }

    /// Icona SF Symbol per la lista.
    var systemImage: String {
        isDirectory ? "folder.fill" : "doc.text.fill"
    }
}

/// Errori dello store, con messaggi in italiano.
enum SiteError: LocalizedError {
    case invalidName
    case duplicate
    case notFound
    case io(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Nome non valido: niente barre, punti finali o caratteri speciali."
        case .duplicate:
            return "Esiste già un elemento con questo nome."
        case .notFound:
            return "Elemento non trovato."
        case let .io(msg):
            return "Errore sui file: \(msg)"
        }
    }
}

/// Archiviazione del sito **sul disco dell'app**:
/// una vera alberatura di cartelle e file (HTML/CSS/JS…)
/// dentro `Documents/Sito`, con template iniziale automatico.
/// Tutte le mutazioni partono dall'UI (thread principale).
final class SiteStore: ObservableObject {

    /// Radice del sito (`Documents/Sito`).
    let root: URL

    /// Percorso corrente (relativo, `""` = radice).
    @Published private(set) var currentPath: String = ""

    /// Elementi della cartella corrente.
    @Published private(set) var items: [SiteItem] = []

    /// Contenuto del file aperto nell'editor (`nil` = nessuno).
    @Published private(set) var openFile: OpenFile?

    struct OpenFile: Identifiable, Hashable {
        var path: String
        var text: String
        var id: String { path }
    }

    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Sito", isDirectory: true)
        bootstrap()
    }

    // MARK: - Bootstrap (crea il sito in automatico)

    /// Crea la struttura iniziale alla prima avvio:
    /// `index.html`, `css/stile.css`, `js/script.js`.
    private func bootstrap() {
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            guard !fm.contentsOfDirectory(atPath: root.path).isEmpty else {
                try createInitialTemplate()
            }
        } catch {
            // se non crea niente, l'utente può ancora creare file a mano
        }
        reload()
    }

    private func createInitialTemplate() throws {
        let css = root.appendingPathComponent("css")
        let js = root.appendingPathComponent("js")
        try fm.createDirectory(at: css, withIntermediateDirectories: true)
        try fm.createDirectory(at: js, withIntermediateDirectories: true)

        try Self.initialHTML.write(to: root.appendingPathComponent("index.html"),
                                   atomically: true, encoding: .utf8)
        try Self.initialCSS.write(to: css.appendingPathComponent("stile.css"),
                                  atomically: true, encoding: .utf8)
        try Self.initialJS.write(to: js.appendingPathComponent("script.js"),
                                 atomically: true, encoding: .utf8)
    }

    // MARK: - Navigazione

    /// Torna alla radice.
    func goHome() {
        currentPath = ""
        reload()
    }

    /// Entra in una cartella.
    func open(_ path: String) {
        currentPath = path
        reload()
    }

    /// Cartella superiore.
    func goUp() {
        guard !currentPath.isEmpty else { return }
        currentPath = (currentPath as NSString).deletingLastPathComponent
        reload()
    }

    /// Elementi di una cartella (anche non corrente).
    func listing(_ path: String) -> [SiteItem] {
        let url = absolute(path)
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        var result: [SiteItem] = []
        for name in names where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.appendingPathComponent(name).path,
                                isDirectory: &isDir) else { continue }
            let child = path.isEmpty ? name : "\(path)/\(name)"
            result.append(SiteItem(path: child, name: name, isDirectory: isDir.boolValue))
        }
        return result.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func reload() { items = listing(currentPath) }

    // MARK: - Creazione

    /// Crea una cartella (o un file, se `isFile`) nella cartella data.
    func create(name: String, in parent: String, isFile: Bool) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.hasPrefix(".") else {
            throw SiteError.invalidName
        }
        let target = absolute(parent).appendingPathComponent(clean)
        guard !fm.fileExists(atPath: target.path) else { throw SiteError.duplicate }
        do {
            if isFile {
                try "".write(to: target, atomically: true, encoding: .utf8)
            } else {
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
            }
        } catch {
            throw SiteError.io(error.localizedDescription)
        }
        reload()
    }

    /// Rinomina un elemento.
    func rename(_ path: String, to newName: String) throws {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.hasPrefix(".") else {
            throw SiteError.invalidName
        }
        let old = absolute(path)
        guard fm.fileExists(atPath: old.path) else { throw SiteError.notFound }
        let dest = old.deletingLastPathComponent().appendingPathComponent(clean)
        guard !fm.fileExists(atPath: dest.path) else { throw SiteError.duplicate }
        do {
            try fm.moveItem(at: old, to: dest)
        } catch {
            throw SiteError.io(error.localizedDescription)
        }
        if openFile?.path == path {
            let parent = (path as NSString).deletingLastPathComponent
            openFile?.path = parent.isEmpty ? clean : "\(parent)/\(clean)"
        }
        reload()
    }

    /// Elimina un elemento (file o cartella con contenuto).
    func delete(_ path: String) throws {
        let url = absolute(path)
        guard fm.fileExists(atPath: url.path) else { throw SiteError.notFound }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw SiteError.io(error.localizedDescription)
        }
        if let open = openFile, open.path == path || open.path.hasPrefix(path + "/") {
            openFile = nil
        }
        reload()
    }

    // MARK: - Editor

    /// Apre un file nell'editor.
    func openEditor(_ path: String) {
        guard let text = String(contentsOf: absolute(path), encoding: .utf8) else { return }
        openFile = OpenFile(path: path, text: text)
    }

    /// Salva il contenuto dell'editor sul disco.
    func save(_ text: String) {
        guard let open = openFile else { return }
        try? text.write(to: absolute(open.path), atomically: true, encoding: .utf8)
        openFile?.text = text
    }

    func closeFile() { openFile = nil }

    // MARK: - Raccolta per il deploy

    /// Tutti i file del sito come `(percorso relativo, contenuto)`.
    func collectFiles() -> [(path: String, data: Data)] {
        var out: [(String, Data)] = []
        collect(root, prefix: "", into: &out)
        return out
    }

    private func collect(_ dir: URL, prefix: String, into out: inout [(String, Data)]) {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if isDir.boolValue {
                collect(url, prefix: rel, into: &out)
            } else if let data = try? Data(contentsOf: url) {
                out.append((rel, data))
            }
        }
    }

    // MARK: - Utilità

    private func absolute(_ relative: String) -> URL {
        relative.isEmpty ? root : root.appendingPathComponent(relative)
    }

    // MARK: - Template iniziale

    static let initialHTML = """
    <!DOCTYPE html>
    <html lang="it">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Il mio sito</title>
      <link rel="stylesheet" href="css/stile.css">
    </head>
    <body>
      <main>
        <h1>Ciao dal mio sito! 🚀</h1>
        <p>Modifica questo file nell'app e pubblica: il sito sarà online gratis.</p>
        <button onclick="saluta()">Premimi</button>
        <p id="out"></p>
      </main>
      <script src="js/script.js"></script>
    </body>
    </html>
    """

    static let initialCSS = """
    body {
      font-family: -apple-system, sans-serif;
      margin: 0;
      background: linear-gradient(160deg, #6a5cff, #23c4ff);
      color: #fff;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    main { text-align: center; padding: 2rem; }
    button {
      font-size: 1.1rem;
      padding: .7rem 1.4rem;
      border: 0;
      border-radius: 999px;
      background: #fff;
      color: #4b3fff;
      font-weight: 600;
    }
    """

    static let initialJS = """
    function saluta() {
      document.getElementById('out').textContent =
        'Ciao! Sono online con dominio gratis. 🎉';
    }
    """
}
