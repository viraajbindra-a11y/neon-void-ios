import SwiftUI
import WebKit

struct GameWindowView: View {
    @State private var showImmersive = false
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VisionGameWebView()
                .ignoresSafeArea()

            // Floating controls ornament
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button(action: {
                        Task {
                            if showImmersive {
                                await dismissImmersiveSpace()
                            } else {
                                await openImmersiveSpace(id: "shipOrnament")
                            }
                            showImmersive.toggle()
                        }
                    }) {
                        Label(showImmersive ? "Hide Ship" : "Show 3D Ship",
                              systemImage: showImmersive ? "cube.transparent" : "cube.fill")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                }
                .padding()
                .glassBackgroundEffect()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// WKWebView wrapper for visionOS
struct VisionGameWebView: UIViewRepresentable {
    func makeCoordinator() -> VisionWebCoordinator {
        VisionWebCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator

        // Inject visionOS detection
        let script = WKUserScript(
            source: "window.isNeonVoidApp = true; window.isVisionPro = true;",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        // Load bundled game
        if let webContentURL = Bundle.main.url(forResource: "WebContent", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebContent") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webContentURL)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

class VisionWebCoordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL {
            decisionHandler(.allow)
        } else if navigationAction.targetFrame?.isMainFrame == true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
