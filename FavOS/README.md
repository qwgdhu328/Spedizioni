# FavOS — wrapper Swift della VM Favilla

Package SwiftPM che gira **FavOS** (il sistema operativo con linguaggio
Favilla) dentro un'app iOS/macOS: incapsula la **VM C++** di
`favos_vm.h` (zero dipendenze), riscrive il kernel e le viste in Swift e
mostra il framebuffer **320x240** in SwiftUI.

```
FavOS/
├── Package.swift                  # swift-tools 5.9, macOS 14 / iOS 17
├── Sources/
│   ├── CFavOSVM/                  # target C/C++
│   │   ├── include/favos_host.h   # API C pura (la Swift la importa)
│   │   ├── favos_host.cpp         # ponte: thunk per slot, Val <-> FavVal
│   │   └── favos_vm.h             # la VM Favilla (copia di favos/esp32)
│   └── FavOS/                     # target Swift
│       ├── Kernel.swift           # processi, shell, input, syscalls
│       ├── Viste.swift            # home / shell / nav / tastiera
│       ├── Framebuffer.swift      # 320x240 RGB + font 5x7 + CGImage
│       ├── Firma.swift            # HMAC-SHA256 (.fvbs, formato FVS1)
│       ├── Macchina.swift         # wrapper Swift della VM C++
│       ├── Sessione.swift         # ciclo schedula 50 ms + render
│       ├── Schermo.swift          # vista SwiftUI (touch + tastiera)
│       └── Resources/Apps/*.fvb   # le app di FavOS incluse nel bundle
├── Tests/FavOSTests/              # test: VM, shell, liste, render, firma
└── tests_cpp/                     # test C++ del ponte (g++, locale)
```

## Perche' un ponte C e non C++-interop

La VM espone `Val (*)(int, const Val*)` **senza contesto**: ogni syscall
registrata riceve un thunk dedicato che conosce il proprio slot e quindi
il nome, e chiama la callback Swift coi valori convertiti (`FavVal`).
`favos_host.h` e' puro C, quindi Swift importa il modulo senza interop
C++; la `favos_vm.h` resta nascosta nel target C++.

Modifiche additive a `favos_vm.h` (in sync con `favos/esp32/`):

- `FAV_SYSCALLS_MAX` (default 32 come prima; qui 48: il wrapper ne
  registra 35) — il limite di 32 non bastava per tutti i builtins;
- `lista_n` / `lista_elem` — leggere le liste per passarle agli argomenti
  delle syscalls (`testo_unisci`);
- `nuova_lista` — creare le liste di risposta (`os_tocco`,
  `os_file_lista`, `testo_dividi`), come fa la VM Python.

## Uso

```swift
import FavOS

let sessione = Sessione(kernel: Risorse.kernelDiFabbrica())
// in una View:
FavOSSchermo(sessione: sessione)
```

- **Touch**: tocchi in coordinate FavOS 320x240 (home, shell, nav,
  tastiera a schermo, `os_tocco` per le app).
- **Tastiera hardware**: caratteri, INVIO, CANCELLA, ESC, frecce.
- **Firma**: `Kernel(chiaveFirma:)` verifica i `.fvbs` (HMAC-SHA256);
  senza chiave le app girano comunque in modalita' "non firmato", come
  in Python. Un bytecode manomesso viene **rifiutato**.
- **Rete**: nel wrapper v1 le syscalls web ritornano `negato` senza
  permesso, e con il permesso `rete` restituiscono `WEBERRORE:...`
  (nessuna richiesta di rete nel wrapper).

## Build dell'app iOS (IPA)

La shell dell'app vive in `../FavOSApp/` (`FavOSApp.swift` +
`Info.plist`) ed è collegata a questo package dal target `FavOSApp` di
`../project.yml` (`packages: FavOS: path: FavOS`, iOS 17). La GitHub
Action `favos-build.yml` fa, su macOS:

```sh
xcodegen generate                         # -> CreaSito.xcodeproj
xcodebuild -project CreaSito.xcodeproj -scheme FavOSApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
# Payload/FavOSApp.app -> FavOS-unsigned.ipa (artifact della run)
```

L'IPA è **unsigned**: per installarlo va firmato (AltStore, Sideloadly,
TestFlight o un profilo proprio).

## Test

```sh
cd FavOS
swift test          # test Swift (VM, shell, liste, render, firma)
```

Test C++ del solo ponte (locale, richiede g++):

```sh
g++ -std=c++11 -DFAV_SYSCALLS_MAX=48 -ISources/CFavOSVM/include \
    -o tests_cpp/test_host tests_cpp/test_host.cpp \
    Sources/CFavOSVM/favos_host.cpp
./tests_cpp/test_host Sources/FavOS/Resources/Apps tests_cpp/lista_tocco.fvb
```

## Origine dei file

I sorgenti di FavOS vivono nel repository principale (`favos/`):
`favos_vm.h` e' una copia di `favos/esp32/favos_vm.h`, le app `.fvb`
sono compilate da `favos/apps/*.fav` con `tools/favc.py`.
