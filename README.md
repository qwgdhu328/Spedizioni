# CreaSito 🌐

App iOS nativa (SwiftUI, **Liquid Glass** iOS 26) per **creare un sito
con cartelle e codice** e **pubblicarlo online gratis** con dominio
incluso: l'app costruisce il sito da sola e lo mette online su
`https://<nome>.vercel.app`.

## Come funziona

1. **Tab Sito** — alberatura di cartelle e file del sito:
   crea cartelle e file HTML/CSS/JS con `+`, tocca un file per
   aprirlo nell'**editor di codice** (monospazio, salvataggio
   automatico), swipe per rinominare o eliminare.
   Alla prima avvio l'app **crea in automatico** un sito completo
   (`index.html`, `css/stile.css`, `js/script.js`) già pubblicabile.
2. **Tab Impostazioni** — incolla il tuo **Access Token Vercel**
   (creato gratis su [vercel.com/account/tokens](https://vercel.com/account/tokens));
   viene salvato solo nel **Keychain** del dispositivo.
3. **Tab Pubblica** — scegli il nome del sito e tocca
   **Pubblica online**: l'app invia tutti i file all'API Vercel
   (`POST /v13/deployments`, file in linea base64, static site con
   nessun build), attende lo stato `READY` e ti dà il link
   `https://<nome>.vercel.app` (**dominio gratis**, piano Hobby)
   condivisibile con `ShareLink`.

## Stack

- **SwiftUI / iOS 26** con `Tab` Liquid Glass, `buttonStyle(.glass)` e
  `GlassEffectContainer`.
- **XcodeGen** (`project.yml`), build CI su **GitHub Actions**
  (macOS + Xcode 26, IPA unsigned come artifact).
- **Vercel REST API v13** per il deploy; nessun server proprio:
  il sito vive su Vercel, i file restano sul dispositivo finché
  non pubblichi.

## Struttura

```
Spedizioni/
├── project.yml                     # XcodeGen → CreaSito, iOS 26.0
├── Resources/Info.plist
├── .github/workflows/ios-build.yml # build + IPA unsigned
├── .github/workflows/favos-build.yml # build + IPA unsigned di FavOS
├── FavOS/                          # wrapper Swift di FavOS (Swift Package)
├── FavOSApp/                       # shell iOS che mostra FavOSSchermo
└── Sources/
    ├── App/CreaSitoApp.swift       # entry point
    ├── Services/
    │   ├── SiteStore.swift         # alberatura file + template iniziale
    │   ├── VercelClient.swift      # deploy API + polling READY
    │   └── VercelKeychain.swift    # token nel Keychain
    └── Views/
        ├── ContentView.swift       # tab bar Liquid Glass
        ├── SiteView.swift          # cartelle e file del sito
        ├── EditorView.swift        # editor di codice
        ├── PublishView.swift       # pubblica online (deploy)
        └── SettingsView.swift      # token Vercel
```

## Build (macOS con Xcode 26+)

```sh
brew install xcodegen
cd Spedizioni
xcodegen generate
xcodebuild -project CreaSito.xcodeproj -scheme CreaSito \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Requisiti: **iOS 26.0+** (API Liquid Glass), Xcode 26+.

## FavOS (Swift Package)

`FavOS/` contiene il **wrapper Swift di FavOS**: una Swift Package che
incapsula la VM Favilla C++ (`favos_vm.h`), riscrive kernel e viste in
Swift e mostra il framebuffer 320x240 in SwiftUI. `FavOSApp/` è la
shell iOS (`@main`) che monta `FavOSSchermo` a schermo intero, collegata
come package locale dal target `FavOSApp` di `project.yml`.

La GitHub Action `favos-build.yml` (macOS + Xcode) genera il progetto
con XcodeGen, compila l'app e **pubblica l'IPA unsigned come artifact**
(`FavOS-unsigned-ipa`); i test restano locali con `swift test`. Vedi
`FavOS/README.md` per i dettagli.

## Note

- I dati (file del sito) restano sul dispositivo in `Documents/Sito`.
- Il token Vercel non lascia mai il Keychain.
- Nessuna affiliazione con Vercel; il piano Hobby è gratuito.
