import SwiftUI
import WebKit
import GameController

struct TVGameView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TVGameViewController {
        TVGameViewController()
    }
    func updateUIViewController(_ vc: TVGameViewController, context: Context) {}
}

class TVGameViewController: UIViewController {
    var webView: WKWebView!
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    var isPanning = false
    var activeKeys: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Setup WKWebView
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Inject remote control mapping script
        let remoteScript = WKUserScript(
            source: tvRemoteScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(remoteScript)

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        // Load game
        if let webContentURL = Bundle.main.url(forResource: "WebContent", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebContent") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webContentURL)
        }

        // Setup gesture recognizers for Siri Remote
        setupRemoteGestures()

        // Setup game controller support (physical controllers)
        setupGameController()

        // Keep screen awake
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // MARK: - Siri Remote Gestures

    func setupRemoteGestures() {
        // Trackpad pan → movement
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        // Tap (click center) → shoot
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(tap)

        // Play/Pause → pause game
        let playPause = UITapGestureRecognizer(target: self, action: #selector(handlePlayPause(_:)))
        playPause.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(playPause)
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: view)
        let deadzone: CGFloat = 50

        switch gesture.state {
        case .changed:
            var newKeys: Set<String> = []

            if velocity.x < -deadzone { newKeys.insert("ArrowLeft") }
            if velocity.x > deadzone { newKeys.insert("ArrowRight") }
            if velocity.y < -deadzone { newKeys.insert("ArrowUp") }
            if velocity.y > deadzone { newKeys.insert("ArrowDown") }

            // Release old keys
            for key in activeKeys.subtracting(newKeys) {
                injectKeyEvent(key: key, type: "keyup")
            }
            // Press new keys
            for key in newKeys.subtracting(activeKeys) {
                injectKeyEvent(key: key, type: "keydown")
            }
            activeKeys = newKeys

        case .ended, .cancelled:
            for key in activeKeys {
                injectKeyEvent(key: key, type: "keyup")
            }
            activeKeys = []

        default: break
        }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // Shoot (X key) + also handle menu clicks
        injectKeyEvent(key: "KeyX", type: "keydown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.injectKeyEvent(key: "KeyX", type: "keyup")
        }
        // Also simulate a click for menu buttons
        injectClick()
    }

    @objc func handlePlayPause(_ gesture: UITapGestureRecognizer) {
        injectKeyEvent(key: "Escape", type: "keydown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.injectKeyEvent(key: "Escape", type: "keyup")
        }
    }

    // Handle Menu button (back)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                injectKeyEvent(key: "Escape", type: "keydown")
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                injectKeyEvent(key: "Escape", type: "keyup")
                return
            }
        }
        super.pressesEnded(presses, with: event)
    }

    // MARK: - Game Controller (MFi / PlayStation / Xbox)

    func setupGameController() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect, object: nil
        )
        // Check for already-connected controllers
        for controller in GCController.controllers() {
            configureController(controller)
        }
    }

    @objc func controllerConnected(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            configureController(controller)
        }
    }

    func configureController(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        // Left stick → WASD
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }
            let deadzone: Float = 0.2
            var newKeys: Set<String> = []

            if xValue < -deadzone { newKeys.insert("ArrowLeft") }
            if xValue > deadzone { newKeys.insert("ArrowRight") }
            if yValue > deadzone { newKeys.insert("ArrowUp") }
            if yValue < -deadzone { newKeys.insert("ArrowDown") }

            for key in self.activeKeys.subtracting(newKeys) {
                self.injectKeyEvent(key: key, type: "keyup")
            }
            for key in newKeys.subtracting(self.activeKeys) {
                self.injectKeyEvent(key: key, type: "keydown")
            }
            self.activeKeys = newKeys
        }

        // A button → shoot
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.injectKeyEvent(key: "KeyX", type: pressed ? "keydown" : "keyup")
        }

        // B button → jump (for Crashed Adventure)
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.injectKeyEvent(key: "Space", type: pressed ? "keydown" : "keyup")
        }

        // X button → dash
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.injectKeyEvent(key: "ShiftLeft", type: pressed ? "keydown" : "keyup")
        }

        // Y button → gravity well
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.injectKeyEvent(key: "KeyQ", type: pressed ? "keydown" : "keyup")
        }

        // Menu → pause
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.injectKeyEvent(key: "Escape", type: "keydown") }
            else { self?.injectKeyEvent(key: "Escape", type: "keyup") }
        }
    }

    // MARK: - JavaScript Injection

    func injectKeyEvent(key: String, type: String) {
        let js = """
        (function() {
            var e = new KeyboardEvent('\(type)', {
                code: '\(key)',
                key: '\(key)',
                bubbles: true,
                cancelable: true
            });
            document.dispatchEvent(e);
            if (window.keys) window.keys['\(key)'] = \(type == "keydown" ? "true" : "false");
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func injectClick() {
        let js = """
        (function() {
            var focused = document.activeElement;
            if (focused && focused.tagName === 'BUTTON') {
                focused.click();
            } else {
                var buttons = document.querySelectorAll('button:not([style*="display:none"]):not([style*="visibility:hidden"])');
                if (buttons.length > 0) buttons[0].click();
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func tvRemoteScript() -> String {
        return """
        window.isNeonVoidApp = true;
        window.isTVOS = true;

        // Override auto-fire to always on (no mouse on TV)
        document.addEventListener('DOMContentLoaded', function() {
            // Enable auto-fire for TV
            if (typeof appSettings !== 'undefined') {
                appSettings.autoFire = true;
                appSettings.mobile = false;
            }
        });

        // TV remote hint overlay
        setTimeout(function() {
            if (document.getElementById('login-screen') && !document.getElementById('login-screen').classList.contains('hidden')) {
                var hint = document.createElement('div');
                hint.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:999;font-family:monospace;font-size:12px;color:#555;text-align:center;pointer-events:none;';
                hint.innerHTML = 'SWIPE: Move | CLICK: Select/Shoot | PLAY/PAUSE: Pause | MENU: Back';
                document.body.appendChild(hint);
                setTimeout(function() { hint.style.opacity = '0'; hint.style.transition = 'opacity 2s'; }, 8000);
            }
        }, 2000);
        """
    }
}
