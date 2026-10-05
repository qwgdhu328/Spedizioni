import SwiftUI
import WebKit

/// WKWebView nativa: apre le pagine ufficiali dei corrieri
/// (mappa live del veicolo quando disponibile) DENTRO l'app.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
