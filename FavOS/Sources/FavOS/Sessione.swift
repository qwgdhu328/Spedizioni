// Sessione.swift — Il driver del wrapper: ogni 50 ms schedula il kernel
// (come il simulatore PC) e ridisegna il framebuffer, pubblicando il
// CGImage pronto da mostrare.

import Foundation
import Combine
import CoreGraphics

public final class Sessione: ObservableObject {
    /// L'ultimo schermo renderizzato (320x240).
    @Published public private(set) var schermo: CGImage?
    public let kernel: Kernel

    private var timer: Timer?
    private let intervallo: TimeInterval

    public init(kernel: Kernel, intervallo: TimeInterval = 0.05) {
        self.kernel = kernel
        self.intervallo = intervallo
        ridisegna()
    }

    /// Avvia il ciclo schedula + render (idempotente).
    public func avvia() {
        guard timer == nil else { return }
        ridisegna()
        timer = Timer.scheduledTimer(withTimeInterval: intervallo,
                                     repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.kernel.schedula()
            self.ridisegna()
        }
    }

    public func ferma() {
        timer?.invalidate()
        timer = nil
    }

    // -----------------------------------------------------------
    // INPUT
    // -----------------------------------------------------------
    public func premiTasto(_ testo: String) {
        kernel.premiTasto(testo)
        ridisegna()
    }

    /// Tocco in coordinate schermo FavOS (320x240).
    public func tocco(x: Int, y: Int) {
        kernel.tocco(x: x, y: y)
        ridisegna()
    }

    // -----------------------------------------------------------
    // RENDER
    // -----------------------------------------------------------
    public func ridisegna() {
        schermo = Viste.renderSchermo(kernel).cgImage()
    }
}
