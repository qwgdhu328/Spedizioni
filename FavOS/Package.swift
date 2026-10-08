// swift-tools-version:5.9
// FavOS — wrapper Swift della VM Favilla C++ (favos_vm.h).
//
// Targets:
//   CFavOSVM  — ponte C/C++ sulla VM (favos_host.h/.cpp + favos_vm.h)
//   FavOS     — kernel, viste, firma, sessione e vista SwiftUI
//   FavOSTests — test (bundle + risorse di test)

import PackageDescription

let package = Package(
    name: "FavOS",
    platforms: [
        // KeyPress/onKeyPress richiedono iOS 17 + macOS 14
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FavOS", targets: ["FavOS"]),
    ],
    targets: [
        .target(
            name: "CFavOSVM",
            publicHeadersPath: "include",
            cxxSettings: [
                // il wrapper registra 35 syscalls: il default 32 della
                // VM (pensata per l'ESP32) non basta
                .define("FAV_SYSCALLS_MAX", to: "48"),
            ]
        ),
        .target(
            name: "FavOS",
            dependencies: ["CFavOSVM"],
            resources: [
                .copy("Resources/Apps"),
            ]
        ),
        .testTarget(
            name: "FavOSTests",
            dependencies: ["FavOS"],
            resources: [
                .copy("Resources/lista_tocco.fvb"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
