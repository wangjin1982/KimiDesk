import SwiftUI
import WebKit

/// Holds a weak reference to the active WKWebView so native UI (toolbar)
/// can evaluate JS in the page (e.g. submit "/yolo" to the live session).
@MainActor
final class WebViewStore {
    static let shared = WebViewStore()
    weak var webView: WKWebView?

    /// Type a slash command into the chat textarea and submit it.
    /// Only attempts when the input is empty (never clobbers a draft).
    /// Returns the JS result string ("sent" / "no-textarea" / "not-empty").
    @discardableResult
    func submitSlashCommand(_ command: String) async -> String {
        guard let webView else { return "no-webview" }
        let js = """
        (function(){
          var ta = document.querySelector('textarea[data-slot="textarea"]') || document.querySelector('textarea');
          if (!ta) return 'no-textarea';
          if (ta.value && ta.value.trim() !== '') return 'not-empty';
          var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
          setter.call(ta, '\(command)');
          ta.dispatchEvent(new Event('input', {bubbles: true}));
          ta.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true}));
          return 'sent';
        })()
        """
        let result = try? await webView.evaluateJavaScript(js)
        return result as? String ?? "error"
    }
}

/// 让网页里的文件选择（📎 附件按钮）弹出系统文件面板。
/// WKWebView 不实现这个代理方法时，<input type="file"> 点了没反应。
final class WebViewUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}

struct WebView: NSViewRepresentable {
    let url: URL?

    @MainActor
    final class Coordinator {
        var lastLoadedURL: URL?
        let uiDelegate = WebViewUIDelegate()
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
        // 隐藏「Open」菜单里本机未安装的编辑器/终端项（官方 SPA 硬编码列表，
        // 菜单是动态渲染的，用 MutationObserver 兜住每次弹出）
        let hideUninstalled = WKUserScript(
            source: """
            (function(){
              var HIDE = ['Cursor', 'Antigravity', 'iTerm'];
              var scheduled = false;
              function hide() {
                scheduled = false;
                var items = document.querySelectorAll('[role="menuitem"]');
                for (var i = 0; i < items.length; i++) {
                  if (HIDE.indexOf(items[i].textContent.trim()) >= 0) {
                    items[i].style.display = 'none';
                  }
                }
              }
              function schedule() {
                if (scheduled) return;
                scheduled = true;
                requestAnimationFrame(hide);
              }
              function start() {
                new MutationObserver(schedule).observe(document.body, {subtree: true, childList: true});
              }
              if (document.body) start();
              else document.addEventListener('DOMContentLoaded', start);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(hideUninstalled)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = context.coordinator.uiDelegate
        Task { @MainActor in WebViewStore.shared.webView = webView }
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
