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
        // 输入法保护：组词/候选状态下的回车是「确认字母」，不能传给页面当「发送」。
        // 在 window 捕获阶段拦截：SPA 的处理器收不到，但输入法的默认提交不受影响。
        let imeGuard = WKUserScript(
            source: """
            window.addEventListener('keydown', function(e) {
              if ((e.key === 'Enter' || e.keyCode === 13) && (e.isComposing || e.keyCode === 229)) {
                e.stopImmediatePropagation();
              }
            }, true);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(imeGuard)
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
