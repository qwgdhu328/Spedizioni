import SwiftUI
import SafariServices

/// SFSafariViewController nativo per aprire le pagine di
/// tracciamento delle reti dentro l'app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
