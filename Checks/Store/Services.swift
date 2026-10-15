// Keep integration checks away from the user's Keychain, notifications and idle prompts.
import AppKit
import Foundation

@MainActor enum Keychain {
    static var items: [String: Data] = [:]
    static var failure: Error?
    static func get(_ account: String) throws -> Data? {
        if let failure { throw failure }
        return items[account]
    }
    static func set(_ data: Data?, for account: String) throws {
        if let failure { throw failure }
        items[account] = data
    }
}
struct SignInError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
enum Launchpad {
    static let builtIn: (id: String, secret: String?)? = nil
    static func makeState() throws -> String { "unused" }
    static func loginURL(clientID: String, redirect: URL, state: String) -> URL { redirect }
    static func exchange(code: String, clientID: String, clientSecret: String?, redirect: URL) async throws -> Credentials { throw SignInError("Unused") }
}
enum LoopbackServer {
    static func waitForCode(on redirect: URL, state: String) async throws -> String { throw SignInError("Unused") }
}
@MainActor enum AppRedirect {
    static func waitForCode(state: String) async throws -> String { throw SignInError("Unused") }
}
@MainActor final class IdleMonitor {
    init(store: Store) {}
    func reset() {}
}
@MainActor final class Reminders {
    weak var store: Store?
    static var longTimerAlert: Bool { false }
    static func requestPermission() async {}
    func check() {}
    func reset() {}
}
