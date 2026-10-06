import Foundation

/// Client dell'API **REST Vercel** per pubblicare il sito online.
///
/// Flusso:
/// 1. `POST https://api.vercel.com/v13/deployments` con i file in
///    linea (`files: [{file, data, encoding: "base64"}]`),
///    `projectSettings.framework: null` (sito statico, nessun build)
///    e `target: "production"`.
/// 2. Polling `GET /v13/deployments/{id}` finché `readyState`
///    diventa `READY` (o `ERROR`).
///
/// Autenticazione: `Authorization: Bearer <token>` — il token
/// (Access Token) va creato su vercel.com/account/tokens e
/// inserito in Impostazioni (salvato nel Keychain).
///
/// Il sito finisce online su `https://<nome-progetto>.vercel.app`
/// (dominio gratis incluso nel piano Hobby).
enum VercelClient {

    static let apiBase = "https://api.vercel.com"

    // MARK: - Errori

    enum VercelError: LocalizedError {
        case noToken
        case http(Int, String)
        case decoding(String)
        case deployFailed(String)
        case timeout
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Nessun token Vercel: aggiungilo in Impostazioni."
            case let .http(code, msg):
                return "Vercel ha risposto con errore HTTP \(code)\(msg.isEmpty ? "" : ": \(msg)")"
            case let .decoding(msg):
                return "Risposta Vercel non interpretabile: \(msg)"
            case let .deployFailed(msg):
                return "Deploy non riuscito: \(msg)"
            case .timeout:
                return "Il deploy non è terminato entro 90 secondi. Riprova."
            case let .network(msg):
                return "Errore di rete: \(msg)"
            }
        }
    }

    // MARK: - Deploy

    static func deploy(
        name: String,
        token: String,
        files: [(path: String, data: Data)]
    ) async throws -> URL {
        guard !token.isEmpty else { throw VercelError.noToken }
        guard !files.isEmpty else {
            throw VercelError.deployFailed("il sito non contiene file")
        }

        let body: [String: Any] = [
            "name": sanitize(name),
            "target": "production",
            "files": files.map { file in
                [
                    "file": file.path,
                    "data": file.data.base64EncodedString(),
                    "encoding": "base64"
                ]
            },
            "projectSettings": [
                "framework": NSNull(),
                "buildCommand": NSNull(),
                "installCommand": NSNull(),
                "outputDirectory": NSNull(),
                "devCommand": NSNull()
            ]
        ]

        guard JSONSerialization.isValidJSONObject(body),
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { throw VercelError.deployFailed("body non valido") }

        var request = URLRequest(url: URL(string: "\(apiBase)/v13/deployments")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = payload
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw VercelError.http(status, apiMessage(data))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw VercelError.decoding("risposta non JSON") }

        guard let id = json["id"] as? String else {
            throw VercelError.decoding("deployment id assente")
        }

        // Il deployment parte subito: attendi READY con polling breve.
        if let state = json["readyState"] as? String, state == "READY" {
            return finalURL(json: json)
        }
        return try await poll(id: id, token: token)
    }

    // MARK: - Polling stato

    private static func poll(
        id: String,
        token: String
    ) async throws -> URL {
        for _ in 0..<18 {                       // 18 × 5s = 90s max
            try await Task.sleep(nanoseconds: 5_000_000_000)

            var request = URLRequest(
                url: URL(string: "\(apiBase)/v13/deployments/\(id)")!
            )
            request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                throw VercelError.http(status, apiMessage(data))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { throw VercelError.decoding("stato non JSON") }

            switch json["readyState"] as? String {
            case "READY":
                return finalURL(json: json)
            case "ERROR":
                throw VercelError.deployFailed(
                    (json["errorMessage"] as? String) ?? "errore sconosciuto"
                )
            default:
                continue                          // QUEUED / BUILDING…
            }
        }
        throw VercelError.timeout
    }

    /// URL pubblico finale: alias di produzione se presente,
    /// altrimenti l'URL del deployment (`<id>.vercel.app`).
    private static func finalURL(json: [String: Any]) -> URL {
        if let alias = json["alias"] as? [String], let first = alias.first {
            let host = first.hasPrefix("http") ? first : "https://\(first)"
            if let url = URL(string: host) { return url }
        }
        if let urlStr = json["url"] as? String {
            let host = urlStr.hasPrefix("http") ? urlStr : "https://\(urlStr)"
            if let url = URL(string: host) { return url }
        }
        if let name = json["name"] as? String {
            return URL(string: "https://\(name).vercel.app")
                ?? URL(string: "https://vercel.com")!
        }
        return URL(string: "https://vercel.com")!
    }

    // MARK: - Utilità

    /// Nome progetto Vercel: minuscolo, lettere/numeri/trattini.
    static func sanitize(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let mapped = lowered.map { ch -> Character in
            let scalar = String(ch).unicodeScalars.first!
            return allowed.contains(scalar) ? ch : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = String(slug.prefix(60)).trimmingCharacters(
            in: CharacterSet(charactersIn: "-")
        )
        return slug.isEmpty ? "mio-sito" : slug
    }

    /// Estrae un messaggio d'errore leggibile dalla risposta.
    private static func apiMessage(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return "" }
        if let err = json["error"] as? [String: Any] {
            if let msg = err["message"] as? String { return msg }
            if let code = err["code"] as? String { return code }
        }
        if let msg = json["message"] as? String { return msg }
        return ""
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw VercelError.network(error.localizedDescription)
        }
    }
}
