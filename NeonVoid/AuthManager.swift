import Foundation
import AuthenticationServices
import LocalAuthentication

// MARK: - AuthManager
// Handles Sign in with Apple flow and credential persistence.

class AuthManager: NSObject {

    // UserDefaults keys
    static let kUserID   = "neonVoidAppleUserID"
    static let kUsername = "neonVoidUsername"

    // Shared singleton
    static let shared = AuthManager()

    // Callback invoked after a successful Apple sign-in
    var onSignInComplete: ((_ userID: String, _ username: String) -> Void)?

    // MARK: - Computed Properties

    var isSignedIn: Bool {
        return userID != nil && username != nil
    }

    var userID: String? {
        UserDefaults.standard.string(forKey: AuthManager.kUserID)
    }

    var username: String? {
        UserDefaults.standard.string(forKey: AuthManager.kUsername)
    }

    // MARK: - Sign In with Apple

    /// Presents the Apple ID authorization sheet.
    /// - Parameter presentingController: The view controller that will anchor the sheet.
    func requestAppleSignIn(from presentingController: UIViewController) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = PresentationContextProvider(
            window: presentingController.view.window
        )
        controller.performRequests()
    }

    /// Checks Apple's credential state for a previously signed-in user.
    /// Calls `completion(true)` if still valid, `completion(false)` if revoked/not found.
    func checkCredentialState(completion: @escaping (Bool) -> Void) {
        guard let uid = userID else { completion(false); return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: uid) { state, _ in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    completion(true)
                case .revoked, .notFound:
                    self.signOut()
                    completion(false)
                default:
                    completion(false)
                }
            }
        }
    }

    // MARK: - Persistence

    func saveCredentials(userID: String, username: String) {
        UserDefaults.standard.set(userID,   forKey: AuthManager.kUserID)
        UserDefaults.standard.set(username, forKey: AuthManager.kUsername)
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: AuthManager.kUserID)
        UserDefaults.standard.removeObject(forKey: AuthManager.kUsername)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }

        let uid = appleCredential.user

        // Build a display name from the full name (only provided on first sign-in).
        // Fall back to the saved username if already set, or a generic pilot name.
        let derivedName: String
        if let fullName = appleCredential.fullName,
           let given = fullName.givenName, !given.isEmpty {
            // Sanitise: keep alphanumeric + underscore, max 16 chars, uppercase
            let sanitised = given
                .uppercased()
                .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_")).inverted)
                .joined()
            derivedName = String(sanitised.prefix(16))
        } else {
            // Subsequent launches — Apple no longer provides the name
            derivedName = username ?? "PILOT"
        }

        let finalName = derivedName.isEmpty ? "PILOT" : derivedName
        saveCredentials(userID: uid, username: finalName)

        DispatchQueue.main.async {
            self.onSignInComplete?(uid, finalName)
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // User cancelled or an error occurred — no action needed
        print("NeonVoid AuthManager: Apple sign-in error: \(error.localizedDescription)")
    }
}

// MARK: - Presentation Context Helper

private class PresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    weak var window: UIWindow?
    init(window: UIWindow?) { self.window = window }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return window ?? UIWindow()
    }
}

// MARK: - BiometricAuth
// Handles Face ID / Touch ID authentication using LocalAuthentication.

class BiometricAuth {

    enum BiometricType {
        case none, faceID, touchID
    }

    /// Returns the biometric type available on this device.
    var biometricType: BiometricType {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        if #available(iOS 11.0, *) {
            return ctx.biometryType == .faceID ? .faceID : .touchID
        }
        return .touchID
    }

    /// Attempts biometric authentication.
    /// - Parameters:
    ///   - reason: The localised reason string shown in the system dialog.
    ///   - completion: Called on the main thread with `true` on success, `false` on failure/cancellation.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var error: NSError?

        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
