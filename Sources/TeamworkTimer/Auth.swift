import Foundation
import LocalAuthentication
import Network
import Security

/// Generic-password Keychain items for this app.
///
/// Items are stored under `<account>.v2`. Builds signed with the local self-signed identity still count as
/// a new app to the Keychain (its partition list needs an Apple-issued team ID), so macOS asks for the login
/// password once after each update; signing with an Apple Development certificate would remove that prompt.
/// Items from the ad-hoc-signed builds (plain `<account>`) are read once, copied to `.v2`, then removed.
enum Keychain {
    private static let service = "com.doxigo.TeamworkTimer"
    private static let suffix = ".v2"

    static func get(_ account: String) -> Data? {
        if let data = read(account + suffix) { return data }
        guard let legacy = read(account) else { return nil }
        set(legacy, for: account)
        remove(account, allowPrompt: false)
        return legacy
    }

    /// `nil` deletes the item (and any legacy copy).
    static func set(_ data: Data?, for account: String) {
        guard let data else {
            remove(account + suffix, allowPrompt: true)
            remove(account, allowPrompt: false)
            return
        }
        let query = base(account + suffix)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func read(_ account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func remove(_ account: String, allowPrompt: Bool) {
        var query = base(account)
        if !allowPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true // fail quietly rather than ask
            query[kSecUseAuthenticationContext as String] = context
        }
        SecItemDelete(query as CFDictionary)
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

struct SignInError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Teamwork Launchpad OAuth (authorization-code flow) with the user's own registered client.
enum Launchpad {
    static func loginURL(clientID: String, redirect: URL) -> URL {
        var components = URLComponents(string: "https://www.teamwork.com/launchpad/login")!
        components.queryItems = [.init(name: "redirect_uri", value: redirect.absoluteString), .init(name: "client_id", value: clientID)]
        return components.url!
    }

    static func exchange(code: String, clientID: String, clientSecret: String, redirect: URL) async throws -> Credentials {
        var request = URLRequest(url: URL(string: "https://www.teamwork.com/launchpad/v1/token.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "client_id": clientID, "client_secret": clientSecret, "redirect_uri": redirect.absoluteString,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, detail: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
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
    static func waitForCode(on redirect: URL, timeout: TimeInterval = 300) async throws -> String {
        guard let port = redirect.port.flatMap({ NWEndpoint.Port(rawValue: UInt16($0)) }) else {
            throw SignInError("The redirect URI needs a port, e.g. http://localhost:8123")
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
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let query = callbackQuery(fromRequest: data.map { String(decoding: $0, as: UTF8.self) } ?? "")
                    let message = query["code"] != nil ? "Signed in. You can close this tab." : "Sign-in didn't finish. You can close this tab."
                    let page = "<html><body style=\"font: 15px -apple-system, sans-serif; padding: 40px\">\(message)</body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(page)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    if let code = query["code"] {
                        once.resume(returning: code)
                    } else if let error = query["error"] {
                        once.resume(throwing: SignInError("Teamwork sign-in failed: \(error)"))
                    }
                    // Anything else (favicon.ico, …) is ignored; keep waiting.
                }
            }
            listener.start(queue: .main)
          }
        } onCancel: {
            once.resume(throwing: CancellationError())
        }
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
