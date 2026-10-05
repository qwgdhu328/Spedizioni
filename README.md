# Spedizioni 📦

App iOS nativa (SwiftUI) per **controllare le spedizioni**, con
**tutte le reti di spedizione** incluse e design **Liquid Glass**
nativo di iOS 26.

## Funzioni

- **Tab Spedizioni**: riepilogo su vetro (totali / in transito /
  consegati), lista con ricerca, tocca per aprire il dettaglio,
  `+` glass per aggiungerne una nuova.
- **Tab Reti**: catalogo completo (**60+ reti**: Poste Italiane,
  BRT, GLS, DPD, DHL, UPS, FedEx, USPS, Royal Mail, Colissimo,
  China Post, Yamato, Aramex, Australia Post, 17Track…) con
  ricerca per nome/paese e **tracciamento rapido** campo numero +
  lente per rete.
- **Tab Impostazioni**: conteggi, cancellazione dati, info.
- **Dettaglio**: stato segmentato (in attesa / in transito /
  consegnato / problema), etichetta, note e **tracciamento
  in-app**: la vista Tracciamento interroga l'**API pubblica
  Cainiao (keyless, `global.cainiao.com`, risposte in
  italiano)**, mostra **ogni movimento in dettaglio** (timeline
  completa con data, titolo, descrizione e codice),
  avanzamento con tappe e **auto-refresh ogni 60 secondi**.
- **GPS veicolo**: mappa live del corriere aperta **dentro
  l'app** (WKWebView): quando il corriere espone la posizione
  GPS del veicolo, la mappa appare senza uscire dall'app; se
  l'API fornisce coordinate degli eventi, vengono mostrate con
  marker su mappa nativa (MapKit).

## Liquid Glass (iOS 26)

- `TabView` con `Tab` (stile vetro automatico) e
  `tabBarMinimizeBehavior`
- `buttonStyle(.glass)` / `.glassProminent` su tutte le azioni
- `GlassEffectContainer` + `glassEffect(_:in:)` per il riepilogo
  e le azioni del dettaglio
- `.searchable` nativo nelle barre vetro delle toolbar

## Struttura

```
Spedizioni/
├── project.yml                    # XcodeGen, iOS 26.0
├── Resources/Info.plist
└── Sources/
    ├── App/SpedizioniApp.swift    # entry point
    ├── Models/
    │   ├── Carrier.swift          # rete + categoria (icona/colore)
    │   └── Shipment.swift         # spedizione + stato
    ├── Services/
    │   ├── CarrierCatalog.swift   # catalogo completo reti
    │   └── ShipmentStore.swift    # CRUD + persistenza JSON locale
    └── Views/
        ├── ContentView.swift      # tab bar Liquid Glass
        ├── ShipmentListView.swift # lista + riepilogo vetro
        ├── AddShipmentView.swift  # nuovo pacco (picker rete)
        ├── CarrierPickerView.swift# tutte le reti, cercabili
        ├── CarriersView.swift     # tab Reti con tracciamento rapido
        ├── ShipmentDetailView.swift # stato + tracciamento in-app
        ├── TrackingView.swift      # timeline movimenti + GPS/API
        ├── WebView.swift           # WKWebView (mappa live corriere)
        ├── SettingsView.swift     # impostazioni
        └── SafariView.swift       # SFSafariViewController
```

## Build (macOS con Xcode 26+)

```sh
brew install xcodegen
cd Spedizioni
xcodegen generate
xcodebuild -project Spedizioni.xcodeproj -scheme Spedizioni \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Requisiti: **iOS 26.0+** (API Liquid Glass), Xcode 26+.

## Note

- I dati restano sul dispositivo (JSON in Application Support).
- Il tracciamento apre il sito della rete scelta; per reti senza
  URL diretto si usa 17Track (2000+ reti supportate).
- Nessuna affiliazione con le aziende di trasporto citate.
