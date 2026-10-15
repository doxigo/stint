import Foundation
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

/// Teamwork Launchpad OAuth (authorization-code flow) with the user's own registered client.
enum Launchpad {
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
