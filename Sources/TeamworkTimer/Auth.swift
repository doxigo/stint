import AppKit
import AuthenticationServices
import Network
import Security
import WebKit

/// Generic-password Keychain items for this app.
///
/// Items are stored under `<account>.v2`. Builds signed with the local self-signed identity still count as
/// a new app to the Keychain (its partition list needs an Apple-issued team ID), so macOS asks for the login
/// password once after each update; signing with an Apple Development certificate would remove that prompt.
/// Items from the ad-hoc-signed builds (plain `<account>`) are read once, copied to `.v2`, then removed.
enum Keychain {
    /// Per app ID, so a test copy with its own ID has its own sign-in (Stint itself: com.doxigo.TeamworkTimer).
    private static let service = Bundle.main.bundleIdentifier ?? "com.doxigo.TeamworkTimer"
    private static let suffix = ".v2"

    static func get(_ account: String) throws -> Data? {
        if let data = try read(account + suffix) { return data }
        guard let legacy = try read(account) else { return nil }
        try set(legacy, for: account)
        try remove(account)
        return legacy
    }

    /// `nil` deletes the item (and any legacy copy).
    static func set(_ data: Data?, for account: String) throws {
        guard let data else {
            try remove(account + suffix)
            try remove(account)
            return
        }
        let query = base(account + suffix)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }

    private static func read(_ account: String) throws -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    private static func remove(_ account: String) throws {
        let query = base(account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw SignInError("Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))")
        }
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

struct SignInError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Teamwork Launchpad OAuth (authorization-code flow), with Stint's built-in client or the user's own.
enum Launchpad {
    /// Stint's own Developer Portal app, when this build carries one. bundle.sh writes it into the built app's
    /// Info.plist from TEAMWORK_CLIENT_ID, TEAMWORK_CLIENT_SECRET (GitHub secrets in CI) and TEAMWORK_REDIRECT;
    /// the repo never has it. The secret is optional: a shipped secret can be read out of the app (see DESIGN.md,
    /// "Built-in sign-in").
    static let builtIn: (id: String, secret: String?, redirect: URL)? = {
        let value = { (key: String) in (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return value("TeamworkClientID").map { ($0, value("TeamworkClientSecret"), builtInRedirect(value("TeamworkRedirect"))) }
    }()

    static func makeState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        try Keychain.check(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes))
        return Data(bytes).base64EncodedString()
    }

    static func loginURL(clientID: String, redirect: URL, state: String) -> URL {
        var components = URLComponents(string: "https://www.teamwork.com/launchpad/login")!
        components.queryItems = [.init(name: "redirect_uri", value: redirect.absoluteString), .init(name: "client_id", value: clientID), .init(name: "state", value: state)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Without a secret, `client_secret` is left out (only works if Teamwork accepts the client without one).
    static func tokenRequest(code: String, clientID: String, clientSecret: String?, redirect: URL) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://www.teamwork.com/launchpad/v1/token.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["code": code, "client_id": clientID, "redirect_uri": redirect.absoluteString]
        body["client_secret"] = clientSecret
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func exchange(code: String, clientID: String, clientSecret: String?, redirect: URL) async throws -> Credentials {
        let request = try tokenRequest(code: code, clientID: clientID, clientSecret: clientSecret, redirect: redirect)
        let (data, response) = try await TeamworkClient.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // A code works once, for 15 minutes; Launchpad refuses an old or reused one.
            if (400..<500).contains(status), status != 429 {
                throw SignInError("Teamwork didn't accept the sign-in (\(status)). Sign-in codes expire after 15 minutes; try again.")
            }
            throw APIError(status: status, detail: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard token.installation.apiEndPoint.scheme == "https", token.installation.apiEndPoint.host != nil else {
            throw SignInError("Teamwork returned an invalid API endpoint.")
        }
        return Credentials(kind: .oauth, site: token.installation.apiEndPoint, secret: token.accessToken)
    }

    private struct TokenResponse: Decodable {
        struct Installation: Decodable { let apiEndPoint: URL }
        let accessToken: String
        let installation: Installation
        private enum CodingKeys: String, CodingKey { case accessToken = "access_token", installation }
    }
}

/// Catches the browser's redirect to `http://localhost:<port>` and returns the authorization code.
enum LoopbackServer {
    static func waitForCode(on redirect: URL, state: String, timeout: TimeInterval = 300) async throws -> String {
        guard oauthRedirect(redirect.absoluteString) != nil,
              let value = redirect.port.flatMap(UInt16.init(exactly:)), let port = NWEndpoint.Port(rawValue: value) else {
            throw SignInError("Use an HTTP loopback redirect with a port from 1 to 65535, e.g. http://localhost:8123")
        }
        // Loopback only (never the network), IPv4 and IPv6: "localhost" may resolve to ::1 or 127.0.0.1.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: port)
        defer { listener.cancel() }

        let once = Once<String>()
        // Cancelling (Settings' Cancel button) frees the port right away instead of after the timeout.
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.resume(throwing: SignInError("Sign-in timed out. Try again."))
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { once.resume(throwing: error) }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { connection.cancel() }
                receiveRequest(connection) { request in
                    let query = callbackQuery(fromRequest: request, redirect: redirect, state: state)
                    let message = query["code"] != nil ? "Return to Stint to finish signing in. You can close this tab." : "Sign-in didn't finish. You can close this tab."
                    let page = "<html><body style=\"font: 15px -apple-system, sans-serif; padding: 40px\">\(message)</body></html>"
                    let response = "HTTP/1.1 \(query.isEmpty ? "400 Bad Request" : "200 OK")\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    if let code = query["code"] {
                        once.resume(returning: code)
                    } else if let error = query["error"] {
                        once.resume(throwing: SignInError("Teamwork sign-in failed: \(error)"))
                    }
                }
            }
            listener.start(queue: .main)
          }
        } onCancel: {
            once.resume(throwing: CancellationError())
        }
    }

    private static func receiveRequest(_ connection: NWConnection, data: Data = Data(),
                                       complete: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384 - data.count) { chunk, _, ended, error in
            let buffer = data + (chunk ?? Data())
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                complete(String(decoding: buffer, as: UTF8.self))
            } else if error != nil || ended || buffer.count >= 16_384 {
                connection.cancel()
            } else {
                receiveRequest(connection, data: buffer, complete: complete)
            }
        }
    }
}

/// Signs in through `appRedirect` (`stint://oauth/callback`) with Apple's web authentication session: Teamwork's
/// login opens in a browser sheet that shares the user's browser session (one click when already signed in,
/// password autofill, Google and SSO, which refuse embedded web views), catches the redirect itself and closes.
@MainActor enum AppRedirect {
    /// Kept for the session's lifetime: it stops if released, and holds its context provider weakly.
    private static var active: (session: ASWebAuthenticationSession, anchor: Anchor)?

    static func waitForCode(login: URL, state: String) async throws -> String {
        let once = Once<URL>()
        // @Sendable: the session calls back on an XPC queue, not the main thread (a main-actor closure crashed there).
        let session = ASWebAuthenticationSession(url: login, callback: .customScheme(appRedirect.scheme!)) { @Sendable url, error in
            if let url {
                once.resume(returning: url)
            } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                once.resume(throwing: CancellationError())
            } else {
                once.resume(throwing: error ?? SignInError("Sign-in failed. Try again."))
            }
        }
        let anchor = Anchor()
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = false // reuse the browser's Teamwork sign-in
        active = (session, anchor)
        defer { if active?.session === session { active = nil } }
        let callback = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                if !session.start() { once.resume(throwing: SignInError("The sign-in page could not be opened.")) }
            }
        } onCancel: {
            once.resume(throwing: CancellationError())
            Task { @MainActor in active?.session.cancel() }
        }
        let query = callbackQuery(fromURL: callback, redirect: appRedirect, state: state)
        if let code = query["code"] { return code }
        throw SignInError(query["error"].map { "Teamwork sign-in failed: \($0)" } ?? "Teamwork didn't return a sign-in code. Try again.")
    }

    /// The window the browser sheet attaches to: the one the user clicked Sign In in.
    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor() }
        }
    }
}

/// Teamwork's login page in a Stint window, for the built-in app's default redirect (`teamworkRedirect`).
/// The navigation to the redirect is cancelled before it loads and its code taken; every other page loads as
/// usual, including single sign-on on other hosts. The subtitle shows the page's host. A non-persistent data
/// store keeps no Teamwork cookies or storage once the window closes, so each sign-in starts signed out.
@MainActor final class WebSignIn: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    private let redirect: URL
    private let state: String
    private let once = Once<String>()

    /// Opens the window on `login` and waits for the code; closing the window cancels. It stays up to
    /// 15 minutes, as long as a code lasts (single sign-on and two-factor steps can take a while).
    static func waitForCode(login: URL, redirect: URL, state: String, timeout: TimeInterval = 15 * 60) async throws -> String {
        let signIn = WebSignIn(redirect: redirect, state: state)
        signIn.window.center()
        signIn.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return try await signIn.code(from: login, timeout: timeout)
    }

    init(redirect: URL, state: String) {
        self.redirect = redirect
        self.state = state
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Sign in with Teamwork"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Loads `login` (the window needn't be on screen) and returns the code it redirects with.
    func code(from login: URL, timeout: TimeInterval) async throws -> String {
        let once = once
        defer { window.close() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    once.resume(throwing: SignInError("Sign-in timed out. Try again."))
                }
                webView.load(URLRequest(url: login))
            }
        } onCancel: {
            once.resume(throwing: CancellationError())
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, isRedirect(url, to: redirect) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        let query = callbackQuery(fromURL: url, redirect: redirect, state: state)
        if let code = query["code"] {
            once.resume(returning: code)
        } else if let error = query["error"] {
            once.resume(throwing: SignInError("Teamwork sign-in failed: \(error)"))
        } else {
            once.resume(throwing: SignInError("Teamwork's reply didn't match this sign-in. Try again."))
        }
    }

    /// ponytail: links that open a new window (target="_blank", window.open) load in this one, so a single
    /// sign-on popup still lands on the redirect. A popup that talks back to its opener would need a real child view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(action.request)
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        window.subtitle = webView.url?.host() ?? ""
    }

    /// A page that can't load (offline, a bad certificate) ends sign-in with its error. Loads stopped on purpose
    /// don't: a newer navigation, or the cancelled redirect ("frame load interrupted", WebKit's 102).
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled),
              !(error.domain == "WebKitErrorDomain" && error.code == 102) else { return }
        once.resume(throwing: error)
    }

    func windowWillClose(_ notification: Notification) {
        once.resume(throwing: CancellationError())
    }
}

/// Resumes a continuation at most once, from whichever callback fires first —
/// including a cancellation that arrives before the continuation is set.
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var earlyError: (any Error)?
    private var finished = false

    func set(_ continuation: CheckedContinuation<T, any Error>) {
        let early: (any Error)? = lock.withLock {
            if let earlyError { finished = true; return earlyError }
            self.continuation = continuation
            return nil
        }
        if let early { continuation.resume(throwing: early) }
    }

    func resume(returning value: T) { take()?.resume(returning: value) }

    func resume(throwing error: any Error) {
        let pending: CheckedContinuation<T, any Error>? = lock.withLock {
            guard !finished else { return nil }
            guard let continuation else { earlyError = error; return nil }
            finished = true
            self.continuation = nil
            return continuation
        }
        pending?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, any Error>? {
        lock.withLock {
            guard !finished, let continuation else { return nil }
            finished = true
            self.continuation = nil
            return continuation
        }
    }
}
