import Foundation

/// Client dell'API **ufficiale InPost** (developers.inpost-group.com).
///
/// Flusso:
/// 1. OAuth 2.1 *client credentials*:
///    `POST https://api.inpost-group.com/oauth2/token`
///    (grant_type=client_credentials, scope=`openid api:tracking:read`)
/// 2. Tracking:
///    `GET https://api.inpost-group.com/tracking/v1/parcels?trackingNumbers={n}`
///    con `Authorization: Bearer {token}`.
///
/// La risposta contiene il parcel (`trackingNumber`, `currentCode`,
/// `events[]` con `eventCode`); ogni evento è arricchito con il
/// catalogo ufficiale `InPostEventCatalog` (titolo + descrizione).
enum InPostTrackingClient {

    static let apiBase = "https://api.inpost-group.com"

    // MARK: - Token (cache fino a scadenza)

    private actor TokenCache {
        private var token: String?
        private var expiresAt = Date.distantPast

        func valid() -> String? {
            guard let token, expiresAt > Date().addingTimeInterval(30) else { return nil }
            return token
        }

        func store(_ token: String, expiresIn seconds: Double) {
            self.token = token
            expiresAt = Date().addingTimeInterval(seconds)
        }
    }

    private static let cache = TokenCache()

    private static func accessToken(
        clientID: String,
        clientSecret: String
    ) async throws -> String {
        if let cached = await cache.valid() { return cached }

        guard let url = URL(string: "\(apiBase)/oauth2/token") else {
            throw TrackingError.invalidNumber
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let body = [
            "grant_type": "client_credentials",
            "scope": "openid api:tracking:read",
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        request.httpBody = Data(formEncode(body).utf8)

        let (data, response) = try await data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let apiError = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: Any] }?["error"] as? String
            if apiError == "invalid_client" || http.statusCode == 401 {
                throw TrackingError.config(
                    "Credenziali InPost non valide: controlla Client ID e Secret in Impostazioni."
                )
            }
            throw TrackingError.http(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data)
                .flatMap({ $0 as? [String: Any] }),
              let token = json["access_token"] as? String
        else {
            throw TrackingError.decoding("token OAuth non leggibile")
        }
        let expiresIn = (json["expires_in"] as? Double)
            ?? (json["expires_in"] as? Int).map(Double.init)
            ?? 599
        await cache.store(token, expiresIn: expiresIn)
        return token
    }

    // MARK: - Tracking

    static func track(
        number: String,
        clientID: String,
        clientSecret: String
    ) async throws -> TrackingResult {
        let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrackingError.invalidNumber }

        let token = try await accessToken(
            clientID: clientID,
            clientSecret: clientSecret
        )

        var components = URLComponents(string: "\(apiBase)/tracking/v1/parcels")!
        components.queryItems = [
            URLQueryItem(name: "trackingNumbers", value: clean)
        ]
        guard let url = components.url else { throw TrackingError.invalidNumber }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw TrackingError.http(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw TrackingError.decoding("risposta non JSON")
        }

        let parcels = parcelsArray(from: json)
        guard !parcels.isEmpty else { throw TrackingError.emptyResponse }

        let key = clean.uppercased()
        let parcel = parcels.first {
            (stringValue($0["trackingNumber"]) ?? "").uppercased() == key
        } ?? parcels[0]

        return buildResult(parcel: parcel, requested: clean)
    }

    // MARK: - Parsing difensivo

    private static func parcelsArray(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] { return array }
        if let dict = json as? [String: Any] {
            for key in ["parcels", "data", "items", "results"] {
                if let array = dict[key] as? [[String: Any]] { return array }
            }
            if let single = dict["parcel"] as? [String: Any] { return [single] }
            return [dict]
        }
        return []
    }

    private static func buildResult(
        parcel: [String: Any],
        requested: String
    ) -> TrackingResult {
        let currentCode = stringValue(parcel["currentCode"])
            ?? stringValue(parcel["status"])
            ?? ""

        // Gli eventi arrivano in ordine cronologico (l'ultimo = più
        /// recente): l'invertiamo per la timeline più recente-prima.
        let rawEvents = parcel["events"] as? [[String: Any]] ?? []
        let events: [TrackingEvent] = rawEvents.reversed().enumerated()
            .map { index, event in
                let code = stringValue(event["eventCode"])
                    ?? stringValue(event["code"])
                    ?? ""
                let info = code.isEmpty ? nil : InPostEventCatalog.info(for: code)
                let apiTitle = stringValue(event["title"])
                    ?? stringValue(event["statusDescription"])
                let apiDesc = stringValue(event["description"])
                    ?? stringValue(event["message"])
                var detail = apiDesc ?? info?.description ?? ""
                if let place = locationString(event) {
                    detail = detail.isEmpty ? place : "\(detail) · \(place)"
                }
                let date = dateValue(event)
                return TrackingEvent(
                    id: "\(index)-\(code)",
                    time: date,
                    timeString: stringValue(event["occurredAt"])
                        ?? stringValue(event["eventDate"])
                        ?? stringValue(event["timestamp"])
                        ?? stringValue(event["date"])
                        ?? "",
                    title: apiTitle ?? info?.title
                        ?? (code.isEmpty ? "Movimento" : code),
                    detail: detail,
                    actionCode: code,
                    latitude: doubleValue(event["latitude"]),
                    longitude: doubleValue(event["longitude"])
                )
            }

        let stages = Array(Set(events.compactMap { event -> String? in
            guard !event.actionCode.isEmpty else { return nil }
            return event.actionCode.split(separator: ".").first.map(String.init)
        }))
        let orderedStages = ["CRE", "FUL", "FMD", "HAN", "LMD", "EOL", "RTS"]
            .filter { stages.contains($0) }

        let info = currentCode.isEmpty
            ? nil
            : InPostEventCatalog.info(for: currentCode)

        return TrackingResult(
            number: requested,
            status: currentCode.isEmpty ? "IN_TRANSIT" : currentCode,
            statusDesc: info?.title
                ?? stringValue(parcel["statusDescription"])
                ?? "Stato InPost",
            emptyDescription: "Nessun movimento InPost per questo numero.",
            progressRate: nil,
            progressPoints: orderedStages,
            originCountry: nil,
            destCountry: nil,
            events: events,
            source: "InPost Tracking API (OAuth 2.1, ufficiale)"
        )
    }

    // MARK: - Helper JSON

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func locationString(_ event: [String: Any]) -> String? {
        for key in ["location", "place", "address", "facility"] {
            if let s = stringValue(event[key]) { return s }
        }
        if let dict = event["location"] as? [String: Any],
           let name = stringValue(dict["name"]) ?? stringValue(dict["address"]) {
            return name
        }
        return nil
    }

    private static func dateValue(_ event: [String: Any]) -> Date? {
        for key in ["occurredAt", "eventDate", "timestamp", "date", "createdAt", "eventTime"] {
            if let s = stringValue(event[key]), let date = parseDate(s) {
                return date
            }
            if let epoch = doubleValue(event[key]), epoch > 0 {
                let seconds = epoch > 100_000_000_000 ? epoch / 1000 : epoch
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return plain.date(from: raw)
    }

    // MARK: - Utilità HTTP

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw TrackingError.network(error.localizedDescription)
        }
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params
            .map { key, value in
                let allowed = CharacterSet.urlQueryAllowed
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
