import SwiftUI
import WebKit

struct GameWebView: UIViewRepresentable {
    let safeAreaInsets: EdgeInsets

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // JS bridge
        config.userContentController.add(context.coordinator, name: "neonVoid")

        // Inject safe area CSS vars + app detection at document start
        let safeAreaScript = WKUserScript(
            source: safeAreaJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(safeAreaScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        // Load bundled HTML
        if let webContentURL = Bundle.main.url(forResource: "WebContent", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebContent") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webContentURL)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update safe area if device rotates
        let js = """
        (function() {
            var r = document.documentElement.style;
            r.setProperty('--sat', '\(Int(safeAreaInsets.top))px');
            r.setProperty('--sar', '\(Int(safeAreaInsets.trailing))px');
            r.setProperty('--sab', '\(Int(safeAreaInsets.bottom))px');
            r.setProperty('--sal', '\(Int(safeAreaInsets.leading))px');
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func safeAreaJS() -> String {
        return """
        (function() {
            window.isNeonVoidApp = true;
            window.neonVoidSafeArea = {
                top: \(Int(safeAreaInsets.top)),
                right: \(Int(safeAreaInsets.trailing)),
                bottom: \(Int(safeAreaInsets.bottom)),
                left: \(Int(safeAreaInsets.leading))
            };
            var style = document.createElement('style');
            style.textContent = ':root { --sat: \(Int(safeAreaInsets.top))px; --sar: \(Int(safeAreaInsets.trailing))px; --sab: \(Int(safeAreaInsets.bottom))px; --sal: \(Int(safeAreaInsets.leading))px; }';
            document.head.appendChild(style);
        })();
        """
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?

    // Handle JS bridge messages
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "haptic":
            let type = body["type"] as? String ?? "medium"
            switch type {
            case "light":
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            default:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        case "keepAwake":
            let value = body["value"] as? Bool ?? false
            UIApplication.shared.isIdleTimerDisabled = value
        case "openExternal":
            if let urlString = body["url"] as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    // Navigation policy: local files allowed, external URLs open in Safari
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.isFileURL {
            decisionHandler(.allow)
            // Toggle scroll based on page type
            let path = url.lastPathComponent
            let isScrollablePage = path.contains("arcade") || path == "index.html" && url.pathComponents.contains("games")
            webView.scrollView.isScrollEnabled = isScrollablePage
        } else if url.scheme == "https" || url.scheme == "http" {
            // External navigation → open in Safari
            if navigationAction.targetFrame?.isMainFrame == true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                // Allow subframe loads (APIs, etc.)
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Keep screen awake during gameplay
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
