// Framebuffer.swift — Il framebuffer di FavOS: griglia di pixel RGB
// (0xRRGGBB) con le stesse primitive di kernel/viste (_rett, _testo_fb)
// piu' la conversione a CGImage per mostrarlo in SwiftUI.

import Foundation
import CoreGraphics

public final class Framebuffer {
    public let larghezza: Int
    public let altezza: Int
    public var pixel: [UInt32]

    public init(larghezza: Int, altezza: Int) {
        self.larghezza = larghezza
        self.altezza = altezza
        self.pixel = [UInt32](repeating: 0, count: larghezza * altezza)
    }

    /// Rettangolo pieno, con i bordi tagliati ai bordi del buffer
    /// (come _rett di kernel.py/viste.py).
    public func rett(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ colore: Colore) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(larghezza, x + w), y1 = min(altezza, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            let base = yy * larghezza
            for xx in x0..<x1 { pixel[base + xx] = colore }
        }
    }

    /// Riempi tutto il framebuffer.
    public func riempi(_ colore: Colore) {
        for i in 0..<pixel.count { pixel[i] = colore }
    }

    /// Testo col font 5x7 (_testo_fb): '\\n' va a capo, i glifi mancanti
    /// sono ignorati ma avanzano di 6 px, le maiuscole fallback minuscole.
    public func testo(_ x: Int, _ y: Int, _ s: String, _ colore: Colore,
                      scala: Int = 1) {
        let scala = max(1, scala)
        var px = x
        var y = y
        for car in s {
            if car == "\n" {
                y += 8 * scala
                px = x
                continue
            }
            guard let glifo = Font5X7.glifi[car]
                    ?? Font5X7.glifi[car.lowercased().first ?? car] else {
                px += 6 * scala
                continue
            }
            for (j, bits) in glifo.enumerated() {
                for i in 0..<5 {
                    if bits & (1 << (4 - i)) != 0 {
                        rett(px + i, y + j * scala, scala, scala, colore)
                    }
                }
            }
            px += 6 * scala
        }
    }

    /// Copia le righe di un'altra framebuffer (tanto quante ne ha).
    public func copiaRighe(da altra: Framebuffer) {
        let righe = min(altra.altezza, altezza)
        for y in 0..<righe {
            let src = y * altra.larghezza
            let dst = y * larghezza
            let n = min(altra.larghezza, larghezza)
            pixel.replaceSubrange(dst..<(dst + n),
                                  with: altra.pixel[src..<(src + n)])
        }
    }

    /// CGImage RGBA8888 da mostrare in SwiftUI.
    public func cgImage() -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: larghezza * altezza * 4)
        for (i, p) in pixel.enumerated() {
            let o = i * 4
            rgba[o]     = UInt8((p >> 16) & 0xFF)
            rgba[o + 1] = UInt8((p >> 8) & 0xFF)
            rgba[o + 2] = UInt8(p & 0xFF)
            rgba[o + 3] = 255
        }
        let dati = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: dati as CFData) else {
            return nil
        }
        return CGImage(width: larghezza, height: altezza,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: larghezza * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(
                           rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
