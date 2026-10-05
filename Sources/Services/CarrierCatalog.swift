import Foundation

/// Catalogo completo delle reti di spedizione supportate.
///
/// Ogni rete ha un template `trackURL` con `{NUM}` (numero di
/// tracciamento sostituito in fase di apertura). Dove il pattern
/// diretto non è garantito si usa il tracciatore universale
/// 17Track, che copre centinaia di reti nel mondo.
enum CarrierCatalog {

    /// Tutte le reti, ordinate per paese e nome.
    static let all: [Carrier] = build()

    /// Dizionario id -> carrier per lookup rapidi.
    private static let index: [String: Carrier] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func byId(_ id: String) -> Carrier? {
        index[id]
    }

    /// Ricerca per nome, paese o id.
    static func search(_ query: String) -> [Carrier] {
        let q = query.trimmingCharacters(in: .whitespacesAndLocalizedCaseInsensibles).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q)
                || $0.country.lowercased().contains(q)
                || $0.id.contains(q)
        }
    }

    /// Raggruppamento per paese, in ordine alfabetico,
    /// con l'Italia per prima.
    static func groupedByCountry(_ carriers: [Carrier] = all) -> [(country: String, carriers: [Carrier])] {
        let groups = Dictionary(grouping: carriers, by: \.country)
        return groups
            .map { (country: $0.key, carriers: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.country == "Italia" { return true }
                if rhs.country == "Italia" { return false }
                return lhs.country < rhs.country
            }
    }

    // MARK: - Helper di costruzione

    private static let U = "https://www.17track.net/en?nums={NUM}"

    private static func c(
        _ id: String,
        _ name: String,
        _ flag: String,
        _ country: String,
        _ category: CarrierCategory,
        _ url: String,
        note: String? = nil
    ) -> Carrier {
        Carrier(id: id, name: name, flag: flag, country: country,
                category: category, trackURL: url, note: note)
    }

    // MARK: - Catalogo

    private static func build() -> [Carrier] {
        [
            // ── Italia ──────────────────────────────────────────
            c("poste-italiane", "Poste Italiane", "🇮🇹", "Italia", .postale,
              "https://tracking.poste.it/crz/tracking?crz={NUM}"),
            c("sda", "SDA (Poste Italiane)", "🇮🇹", "Italia", .postale,
              "https://tracking.poste.it/crz/tracking?crz={NUM}"),
            c("brt", "BRT Bartolini", "🇮🇹", "Italia", .corriere,
              "https://www.brt.it/ricerca-numerazione?tipo=1&numero={NUM}"),
            c("gls-italy", "GLS Italy", "🇮🇹", "Italia", .corriere,
              "https://gls-group.eu/IT/it/tracking?match={NUM}"),
            c("dpd-italia", "DPD Italia", "🇮🇹", "Italia", .corriere,
              "https://track.dpd.de/parcelstatus?query={NUM}&locale=it_IT"),
            c("dhl-italia", "DHL Italia", "🇮🇹", "Italia", .corriere,
              "https://www.dhl.com/it-it/home/tracking/tracking-parcel.html?submit=1&ID={NUM}"),
            c("amazon-it", "Amazon Logistics Italia", "🇮🇹", "Italia", .ecommerce,
              "https://www.amazon.it/gp/css/ship-tracking?orderId={NUM}",
              note: "Richiede il numero d'ordine Amazon"),
            c("inpost-it", "InPost Italia", "🇮🇹", "Italia", .corriere, U),
            c("asendia-it", "Asendia Italia", "🇮🇹", "Italia", .logistica, U),

            // ── Europa ──────────────────────────────────────────
            c("dhl-paket", "Deutsche Post / DHL Paket", "🇩🇪", "Germania", .postale,
              "https://www.dhl.de/en/verfolgen?lang=en&idc={NUM}"),
            c("hermes-de", "Hermes Germany", "🇩🇪", "Germania", .corriere, U),
            c("dpd-de", "DPD Germany", "🇩🇪", "Germania", .corriere,
              "https://track.dpd.de/parcelstatus?query={NUM}&locale=de_DE"),
            c("gls-de", "GLS Germany", "🇩🇪", "Germania", .corriere,
              "https://gls-group.eu/DE/de/tracking?match={NUM}"),

            c("royal-mail", "Royal Mail", "🇬🇧", "Regno Unito", .postale,
              "https://www.royalmail.com/track-your-item?trackingNumbers={NUM}"),
            c("evri", "Evri (ex Hermes UK)", "🇬🇧", "Regno Unito", .corriere, U),
            c("yodel", "Yodel", "🇬🇧", "Regno Unito", .corriere, U),
            c("dpd-uk", "DPD UK", "🇬🇧", "Regno Unito", .corriere, U),

            c("colissimo", "Colissimo / La Poste", "🇫🇷", "Francia", .postale,
              "https://www.colissimo.fr/portail-colissimo/suivi-colis.do?referencesDisplay={NUM}"),
            c("mondial-relay", "Mondial Relay", "🇫🇷", "Francia", .corriere, U),
            c("chronopost", "Chronopost", "🇫🇷", "Francia", .espress, U),

            c("postnl", "PostNL", "🇳🇱", "Paesi Bassi", .postale,
              "https://www.postnl.nl/track-and-trace/{NUM}-NL"),
            c("bpost", "bpost", "🇧🇪", "Belgio", .postale, U),

            c("correos", "Correos", "🇪🇸", "Spagna", .postale,
              "https://www.correos.es/es/es/herramientas/localizador?nums={NUM}"),
            c("seur", "SEUR", "🇪🇸", "Spagna", .corriere, U),
            c("mrw", "MRW", "🇪🇸", "Spagna", .corriere, U),
            c("nacex", "Nacex", "🇪🇸", "Spagna", .corriere, U),

            c("ctt", "CTT Portugal", "🇵🇹", "Portogallo", .postale, U),

            c("postnord", "PostNord", "🇸🇪", "Svezia/Danimarca/Norvegia", .postale, U),
            c("bring", "Bring", "🇳🇴", "Norvegia", .postale, U),
            c("posti", "Posti (Finlandia)", "🇫🇮", "Finlandia", .postale, U),
            c("an-post", "An Post", "🇮🇪", "Irlanda", .postale, U),
            c("post-at", "Österreichische Post", "🇦🇹", "Austria", .postale, U),
            c("ceska-posta", "Česká pošta", "🇨🇿", "Cechia", .postale, U),
            c("poczta-polska", "Poczta Polska", "🇵🇱", "Polonia", .postale,
              "https://emonitoring.poczta-polska.pl/?lang=en&numer={NUM}"),
            c("hungarian-post", "Magyar Posta", "🇭🇺", "Ungheria", .postale, U),
            c("swiss-post", "Die Post (Svizzera)", "🇨🇭", "Svizzera", .postale, U),

            // ── Americhe ────────────────────────────────────────
            c("usps", "USPS", "🇺🇸", "Stati Uniti", .postale,
              "https://tools.usps.com/go/TrackConfirmAction?tLabels={NUM}"),
            c("ups", "UPS", "🇺🇸", "Stati Uniti", .espress,
              "https://www.ups.com/track?tracknum={NUM}"),
            c("fedex", "FedEx", "🇺🇸", "Stati Uniti", .espress,
              "https://www.fedex.com/fedextrack/tracking?trknbr={NUM}"),
            c("ontrac", "OnTrac", "🇺🇸", "Stati Uniti", .corriere, U),
            c("lasership", "LaserShip / Veho", "🇺🇸", "Stati Uniti", .corriere, U),
            c("canada-post", "Canada Post", "🇨🇦", "Canada", .postale,
              "https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor={NUM}"),
            c("purolator", "Purolator", "🇨🇦", "Canada", .corriere, U),
            c("correos-mx", "Correos de México", "🇲🇽", "Messico", .postale, U),
            c("correios-br", "Correios", "🇧🇷", "Brasile", .postale, U),

            // ── Asia-Pacifico ───────────────────────────────────
            c("japan-post", "Japan Post", "🇯🇵", "Giappone", .postale, U),
            c("yamato", "Yamato Transport", "🇯🇵", "Giappone", .corriere,
              "https://kuronekoyamato.co.jp/ytc/search/num?taq_no={NUM}"),
            c("sagawa", "Sagawa Express", "🇯🇵", "Giappone", .corriere, U),
            c("china-post", "China Post", "🇨🇳", "Cina", .postale, U),
            c("china-ems", "China EMS", "🇨🇳", "Cina", .espress, U),
            c("sf-express", "SF Express", "🇨🇳", "Cina", .corriere, U),
            c("cainiao", "Cainiao (AliExpress)", "🇨🇳", "Cina", .ecommerce,
              U, note: "Numero di tracciamento AliExpress"),
            c("yunexpress", "YunExpress", "🇨🇳", "Cina", .logistica, U),
            c("4px", "4PX", "🇨🇳", "Cina", .logistica, U),
            c("cj-logistics", "CJ Logistics", "🇰🇷", "Corea del Sud", .corriere, U),
            c("singpost", "SingPost", "🇸🇬", "Singapore", .postale, U),
            c("india-post", "India Post", "🇮🇳", "India", .postale,
              "https://www.indiapost.gov.in/VAS/Pages/TrackConsignment.aspx?Expectedsgcno={NUM}"),
            c("ptt-tr", "PTT Türkiye", "🇹🇷", "Turchia", .postale, U),

            c("auspost", "Australia Post", "🇦🇺", "Australia", .postale,
              "https://auspost.com.au/mypost/track/#/search?item={NUM}"),
            c("nz-post", "NZ Post", "🇳🇿", "Nuova Zelanda", .postale, U),

            // ── Medio Oriente / Africa ──────────────────────────
            c("aramex", "Aramex", "🇦🇪", "Emirati Arabi Uniti", .espress,
              "https://www.aramex.com/us/en/track/shipments?ShipmentNumber={NUM}"),
            c("israel-post", "Israel Post", "🇮🇱", "Israele", .postale, U),
            c("sa-po", "Saudi Post", "🇸🇦", "Arabia Saudita", .postale, U),

            // ── Universale ──────────────────────────────────────
            c("17track", "17Track (universale)", "🌐", "Mondo", .logistica, U,
              note: "Copre 2000+ reti: usalo per qualsiasi corriere non elencato"),
            c("tnt", "TNT", "🌍", "Mondo", .espress, U),
            c("dhl-express", "DHL Express", "🌍", "Mondo", .espress,
              "https://www.dhl.com/it-it/home/tracking/tracking-parcel.html?submit=1&ID={NUM}"),
            c("dhl-ecommerce", "DHL eCommerce", "🌍", "Mondo", .ecommerce, U),
            c("tnt-it", "TNT Italia", "🌍", "Italia", .espress, U)
        ]
    }
}
