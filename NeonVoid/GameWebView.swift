import SwiftUI
import WebKit
import AuthenticationServices
import LocalAuthentication

struct GameWebView: UIViewRepresentable {
    let safeAreaInsets: EdgeInsets

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // JS bridge — handles haptics, keepAwake, openExternal, and auth messages
        config.userContentController.add(context.coordinator, name: "neonVoid")

        // Inject safe area CSS vars + app detection at document start
        let safeAreaScript = WKUserScript(
            source: safeAreaJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(safeAreaScript)

        // Inject "Sign in with Apple" button replacement at document end
        let appleAuthScript = WKUserScript(
            source: appleSignInJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(appleAuthScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.024, green: 0.024, blue: 0.047, alpha: 1.0) // #06060c
        webView.scrollView.backgroundColor = UIColor(red: 0.024, green: 0.024, blue: 0.047, alpha: 1.0)
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        // Load bundled HTML - try multiple paths
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebContent") {
            let accessURL = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: accessURL)
        } else if let webContentURL = Bundle.main.url(forResource: "WebContent", withExtension: nil) {
            let indexURL = webContentURL.appendingPathComponent("index.html")
            webView.loadFileURL(indexURL, allowingReadAccessTo: webContentURL)
        } else {
            // Debug: list what's in the bundle
            let bundlePath = Bundle.main.bundlePath
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(atPath: bundlePath) {
                print("NEONVOID: Bundle contents: \(items)")
            }
            webView.loadHTMLString("<html><body style='background:#06060c;color:#ff0055;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0'><h1>WebContent not found in bundle</h1></body></html>", baseURL: nil)
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

    // MARK: - Injected JavaScript

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

    /// Injects JavaScript that replaces the DEPLOY button with a native-style
    /// "Sign in with Apple" button when running inside the iOS app.
    /// The button sends a message to Swift via webkit.messageHandlers.neonVoid,
    /// and Swift calls back with the user info once authentication is complete.
    private func appleSignInJS() -> String {
        // If the user is already signed in, pass their credentials immediately.
        let savedUserID   = AuthManager.shared.userID   ?? ""
        let savedUsername = AuthManager.shared.username ?? ""
        let alreadySignedIn = AuthManager.shared.isSignedIn

        return """
        (function() {
            if (!window.isNeonVoidApp) return;

            // Hide the Google sign-in container (web only)
            var gContainer = document.getElementById('google-signin-container');
            if (gContainer) gContainer.style.display = 'none';

            // ── If already signed in, auto-complete login after biometric check ──
            var savedUserID   = '\(savedUserID.replacingOccurrences(of: "'", with: "\\'"))';
            var savedUsername = '\(savedUsername.replacingOccurrences(of: "'", with: "\\'"))';
            var alreadySignedIn = \(alreadySignedIn ? "true" : "false");

            if (alreadySignedIn && savedUserID && savedUsername) {
                // Biometric gate: Swift will call neonVoidAppleSignIn with the
                // saved credentials if biometrics pass (handled in didFinish nav).
                webkit.messageHandlers.neonVoid.postMessage({
                    action: 'appleSignInBiometric',
                    userID: savedUserID,
                    username: savedUsername
                });
                return;
            }

            // ── First-time: inject "Sign in with Apple" button ──
            var loginBtn = document.getElementById('login-btn');
            if (!loginBtn) return;

            // Hide the manual login inputs (username / password)
            var usernameInput = document.getElementById('username-input');
            var passwordInput = document.getElementById('password-input');
            var passHint      = passwordInput ? passwordInput.nextElementSibling : null;
            if (usernameInput) usernameInput.style.display = 'none';
            if (passwordInput) passwordInput.style.display = 'none';
            if (passHint && passHint.tagName === 'DIV') passHint.style.display = 'none';

            // Replace DEPLOY button with Apple Sign-In button
            loginBtn.style.cssText = [
                'display:flex', 'align-items:center', 'justify-content:center', 'gap:10px',
                'background:#000', 'border:2px solid #ffffff30',
                'box-shadow:0 0 18px rgba(255,255,255,0.15)',
                'color:#fff', 'padding:13px 32px',
                'font-family:monospace', 'font-size:15px', 'font-weight:700', 'letter-spacing:3px',
                'cursor:pointer', 'border-radius:8px', 'min-width:260px', 'transition:all 0.3s'
            ].join(';');
            loginBtn.innerHTML =
                '<svg width="18" height="22" viewBox="0 0 814 1000" xmlns="http://www.w3.org/2000/svg" fill="#fff">' +
                '<path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-58.8-155.5-127.4C46 790.7 0 663 0 541.8c0-207.5 135.4-317.3 269-317.3 71 0 130.5 46.4 174.9 46.4 42.7 0 109.2-49 192.8-49 31.3 0 113.4 2.9 179.4 70.9zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/>' +
                '</svg>' +
                'SIGN IN WITH APPLE';

            loginBtn.onclick = function() {
                webkit.messageHandlers.neonVoid.postMessage({ action: 'appleSignIn' });
            };

            // Add a "sign in manually" fallback link
            var manualLink = document.createElement('div');
            manualLink.id  = 'manual-signin-toggle';
            manualLink.style.cssText = 'color:#555; font-size:11px; letter-spacing:2px; cursor:pointer; margin-top:4px;';
            manualLink.textContent   = 'SIGN IN MANUALLY INSTEAD';
            manualLink.onclick = function() {
                if (usernameInput) usernameInput.style.display = '';
                if (passwordInput) passwordInput.style.display = '';
                if (passHint && passHint.tagName === 'DIV') passHint.style.display = '';
                loginBtn.style.cssText = 'border-color:#00ffcc; color:#000; background:linear-gradient(135deg,#00ffcc,#00aa88); box-shadow:0 0 30px #00ffcc80; padding:12px 50px; font-size:18px; font-weight:900; letter-spacing:4px; cursor:pointer; transition:all 0.3s; border-radius:4px;';
                loginBtn.textContent = 'DEPLOY';
                loginBtn.onclick = function() { if (typeof loginUser === 'function') loginUser(); };
                manualLink.style.display = 'none';
            };
            loginBtn.parentNode.insertBefore(manualLink, loginBtn.nextSibling);
        })();
        """
    }
}

// MARK: - WebViewCoordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?

    // MARK: JS → Swift messages

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {

        // ── Existing handlers ──────────────────────────────────────
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

        // ── Apple Sign-In (first time) ─────────────────────────────
        case "appleSignIn":
            DispatchQueue.main.async { [weak self] in
                self?.presentAppleSignIn()
            }

        // ── Apple Sign-In (biometric gate for returning users) ──────
        case "appleSignInBiometric":
            let userID   = body["userID"]   as? String ?? ""
            let username = body["username"] as? String ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.authenticateWithBiometrics(userID: userID, username: username)
            }

        default:
            break
        }
    }

    // MARK: - Apple Sign-In

    private func presentAppleSignIn() {
        guard let webView = webView,
              let rootVC  = webView.window?.rootViewController else { return }

        AuthManager.shared.onSignInComplete = { [weak self] userID, username in
            self?.passAuthToWebView(userID: userID, username: username)
        }

        AuthManager.shared.requestAppleSignIn(from: rootVC)
    }

    // MARK: - Biometric Authentication

    private func authenticateWithBiometrics(userID: String, username: String) {
        let bio = BiometricAuth()
        guard bio.biometricType != .none else {
            // No biometrics — auto-login directly
            passAuthToWebView(userID: userID, username: username)
            return
        }

        let reason = "Authenticate to access Neon Void"
        bio.authenticate(reason: reason) { [weak self] success in
            if success {
                self?.passAuthToWebView(userID: userID, username: username)
            } else {
                // Biometric failed — show the Apple Sign-In button again so
                // the user can try a different method
                self?.webView?.evaluateJavaScript(
                    "document.getElementById('login-screen')?.classList.remove('hidden');",
                    completionHandler: nil
                )
            }
        }
    }

    // MARK: - Pass Auth Result to Web

    /// Calls back into JavaScript with the authenticated user's info so the
    /// game can use the Apple ID as a cloud-save key and the name as callsign.
    private func passAuthToWebView(userID: String, username: String) {
        // Escape single quotes in both values for safe JS string interpolation
        let safeID   = userID.replacingOccurrences(of: "'", with: "\\'")
        let safeName = username.replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function() {
            if (typeof completeLogin === 'function') {
                completeLogin('\(safeName)', '\(safeID)');
            } else {
                // Fallback: set username directly and trigger loginUser
                var input = document.getElementById('username-input');
                if (input) { input.value = '\(safeName)'; }
                if (typeof loginUser === 'function') loginUser();
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    // Navigation policy: local files allowed, external URLs open in Safari
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
        // Keep screen awake during gameplay
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
