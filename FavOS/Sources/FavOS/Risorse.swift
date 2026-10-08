// Risorse.swift — Le app firmate di FavOS vivono nei resources del
// package (Sources/FavOS/Resources/Apps/*.fvb): questo le carica in
// un dict compatibile col kernel.

import Foundation

public enum Risorse {
    /// Carica tutte le app .fvb incluse nel bundle ("Apps/<nome>.fvb").
    public static func appsBundle() -> [String: (Data, String)] {
        var out: [String: (Data, String)] = [:]
        guard let dir = (Bundle.module.url(forResource: "Apps",
                                            withExtension: nil)
            ?? Bundle.module.resourceURL?.appendingPathComponent("Apps"))
            else { return out }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path,
                                             isDirectory: &isDir),
              isDir.boolValue else { return out }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "fvb" {
            if let dati = try? Data(contentsOf: url) {
                let nome = url.deletingPathExtension().lastPathComponent
                out[nome] = (dati, "console")
            }
        }
        return out
    }

    /// Un kernel pronto con le app del bundle e il firmware completo.
    public static func kernelDiFabbrica(chiaveFirma: Data? = nil) -> Kernel {
        Kernel(apps: appsBundle(), chiaveFirma: chiaveFirma)
    }
}
