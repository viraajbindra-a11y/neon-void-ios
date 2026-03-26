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

        // JS bridge for haptics, keepAwake, openExternal
        config.userContentController.add(context.coordinator, name: "neonVoid")

        // Inject safe area CSS vars + app detection
        let safeAreaScript = WKUserScript(
            source: safeAreaJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(safeAreaScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = UIColor.black
        webView.scrollView.backgroundColor = UIColor.black
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        // Load bundled HTML
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebContent") {
            let accessURL = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: accessURL)
        } else if let webContentURL = Bundle.main.url(forResource: "WebContent", withExtension: nil) {
            let indexURL = webContentURL.appendingPathComponent("index.html")
            webView.loadFileURL(indexURL, allowingReadAccessTo: webContentURL)
        } else {
            webView.loadHTMLString("<html><body style='background:#06060c;color:#ff0055;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0'><h1>WebContent not found in bundle</h1></body></html>", baseURL: nil)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
            style.textContent = ':root { --sat: \(Int(safeAreaInsets.top))px; --sar: \(Int(safeAreaInsets.trailing))px; --sab: \(Int(safeAreaInsets.bottom))px; --sal: \(Int(safeAreaInsets.leading))px; } html,body { height:100%!important;overflow:hidden!important;margin:0!important;padding:0!important;background:#000!important; } #main-overlay { height:100%!important; }';
            document.head.appendChild(style);
            // Force ALL elements to use real viewport height
            var realH = window.innerHeight;
            document.documentElement.style.height = realH + 'px';
            document.body.style.height = realH + 'px';
            document.documentElement.style.setProperty('--nvh', realH + 'px');
            window.addEventListener('resize', function() {
                var h = window.innerHeight;
                document.documentElement.style.height = h + 'px';
                document.body.style.height = h + 'px';
                document.documentElement.style.setProperty('--nvh', h + 'px');
            });
            // Also force #main-overlay height after DOM ready
            setTimeout(function() {
                var mo = document.getElementById('main-overlay');
                if (mo) mo.style.height = window.innerHeight + 'px';
            }, 500);
        })();
        """
    }
}

// MARK: - WebViewCoordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "haptic":
            let type = body["type"] as? String ?? "medium"
            switch type {
            case "light":  UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "heavy":  UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            default:       UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .cancel
        }

        if url.isFileURL {
            return .allow
        } else if url.scheme == "https" || url.scheme == "http" {
            if navigationAction.targetFrame?.isMainFrame == true {
                await UIApplication.shared.open(url)
                return .cancel
            } else {
                return .allow
            }
        } else {
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
