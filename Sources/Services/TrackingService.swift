import Foundation

/// Servizio di tracciamento IN-APP.
///
/// Provider primario: **Cainiao Global API** — endpoint pubblico,
/// keyless e gratuito (`global.cainiao.com/global/detail.json`),
/// verificato live con risposte in italiano (`lang=it-IT`).
/// Restituisce stato, avanzamento e l'elenco completo dei
/// movimenti (checkpoint) della spedizione.
enum TrackingService {

    // MARK: - API pubblica Cainiao (keyless)

    private struct CainiaoResponse: Decodable {
        let success: Bool?
        let module: [Module]?

        struct Module: Decodable {
            let mailNo: String?
            let status: String?
            let statusDesc: String?
            let noTrackingDataDesc: String?
            let originCountry: String?
            let destCountry: String?
            let detailList: [Detail]?
            let processInfo: ProcessInfo?
        }

        struct Detail: Decodable {
            let actionCode: String?
            let desc: String?
            let descTitle: String?
            let standerdDesc: String?
            let time: Double?
            let timeStr: String?
            let timeZone: String?
            let latitude: Double?
            let longitude: Double?
        }

        struct ProcessInfo: Decodable {
            let progressRate: Double?
            let progressPointList: [Point]?
        }

        struct Point: Decodable {
            let pointName: String?
        }
    }

    /// Traccia un numero e restituisce tutti i movimenti.
    ///
    /// Se la rete è **InPost** e le credenziali OAuth sono
    /// configurate (Impostazioni), usa l'**API ufficiale InPost**;
    /// in ogni altro caso (o in caso di errore) usa Cainiao.
    /// - Parameters:
    ///   - number: numero di tracciamento.
    ///   - source: nome del corriere (solo per etichette UI).
    ///   - carrier: rete selezionata (guida il routing InPost).
    static func track(
        number: String,
        source: String? = nil,
        carrier: Carrier? = nil
    ) async throws -> TrackingResult {
        if let carrier, carrier.id.hasPrefix("inpost") {
            if let creds = KeychainStore.credentials() {
                do {
                    return try await InPostTrackingClient.track(
                        number: number,
                        clientID: creds.clientID,
                        clientSecret: creds.clientSecret
                    )
                } catch {
                    var fallback = try await trackCainiao(
                        number: number,
                        source: source
                    )
                    fallback.source +=
                        " · InPost API non riuscita (\(error.localizedDescription))"
                    return fallback
                }
            }
            var fallback = try await trackCainiao(number: number, source: source)
            fallback.source +=
                " · configura l'API InPost in Impostazioni per il dettaglio ufficiale"
            return fallback
        }
        return try await trackCainiao(number: number, source: source)
    }

    private static func trackCainiao(
        number: String,
        source: String? = nil
    ) async throws -> TrackingResult {
        let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              var components = URLComponents(string: "https://global.cainiao.com/global/detail.json")
        else { throw TrackingError.invalidNumber }

        components.queryItems = [
            URLQueryItem(name: "mailNos", value: clean),
            URLQueryItem(name: "lang", value: "it-IT"),
            URLQueryItem(name: "language", value: "it-IT")
        ]
        guard let url = components.url else { throw TrackingError.invalidNumber }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TrackingError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TrackingError.http(http.statusCode)
        }

        let decoded: CainiaoResponse
        do {
            decoded = try JSONDecoder().decode(CainiaoResponse.self, from: data)
        } catch {
            throw TrackingError.decoding(String(describing: error))
        }

        let modules = decoded.module ?? []
        guard !modules.isEmpty else { throw TrackingError.emptyResponse }

        let key = clean.uppercased()
        let module = modules.first { ($0.mailNo ?? "").uppercased() == key } ?? modules[0]

        // ── Movimenti: ogni checkpoint, ordinato dal più recente ──
        let details = module.detailList ?? []
        let events: [TrackingEvent] = details.enumerated().compactMap { index, d in
            let epoch = d.time.flatMap(Self.date(fromEpoch:))
            return TrackingEvent(
                id: "\(index)-\(d.time ?? 0)-\(d.actionCode ?? "")",
                time: epoch,
                timeString: d.timeStr ?? "",
                title: d.descTitle ?? d.standerdDesc ?? d.desc ?? "Movimento",
                detail: d.desc ?? d.standerdDesc ?? "",
                actionCode: d.actionCode ?? "",
                latitude: d.latitude,
                longitude: d.longitude
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.time, rhs.time) {
            case let (l?, r?) where l != r: return l > r
            default: return false
            }
        }

        let rate = module.processInfo?.progressRate
        let points = (module.processInfo?.progressPointList ?? [])
            .compactMap(\.pointName)

        return TrackingResult(
            number: clean,
            status: module.status ?? (events.isEmpty ? "PENDING" : "IN_TRANSIT"),
            statusDesc: module.statusDesc
                ?? (events.isEmpty ? "In attesa di movimenti" : "Movimenti trovati"),
            emptyDescription: module.noTrackingDataDesc
                ?? "Nessun movimento registrato per ora: riprova più tardi.",
            progressRate: rate,
            progressPoints: points,
            originCountry: module.originCountry,
            destCountry: module.destCountry,
            events: events,
            source: source ?? "Cainiao Global API (keyless)"
        )
    }

    /// Converte epoch in Date, tollerante secondi o millisecondi.
    private static func date(fromEpoch value: Double) -> Date? {
        guard value > 0 else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
