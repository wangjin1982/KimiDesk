import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL?

    final class Coordinator {
        var lastLoadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load when the requested URL prop actually changes.
        // (The SPA mutates webView.url via history.replaceState as the user
        // navigates between sessions; that must NOT trigger a reload.)
        guard let url, context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }
}
