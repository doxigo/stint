import AppKit
import Observation
import CryptoKit
import SwiftUI // IndexSet-based `move(fromOffsets:toOffset:)`

/// App state. Teamwork is the source of truth for timers and time entries; pins, recents and time
/// adjustments are local.
@MainActor @Observable
final class Store {
    // ponytail: polling; switch to a push channel if Teamwork exposes one for timers
    static let pollSeconds = 15.0

    enum Section: String, CaseIterable, Identifiable {
        case timers = "Timers", today = "Today", week = "This Week", pinned = "Pinned"
        case starred = "Starred Projects", tasks = "My Tasks"
        case settings = "Settings", account = "Account"
        var id: Self { self }
        /// The pages that need a signed-in account; Settings and Account sit in the sidebar's footer.
        static let library: [Section] = [.timers, .today, .week, .pinned, .starred, .tasks]
        var symbol: String {
            switch self {
            case .timers: "timer"
            case .today: "sun.max"
            case .week: "calendar"
            case .pinned: "pin"
            case .starred: "star"
            case .tasks: "checklist"
            case .settings: "gearshape"
            case .account: "person.crop.circle"
            }
        }
    }

    private(set) var client: TeamworkClient?
    private(set) var site: URL?
    private(set) var accountName: String?
    private(set) var userId: Int?
    private(set) var timers: [TWTimer] = []
    private(set) var starred: [Project] = []
    private(set) var pins: [WorkItem] = []
    private(set) var recents: [WorkItem] = []
    /// Seconds taken off a timer's Teamwork time (an edited or idle-trimmed time Teamwork didn't take; negative adds
    /// time), applied when it's logged.
    // ponytail: only a fallback, since edits and idle removal set Teamwork's time; the web app shows Teamwork's time
    // until it's logged.
    private(set) var adjustments: [Int: TimeInterval] = [:]
    /// Logged today, in seconds (refreshed when the popover or Today view opens).
    private(set) var loggedToday: TimeInterval = 0
    /// Bumped after each successful log so entry lists reload.
    private(set) var logRevision = 0
    /// Logged entries per week (key: the week's start), shared by the popover and the window. A week shows
    /// from here at once while it reloads in the background; the weeks either side load ahead.
    // ponytail: never evicted; a week is a few dozen entries.
    private(set) var weeks: [Date: [TimeEntry]] = [:]
    /// Clock for the menu bar label, ticking once a second only while a timer runs.
    /// Time-based views (`Text(timerInterval:)`, `TimelineView`) spin at 100 % CPU inside a MenuBarExtra label,
    /// so the label renders plain text against this instead.
    private(set) var menuBarNow = Date.now
    @ObservationIgnored private var ticker: Task<Void, Never>?
    var section: Section? = .timers
    var showingNewTimer = false
    var showingLogAll = false
    /// Your working hours per weekday and working day (`lengthOfDay`) from Teamwork, in seconds; nil if not set.
    private(set) var teamworkHours: [Int: TimeInterval]?
    private(set) var teamworkDayLength: TimeInterval?
    /// Your own working day from Settings, replacing Teamwork's on each working day; nil uses Teamwork's.
    var customDayLength: TimeInterval? {
        didSet { defaults.set(customDayLength, forKey: "customDayLength") }
    }
    /// Tasks assigned to you and due today, for the popover.
    private(set) var dueToday: [WorkItem] = []
    /// Opens the main window from places without a SwiftUI environment (notification actions).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    var errorMessage: String?
    /// A short confirmation after a successful write (`ToastOverlay` shows it). Failures go to `errorMessage`.
    private(set) var toast: Toast?
    @ObservationIgnored private var toastExpiry: Task<Void, Never>?

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let symbol: String
    }

    private var projectNames: [Int: String] = [:]
    private var taskNames: [Int: String] = [:]
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored let reminders = Reminders()
    private(set) var sessionID = UUID()
    enum LogStatus: String, Codable { case uncertain, posted }
    private(set) var logAttempts: [Int: LogStatus] = [:]
    private var accountReady = false
    private var loggingTimers: Set<Int> = []
    @ObservationIgnored private var completedTimers: Set<Int> = []
    @ObservationIgnored private var pollError: String?
    @ObservationIgnored private var starting: Set<String> = []
    @ObservationIgnored private var loggingItems: Set<String> = []
    @ObservationIgnored private var requests: [UUID: () -> Void] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logDirectory: URL
    private var accountKey: String? {
        guard let site, let userId else { return nil }
        return "account.\(site.absoluteString).\(userId)"
    }
    private var logFile: URL? {
        accountKey.map { logDirectory.appending(path: SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() + ".json") }
    }
    @ObservationIgnored private var idle: IdleMonitor?

    var isSignedIn: Bool { client != nil }
    var activeTimer: TWTimer? { timers.first(where: \.running) ?? timers.first }
    var runningTimer: TWTimer? { timers.first(where: \.running) }

    /// Seconds to work in an interval (a day, a week); nil when it has no working days.
    func target(in interval: DateInterval) -> TimeInterval? {
        workTarget(in: interval, days: workingDays(teamwork: teamworkHours, lengthOfDay: teamworkDayLength, custom: customDayLength))
    }

    init(defaults: UserDefaults = .standard,
         logDirectory: URL = URL.applicationSupportDirectory.appending(path: "com.doxigo.TeamworkTimer/LogAttempts")) {
        self.defaults = defaults
        self.logDirectory = logDirectory
        customDayLength = defaults.object(forKey: "customDayLength") as? TimeInterval
        reminders.store = self
        idle = IdleMonitor(store: self)
        do {
            if let data = try Keychain.get("credentials") {
                activate(try JSONDecoder().decode(Credentials.self, from: data))
                Task { await loadStarred() }
            }
        } catch { errorMessage = error.localizedDescription }
        Task {
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                await refresh()
            }
        }
    }

    // MARK: Session

    func signIn(site input: String, token: String) async throws {
        guard let site = normalizedSite(input) else { throw SignInError("Enter your Teamwork site, e.g. acme.teamwork.com") }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try await connect(Credentials(kind: .apiToken, site: site, secret: token))
    }

    func signInWithOAuth(clientID: String, clientSecret: String, redirect: String) async throws {
        guard let redirect = oauthRedirect(redirect) else {
            throw SignInError("Use an HTTP loopback redirect with a port from 1 to 65535, e.g. http://localhost:8123")
        }
        let state = try Launchpad.makeState()
        async let code = LoopbackServer.waitForCode(on: redirect, state: state)
        guard NSWorkspace.shared.open(Launchpad.loginURL(clientID: clientID, redirect: redirect, state: state)) else {
            throw SignInError("The sign-in page could not be opened.")
        }
        let credentials = try await Launchpad.exchange(code: try await code, clientID: clientID, clientSecret: clientSecret, redirect: redirect)
        try Task.checkCancellation()
        try? Keychain.set(Data(clientSecret.utf8), for: "oauthClientSecret") // convenience only; the code is already spent
        NSApp.activate()
        try await connect(credentials)
    }

    static func savedOAuthSecret() throws -> String? {
        try Keychain.get("oauthClientSecret").map { String(decoding: $0, as: UTF8.self) }
    }

    func signOut() throws {
        try Keychain.set(nil, for: "credentials")
        clearSession()
    }

    private func clearSession() {
        poller?.cancel()
        for cancel in requests.values { cancel() }
        requests = [:]
        sessionID = UUID()
        client = nil
        site = nil
        accountName = nil
        userId = nil
        teamworkHours = nil
        teamworkDayLength = nil
        timers = []
        starred = []
        pins = []
        recents = []
        dueToday = []
        adjustments = [:]
        projectNames = [:]
        taskNames = [:]
        weeks = [:]
        logAttempts = [:]
        accountReady = false
        loggingTimers = []
        completedTimers = []
        loggedToday = 0
        logRevision = 0
        showingNewTimer = false
        showingLogAll = false
        errorMessage = nil
        toast = nil
        idle?.reset()
        reminders.reset()
        updateTicker()
    }

    /// Starts the menu bar clock while a timer runs; stops it otherwise.
    func updateTicker() {
        guard runningTimer != nil else {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.menuBarNow = .now
            }
        }
    }

    private func connect(_ credentials: Credentials) async throws {
        let session = sessionID
        let me = try await TeamworkClient(credentials: credentials).me()
        try Task.checkCancellation()
        guard sessionID == session else { throw CancellationError() }
        try Keychain.set(try JSONEncoder().encode(credentials), for: "credentials")
        activate(credentials)
        identify(me)
        await loadStarred()
        if Reminders.longTimerAlert { await Reminders.requestPermission() }
    }

    private func identify(_ me: (id: Int, name: String, dayLength: TimeInterval?, hours: [Int: TimeInterval]?)) {
        accountReady = false
        (userId, accountName, teamworkDayLength, teamworkHours) = (me.id, me.name, me.dayLength, me.hours)
        pins = load("pins") ?? adoptLegacy("pins") ?? []
        recents = load("recents") ?? adoptLegacy("recents") ?? []
        adjustments = load("adjustments") ?? adoptLegacy("adjustments") ?? [:]
        if let logFile, FileManager.default.fileExists(atPath: logFile.path) {
            do {
                logAttempts = try JSONDecoder().decode([Int: LogStatus].self, from: Data(contentsOf: logFile))
            } catch {
                // An unreadable receipt file mustn't lock the account out of polling and logging: set it aside and warn.
                let aside = logFile.appendingPathExtension("unreadable")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: logFile, to: aside)
                errorMessage = "Earlier log receipts couldn't be read. If a log was interrupted, check Teamwork for a duplicate entry."
            }
        }
        accountReady = true
    }

    private func activate(_ credentials: Credentials) {
        clearSession()
        client = TeamworkClient(credentials: credentials)
        site = credentials.site
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // This week is ready before the popover first opens (retried until it loads).
                if self?.weeks.isEmpty == true { await self?.loadWeek(containing: .now) }
                guard !Task.isCancelled else { return }
                self?.reminders.check()
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
            }
        }
    }

    // MARK: Sync

    /// False when the timers couldn't be fetched.
    @discardableResult
    func refresh() async -> Bool {
        if !accountReady {
            guard let me = await poll({ try await $0.me() }) else { return false }
            identify(me)
        }
        guard let page = await poll({ try await $0.timers() }) else { return false }
        // A failed poll's banner (e.g. offline right after wake) clears once polling works; failed writes stay.
        if let pollError, errorMessage == pollError { errorMessage = nil }
        pollError = nil
        merge(page.included)
        timers = page.timers.sorted { ($0.running ? 1 : 0, $0.lastActive) > ($1.running ? 1 : 0, $1.lastActive) }
        updateTicker()
        if let running = runningTimer, let item = workItem(for: running) { remember(item) }
        // Time already logged but the timer's removal failed: remove it now, so it can't keep running and have
        // its extra time dropped by a later remove-only log.
        for timer in timers where logAttempts[timer.id] == .posted && !loggingTimers.contains(timer.id) {
            if await perform({ try await $0.delete(timer.id) }) != nil {
                completedTimers.insert(timer.id)
                timers.removeAll { $0.id == timer.id }
            }
        }
        let live = Set(timers.map(\.id))
        if adjustments.keys.contains(where: { !live.contains($0) }) {
            adjustments = adjustments.filter { live.contains($0.key) }
            save(adjustments, "adjustments")
        }
        return true
    }

    func loadStarred() async {
        if let projects = await perform({ try await $0.starredProjects() }) { starred = projects }
    }

    func refreshToday() async {
        guard let entries = await timeEntries(from: .now, to: .now) else { return }
        loggedToday = TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60)
    }

    /// Reloads the week containing `date`, then fetches the weeks either side that aren't cached yet
    /// (never future ones), so stepping through days and weeks shows totals without waiting.
    func loadWeek(containing date: Date) async {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
        await fetchWeek(week)
        for offset in [-1, 1] {
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: week.start),
                  start <= .now, weeks[start] == nil,
                  let neighbour = calendar.dateInterval(of: .weekOfYear, for: start) else { continue }
            await fetchWeek(neighbour)
        }
    }

    private func fetchWeek(_ week: DateInterval) async {
        if let entries = await timeEntries(from: week.start, to: week.end.addingTimeInterval(-1)) { weeks[week.start] = entries }
    }

    /// nil when Teamwork couldn't be reached, so callers keep what they had.
    func timeEntries(from: Date, to: Date) async -> [TimeEntry]? {
        guard let userId, let page = await perform({ try await $0.timeEntries(userId: userId, from: from, to: to) }) else { return nil }
        merge(page.included)
        return page.timelogs
    }

    func myTasks(_ filter: TeamworkClient.TaskFilter) async -> [WorkItem]? {
        guard let userId else { return nil }
        return await perform { try await $0.myTasks(userId: userId, filter: filter) }
    }

    // MARK: Timer actions

    /// The timer already tracking this work, if any. Teamwork allows one timer per task.
    func timer(for item: WorkItem) -> TWTimer? {
        timers.first { $0.projectId == item.projectId && $0.taskId == item.taskId }
    }

    func start(_ item: WorkItem) async {
        // Teamwork refuses a second timer on the same task (403): resume or keep the existing one instead.
        if let existing = timer(for: item) {
            if !existing.running { await toggle(existing) }
            remember(item)
            return
        }
        // A double click sends one request.
        let key = "\(item.projectId)-\(item.taskId ?? 0)"
        guard starting.insert(key).inserted else { return }
        defer { starting.remove(key) }
        if await perform({ try await $0.startTimer(item) }) != nil { remember(item) }
        await refresh()
    }

    /// Pauses the running timer, else resumes the last one. Menu command and global shortcut.
    func pauseOrResume() async {
        if let runningTimer { await toggle(runningTimer) } else { await resumeLast() }
    }

    func resumeLast() async {
        if let paused = timers.first(where: { !$0.running }) { await toggle(paused) }
        else if let last = recents.first { await start(last) }
    }

    func toggle(_ timer: TWTimer) async {
        let other = timers.first { $0.running && $0.id != timer.id }
        await perform { client in
            if timer.running {
                try await client.pause(timer.id)
            } else {
                // One running timer at a time; don't rely on the server pausing the other one.
                if let other { try await client.pause(other.id) }
                try await client.resume(timer.id)
            }
        }
        await refresh()
    }

    /// Time shown and logged for a timer: Teamwork's time with the local adjustment applied.
    func elapsed(_ timer: TWTimer, at now: Date = .now) -> TimeInterval {
        max(0, timer.elapsed(at: now) - (adjustments[timer.id] ?? 0))
    }


    /// Logs the timer. Teamwork's own "complete" is used when nothing was changed; an edited duration,
    /// removed idle time or "mark task complete" logs the entry directly and then deletes the timer.
    /// Returns false if Teamwork refused.
    func log(_ timer: TWTimer, seconds: TimeInterval, durationEdited: Bool, description: String, billable: Bool,
             markTaskComplete: Bool) async -> Bool {
        let session = sessionID
        // A receipt means this time was logged earlier and only the leftover timer goes now: no "Logged" toast.
        let fresh = logAttempts[timer.id] == nil
        let logged = await logTimer(timer, seconds: seconds, durationEdited: durationEdited,
                                    description: description, billable: billable, markTaskComplete: markTaskComplete)
        guard sessionID == session else { return false }
        if logged { logRevision += 1 }
        await refresh()
        await refreshToday()
        if logged && fresh { showToast("Logged \(seconds.hoursMinutes) to \(title(of: timer))") }
        return logged
    }

    /// Logs time straight to a task or project on `day`, with no timer created or touched.
    /// Returns false if Teamwork refused.
    func log(_ item: WorkItem, seconds: TimeInterval, on day: Date, description: String, billable: Bool,
             markTaskComplete: Bool) async -> Bool {
        guard seconds.isFinite, seconds >= 60, seconds <= 86400 else {
            errorMessage = "Enter a duration between one minute and 24 hours."
            return false
        }
        // A double click posts once.
        let key = "\(item.projectId)-\(item.taskId ?? 0)"
        guard loggingItems.insert(key).inserted else { return false }
        defer { loggingItems.remove(key) }
        let session = sessionID
        // Ends at this time of day (now, for today), but never before the day starts, so it stays on that day.
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let end = dayStart.addingTimeInterval(Date.now.timeIntervalSince(calendar.startOfDay(for: .now)))
        let start = max(dayStart, end.addingTimeInterval(-seconds))
        // ponytail: no receipt as timers keep; a retry after an ambiguous failure (5xx, timeout) can log twice.
        let posted: Void? = await perform {
            try await $0.logTime(projectId: item.projectId, taskId: item.taskId, seconds: seconds, start: start,
                                 description: description, billable: billable, markTaskComplete: markTaskComplete)
        }
        guard sessionID == session, posted != nil else { return false }
        logRevision += 1
        remember(item)
        await refreshToday()
        showToast("Logged \(seconds.hoursMinutes) to \(item.title)")
        return true
    }

    func isLogging(_ id: Int) -> Bool { loggingTimers.contains(id) }

    private func logTimer(_ timer: TWTimer, seconds: TimeInterval, durationEdited: Bool, description: String,
                          billable: Bool, markTaskComplete: Bool) async -> Bool {
        if completedTimers.contains(timer.id) { return true }
        guard accountReady else { errorMessage = "Account recovery must finish before logging."; return false }
        guard loggingTimers.insert(timer.id).inserted else { return false }
        let session = sessionID
        defer { if sessionID == session { loggingTimers.remove(timer.id) } }
        guard timers.contains(where: { $0.id == timer.id }) else {
            errorMessage = "This timer no longer exists. Refresh before logging."
            return false
        }
        if logAttempts[timer.id] == .uncertain {
            errorMessage = "The previous log may have succeeded. Check Teamwork before retrying."
            return false
        }
        let direct = durationEdited || markTaskComplete || adjustments[timer.id] != nil
        if logAttempts[timer.id] != .posted {
            guard seconds.isFinite, seconds >= 60, !direct || seconds <= 86400 else {
                errorMessage = "Enter a duration between one minute and 24 hours."
                return false
            }
            if !direct, description != timer.description || billable != timer.billable {
                guard await perform({ try await $0.update(timer, description: description, billable: billable) }) != nil else { return false }
            }
            guard !direct || timer.projectId != nil else { errorMessage = "This timer has no project to log against."; return false }
            do { try setLogStatus(.uncertain, for: timer.id) } catch { errorMessage = error.localizedDescription; return false }
            let posted: Void? = await perform { client in
                do {
                    if direct {
                        try await client.logTime(projectId: timer.projectId!, taskId: timer.taskId, seconds: seconds,
                                                 start: timer.startedAt ?? .now.addingTimeInterval(-seconds),
                                                 description: description, billable: billable, markTaskComplete: markTaskComplete)
                    } else { try await client.complete(timer.id) }
                } catch {
                    if self.sessionID == session, let api = error as? APIError, (400..<500).contains(api.status), api.status != 408 {
                        try self.setLogStatus(nil, for: timer.id)
                    }
                    throw error
                }
            }
            guard sessionID == session else { return false }
            guard posted != nil else { return false }
            do { try setLogStatus(.posted, for: timer.id) } catch { errorMessage = "Time was logged, but its receipt could not be saved. Check Teamwork before retrying. \(error.localizedDescription)"; return false }
            if !direct {
                completedTimers.insert(timer.id)
                timers.removeAll { $0.id == timer.id }
                return true
            }
        }
        if await perform({ try await $0.delete(timer.id) }) != nil {
            completedTimers.insert(timer.id)
            timers.removeAll { $0.id == timer.id }
        } else if sessionID == session {
            errorMessage = "Time is already logged. The timer could not be removed; retrying will only remove it."
        }
        return sessionID == session
    }

    private func setLogStatus(_ status: LogStatus?, for id: Int) throws {
        guard let logFile else { throw SignInError("The account is not ready for logging.") }
        var attempts = logAttempts
        attempts[id] = status
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(attempts).write(to: logFile, options: .atomic)
        logAttempts = attempts
    }

    func resolveLog(_ timer: TWTimer, entryExists: Bool) async {
        guard let status = logAttempts[timer.id], status == .uncertain || entryExists,
              !loggingTimers.contains(timer.id) else { return }
        if status == .uncertain {
            do { try setLogStatus(entryExists ? .posted : nil, for: timer.id) }
            catch { errorMessage = error.localizedDescription; return }
        }
        errorMessage = nil
        if entryExists, timers.contains(where: { $0.id == timer.id }) {
            _ = await log(timer, seconds: max(60, elapsed(timer)), durationEdited: true,
                          description: timer.description, billable: timer.billable, markTaskComplete: false)
        }
    }

    func logAll(_ drafts: [(timer: TWTimer, seconds: TimeInterval, durationEdited: Bool, billable: Bool)]) async -> Set<Int> {
        let session = sessionID
        var logged: Set<Int> = []
        for draft in drafts {
            guard sessionID == session, !Task.isCancelled else { break }
            if await logTimer(draft.timer, seconds: draft.seconds, durationEdited: draft.durationEdited,
                              description: draft.timer.description, billable: draft.billable, markTaskComplete: false) {
                logged.insert(draft.timer.id)
            }
        }
        guard sessionID == session else { return [] }
        if !logged.isEmpty { logRevision += 1 }
        await refresh()
        await refreshToday()
        // Only when all went through: after a partial batch the form stays open with the error.
        if !drafts.isEmpty && logged.count == drafts.count {
            let total = drafts.reduce(0) { $0 + $1.seconds }.hoursMinutes
            showToast(drafts.count == 1 ? "Logged \(total) to \(title(of: drafts[0].timer))" : "Logged \(drafts.count) timers · \(total)")
        }
        return logged
    }

    /// Opens the main window with the Log All sheet (end-of-day notification).
    func showLogAll() {
        NSApp.activate()
        openMainWindow?()
        section = .timers
        showingLogAll = true
    }

    /// Moves a timer to another project/task and/or edits its notes; `seconds` sets its tracked time from now on.
    func edit(_ timer: TWTimer, target: WorkItem?, description: String, billable: Bool,
              seconds: TimeInterval? = nil) async -> Bool {
        let sent = Date.now
        let ok: Void? = await perform {
            try await $0.update(timer, target: target, description: description, billable: billable, seconds: seconds)
        }
        if ok != nil, let target { remember(target) }
        let fresh = await refresh()
        if ok != nil, let seconds {
            // Teamwork holds the new time, so the local adjustment goes. If the timer still reads otherwise (Teamwork
            // ignored `seconds`), the difference is kept locally until it's logged, like removed idle time.
            adjustments[timer.id] = nil
            if fresh, let current = timers.first(where: { $0.id == timer.id }) {
                let now = Date.now, roundTrip = now.timeIntervalSince(sent)
                let drift = current.elapsed(at: now) - seconds - (current.running ? roundTrip : 0)
                // A running timer reads up to a round trip short, give or take clock skew.
                if abs(drift) > roundTrip + 5 { adjustments[timer.id] = drift }
            }
            save(adjustments, "adjustments")
        }
        if ok != nil { showToast(target.map { "Timer moved to \($0.title)" } ?? "Timer updated") }
        return ok != nil
    }

    func updateEntry(_ entry: TimeEntry, seconds: TimeInterval, start: Date, description: String, billable: Bool) async -> Bool {
        let ok: Void? = await perform { try await $0.updateEntry(entry.id, seconds: seconds, start: start, description: description, billable: billable) }
        if ok != nil { logRevision += 1 }
        await refreshToday()
        if ok != nil { showToast("Entry updated") }
        return ok != nil
    }

    func deleteEntry(_ entry: TimeEntry) async {
        let ok: Void? = await perform { try await $0.deleteEntry(entry.id) }
        if ok != nil { logRevision += 1 }
        await refreshToday()
        if ok != nil { showToast("Entry deleted", symbol: "trash") }
    }

    /// The task a pasted or dropped Teamwork link points to.
    func item(fromLink text: String) async -> WorkItem? {
        guard let id = taskID(fromLink: text) else { return nil }
        return await perform { try await $0.task(id) } ?? nil
    }

    func refreshDueToday() async {
        if let tasks = await myTasks(.today) { dueToday = tasks }
    }

    func discard(_ timer: TWTimer) async {
        let ok: Void? = await perform { try await $0.delete(timer.id) }
        await refresh()
        if ok != nil { showToast("Timer discarded", symbol: "trash") }
    }

    /// Idle prompt outcome: sets the timer's time on Teamwork without the idle stretch, optionally pausing it.
    func removeIdle(from since: Date, to end: Date, timer: TWTimer, session: UUID, stop: Bool) async {
        guard sessionID == session, let current = timers.first(where: { $0.id == timer.id }) else { return }
        let shown = elapsed(current, at: end)
        let idle = min(current.trackedTime(from: since, to: end), shown)
        // A running timer kept counting while the prompt was up.
        let seconds = shown - idle + (current.running ? max(0, Date.now.timeIntervalSince(end)) : 0)
        let set = await edit(current, target: nil, description: current.description, billable: current.billable, seconds: seconds)
        guard sessionID == session else { return }
        if !set {
            // The request failed (offline or refused): keep it locally until it's logged, so the removal isn't lost.
            // ponytail: a request that timed out after Teamwork applied it removes the idle time twice; compare
            // against the refreshed time if that shows up.
            adjustments[timer.id, default: 0] += idle
            save(adjustments, "adjustments")
        }
        if stop, let current = timers.first(where: { $0.id == timer.id }), current.running { await toggle(current) }
    }

    // MARK: Projects, tasks, pins

    func search(_ query: String, in project: Project?) async -> [WorkItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return await perform { client in
            if let project {
                let tasks = try await client.tasks(matching: query, projectId: project.id, projectName: project.name)
                return query.isEmpty ? [WorkItem(project: project)] + tasks : tasks
            }
            guard !query.isEmpty else { return [] }
            async let projects = client.projects(matching: query)
            async let tasks = client.tasks(matching: query, projectId: nil, projectName: nil)
            return try await projects.map(WorkItem.init(project:)) + tasks
        } ?? []
    }

    func setStarred(_ project: Project, _ isStarred: Bool) async {
        await perform { try await $0.setStarred(project.id, isStarred) }
        await loadStarred()
    }

    func isPinned(_ item: WorkItem) -> Bool { pins.contains { $0.sameTarget(as: item) } }

    func togglePin(_ item: WorkItem) {
        if isPinned(item) { pins.removeAll { $0.sameTarget(as: item) } } else { pins.append(item) }
        save(pins, "pins")
    }

    func movePins(from source: IndexSet, to destination: Int) {
        pins.move(fromOffsets: source, toOffset: destination)
        save(pins, "pins")
    }

    func workItem(for timer: TWTimer) -> WorkItem? {
        guard let projectId = timer.projectId else { return nil }
        return WorkItem(projectId: projectId, projectName: projectName(projectId),
                        taskId: timer.taskId, taskName: timer.taskId.flatMap { taskNames[$0] },
                        description: timer.description, billable: timer.billable)
    }

    func projectName(_ id: Int) -> String { projectNames[id] ?? "Project \(id)" }
    func taskName(_ id: Int) -> String? { taskNames[id] }

    func title(of timer: TWTimer) -> String {
        timer.taskId.flatMap { taskNames[$0] } ?? timer.projectId.map(projectName)
            ?? (timer.description.isEmpty ? "Timer" : timer.description)
    }

    func subtitle(of timer: TWTimer) -> String? {
        timer.taskId == nil ? nil : timer.projectId.map(projectName)
    }

    /// Web link for a task, else its project.
    func webURL(projectId: Int?, taskId: Int?) -> URL? {
        guard let site else { return nil }
        if let taskId { return site.appending(path: "app/tasks/\(taskId)") }
        return projectId.map { site.appending(path: "app/projects/\($0)") }
    }

    private func remember(_ item: WorkItem) {
        if recents.first == item { return } // polling sees the same running timer every 15 s
        recents.removeAll { $0.sameTarget(as: item) }
        recents.insert(item, at: 0)
        recents = Array(recents.prefix(5))
        save(recents, "recents")
    }

    private func merge(_ included: Included) {
        for project in included.projects.values { projectNames[project.id] = project.name }
        for task in included.tasks.values { taskNames[task.id] = task.name }
    }

    // MARK: Helpers

    /// Shows a confirmation for 2 s (after the list has refreshed, so it lands with the change), replacing
    /// any earlier one, and reads it to VoiceOver.
    private func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        toast = Toast(message: message, symbol: symbol)
        AccessibilityNotification.Announcement(message).post()
        toastExpiry?.cancel()
        toastExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func dismissToast() {
        toastExpiry?.cancel()
        toast = nil
    }

    @discardableResult
    private func perform<T: Sendable>(_ work: @escaping @MainActor (TeamworkClient) async throws -> T) async -> T? {
        guard let client, !Task.isCancelled else { return nil }
        let id = UUID()
        let task = Task { try Task.checkCancellation(); return try await work(client) }
        requests[id] = { task.cancel() }
        defer { requests[id] = nil }
        do {
            let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard self.client === client, !Task.isCancelled else { return nil }
            return value
        } catch {
            if self.client === client, !Self.isCancellation(error), !Task.isCancelled { errorMessage = error.localizedDescription }
            return nil
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Runs a poll request; its failure message is remembered so the next successful poll can clear it.
    private func poll<T: Sendable>(_ work: @escaping @MainActor (TeamworkClient) async throws -> T) async -> T? {
        let before = errorMessage
        let result = await perform(work)
        if result == nil, errorMessage != before { pollError = errorMessage }
        return result
    }

    /// Values saved before keys were scoped per account: the first account to sign in adopts them, once.
    private func adoptLegacy<T: Codable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        save(value, key)
        return value
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let accountKey else { return nil }
        return defaults.data(forKey: "\(accountKey).\(key)").flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save(_ value: some Encodable, _ key: String) {
        guard let accountKey else { return }
        defaults.set(try? JSONEncoder().encode(value), forKey: "\(accountKey).\(key)")
    }
}
