import AppKit
import CryptoKit
import Security

/// Keeps Stint current from its GitHub releases: checks every few hours, installs a newer build over this one in the
/// background, and restarts into it once you're away with no timer running (quitting or logging out picks it up too).
/// ponytail: trusts the release as much as a manual download (TLS to GitHub plus the asset's digest); a Developer ID
/// build also requires its own team's signature. Add EdDSA-signed feeds (Sparkle) if releases ever leave GitHub.
@MainActor @Observable
final class Updater {
    enum Status: Equatable {
        case idle, checking, upToDate
        case available(String), installing(String), installed(String)
        case failed(String)
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let digest: String?
        }
        let tagName: String
        let assets: [Asset]
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
        var disk: Asset? { assets.first { $0.name.hasSuffix(".dmg") } }
    }

    static let shared = Updater()
    static var automatic: Bool { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private static let latest = URL(string: "https://api.github.com/repos/doxigo/stint/releases/latest")!
    private static let checkEvery: TimeInterval = 6 * 3600
    private static let awayFor: TimeInterval = 5 * 60

    private(set) var status = Status.idle
    @ObservationIgnored private var release: Release?
    @ObservationIgnored private var checkedAt = Date.distantPast
    @ObservationIgnored private weak var store: Store?

    /// "0.5.10" is newer than "0.5.9".
    nonisolated static func isNewer(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedDescending
    }

    func start(_ store: Store) {
        self.store = store
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if case .installed = status {
                    if isAway { restart() }
                } else if Self.automatic, Date.now.timeIntervalSince(checkedAt) >= Self.checkEvery {
                    await check()
                }
            }
        }
    }

    func check(install: Bool = Updater.automatic) async {
        switch status {
        case .checking, .installing, .installed: return
        default: break
        }
        checkedAt = .now
        status = .checking
        do {
            var request = URLRequest(url: Self.latest)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw Failure("GitHub answered \(code); try again later.") }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(Release.self, from: data)
            guard Self.isNewer(release.version, than: Self.current) else { status = .upToDate; return }
            self.release = release
            status = .available(release.version)
            if install { await self.install() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func install() async {
        guard let release else { return }
        status = .installing(release.version)
        let app = Bundle.main.bundleURL
        var work: URL?
        defer { if let work { try? FileManager.default.removeItem(at: work) } }
        do {
            guard !app.path.contains("/AppTranslocation/") else {
                throw Failure("Move Stint to your Applications folder to install updates.")
            }
            guard let disk = release.disk else { throw Failure("Version \(release.version) has no disk image.") }
            let (download, _) = try await URLSession.shared.download(from: disk.browserDownloadUrl)
            // Next to the installed app, on its volume, so the swap below is a rename.
            let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: app, create: true)
            work = folder
            let image = folder.appending(path: disk.name)
            try FileManager.default.moveItem(at: download, to: image)
            let (digest, current) = (disk.digest, Self.current)
            let staged = try await Task.detached { try Self.stage(image, digest: digest, in: folder, newerThan: current) }.value
            // A running app keeps its open files, so this can happen now; the restart picks it up.
            _ = try FileManager.default.replaceItemAt(app, withItemAt: staged)
            status = .installed(release.version)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Relaunches into the installed update.
    func restart() {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                              Bundle.main.bundleURL.path]
        do { try relaunch.run() } catch { status = .failed(error.localizedDescription); return }
        NSApp.terminate(nil)
    }

    /// Restarting then loses nothing: no timer running (so no idle time to ask about), Stint in the background,
    /// and no input for a while.
    private var isAway: Bool {
        store?.runningTimer == nil && !NSApp.isActive
            && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: IdleMonitor.anyInput) >= Self.awayFor
    }

    /// Checks the image, copies the app out of it and checks the app. Returns the copy.
    nonisolated private static func stage(_ image: URL, digest: String?, in folder: URL, newerThan current: String) throws -> URL {
        if let digest {
            let hash = SHA256.hash(data: try Data(contentsOf: image)).map { String(format: "%02x", $0) }.joined()
            guard digest == "sha256:\(hash)" else { throw Failure("The download was damaged; Stint will try again later.") }
        }
        let mount = folder.appending(path: "mount")
        try run("/usr/bin/hdiutil", "attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path)
        defer { try? run("/usr/bin/hdiutil", "detach", mount.path, "-force") }
        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw Failure("The disk image has no app in it.") }
        let staged = folder.appending(path: app.lastPathComponent)
        try FileManager.default.copyItem(at: app, to: staged)
        let version = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard isNewer(version, than: current) else { throw Failure("The update is version \(version), not newer than \(current).") }
        try verify(staged)
        return staged
    }

    /// The update must be validly signed as this app, and by the same team when this build has one.
    nonisolated private static func verify(_ app: URL) throws {
        let id = Bundle.main.bundleIdentifier ?? "com.doxigo.TeamworkTimer"
        var requirement = "identifier \"\(id)\""
        if let team = teamID { requirement += " and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" }
        var code: SecStaticCode?
        var compiled: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                                         compiled) == errSecSuccess
        else { throw Failure("The update isn't signed as Stint, so it wasn't installed.") }
    }

    /// This build's Developer ID team; nil for ad-hoc and local builds.
    nonisolated private static var teamID: String? {
        var me: SecCode?
        var mine: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me, SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopySigningInformation(mine, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    nonisolated private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("\(URL(fileURLWithPath: tool).lastPathComponent) failed.") }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
