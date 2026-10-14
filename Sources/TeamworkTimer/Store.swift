import AppKit
import Observation
import SwiftUI // IndexSet-based `move(fromOffsets:toOffset:)`

/// App state. Teamwork is the source of truth for timers and time entries; pins, recents and idle
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
    /// Seconds removed from a running timer (idle time), applied when it's logged.
    // ponytail: local until logged; the web app shows the full time meanwhile. Upgrade if Teamwork adds a duration edit.
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
    /// Your working day from Teamwork (`lengthOfDay`), in seconds; nil if not set.
    private(set) var dayTarget: TimeInterval?
    /// Tasks assigned to you and due today, for the popover.
    private(set) var dueToday: [WorkItem] = []
    /// Opens the main window from places without a SwiftUI environment (notification actions).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    var errorMessage: String?

    private var projectNames: [Int: String] = [:]
    private var taskNames: [Int: String] = [:]
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored let reminders = Reminders()
    @ObservationIgnored private var idle: IdleMonitor?

    var isSignedIn: Bool { client != nil }
    var activeTimer: TWTimer? { timers.first(where: \.running) ?? timers.first }
    var runningTimer: TWTimer? { timers.first(where: \.running) }

    init() {
        pins = Self.load("pins") ?? []
        recents = Self.load("recents") ?? []
        adjustments = Self.load("adjustments") ?? [:]
        reminders.store = self
        idle = IdleMonitor(store: self)
        if let data = Keychain.get("credentials"), let credentials = try? JSONDecoder().decode(Credentials.self, from: data) {
            activate(credentials)
            Task {
                if let me = try? await client?.me() { (userId, accountName, dayTarget) = (me.id, me.name, me.dayLength) }
                await loadStarred()
            }
        }
        // Timers started elsewhere keep running while the Mac sleeps; catch up on wake.
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
        guard let redirect = URL(string: redirect), redirect.port != nil else {
            throw SignInError("Enter a redirect URI with a port, e.g. http://localhost:8123")
        }
        async let code = LoopbackServer.waitForCode(on: redirect)
        NSWorkspace.shared.open(Launchpad.loginURL(clientID: clientID, redirect: redirect))
        let credentials = try await Launchpad.exchange(code: try await code, clientID: clientID, clientSecret: clientSecret, redirect: redirect)
        Keychain.set(Data(clientSecret.utf8), for: "oauthClientSecret")
        NSApp.activate()
        try await connect(credentials)
    }

    static var savedOAuthSecret: String? { Keychain.get("oauthClientSecret").map { String(decoding: $0, as: UTF8.self) } }

    func signOut() {
        poller?.cancel()
        Keychain.set(nil, for: "credentials")
        client = nil
        site = nil
        accountName = nil
        userId = nil
        timers = []
        starred = []
        weeks = [:]
        loggedToday = 0
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
        let me = try await TeamworkClient(credentials: credentials).me()
        (userId, accountName, dayTarget) = (me.id, me.name, me.dayLength)
        Keychain.set(try JSONEncoder().encode(credentials), for: "credentials")
        activate(credentials)
        await loadStarred()
        // Ask now, in context, rather than when the first 8-hour alert would fire.
        if Reminders.longTimerAlert { await Reminders.requestPermission() }
    }

    private func activate(_ credentials: Credentials) {
        client = TeamworkClient(credentials: credentials)
        site = credentials.site
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // This week is ready before the popover first opens (retried until it loads).
                if self?.weeks.isEmpty == true { await self?.loadWeek(containing: .now) }
                self?.reminders.check()
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
            }
        }
    }

    // MARK: Sync

    func refresh() async {
        await perform { client in
            // Retried every poll until it works (e.g. "Open at login" before the network is up).
            if userId == nil {
                let me = try await client.me()
                (userId, accountName, dayTarget) = (me.id, me.name, me.dayLength)
            }
            let page = try await client.timers()
            merge(page.included)
            // Running first, then most recently used, so "resume last" means the last one you used.
            timers = page.timers.sorted { ($0.running ? 1 : 0, $0.lastActive) > ($1.running ? 1 : 0, $1.lastActive) }
            updateTicker()
            // A timer started on the web becomes a recent too.
            if let running = runningTimer, let item = workItem(for: running) { remember(item) }
            // Forget adjustments for timers that are gone (logged or deleted elsewhere).
            let live = Set(timers.map(\.id))
            if adjustments.keys.contains(where: { !live.contains($0) }) {
                adjustments = adjustments.filter { live.contains($0.key) }
                Self.save(adjustments, "adjustments")
            }
            errorMessage = nil
        }
    }

    func loadStarred() async {
        await perform { starred = try await $0.starredProjects() }
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
        guard let userId else { return nil }
        var entries: [TimeEntry]?
        await perform { client in
            let page = try await client.timeEntries(userId: userId, from: from, to: to)
            merge(page.included)
            entries = page.timelogs
        }
        return entries
    }

    /// nil when Teamwork couldn't be reached, so callers keep what they had.
    func myTasks(_ filter: TeamworkClient.TaskFilter) async -> [WorkItem]? {
        guard let userId else { return nil }
        var items: [WorkItem]?
        await perform { items = try await $0.myTasks(userId: userId, filter: filter) }
        return items
    }

    // MARK: Timer actions

    func start(_ item: WorkItem) async {
        if await perform({ try await $0.startTimer(item) }) { remember(item) }
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

    /// Time shown and logged for a timer: server time minus removed idle time.
    func elapsed(_ timer: TWTimer, at now: Date = .now) -> TimeInterval {
        max(0, timer.elapsed(at: now) - (adjustments[timer.id] ?? 0))
    }


    /// Logs the timer. Teamwork's own "complete" is used when nothing was changed; an edited duration,
    /// removed idle time or "mark task complete" logs the entry directly and then deletes the timer.
    /// Returns false if Teamwork refused.
    func log(_ timer: TWTimer, seconds: TimeInterval, durationEdited: Bool, description: String, billable: Bool,
             markTaskComplete: Bool) async -> Bool {
        let direct = durationEdited || markTaskComplete || adjustments[timer.id] != nil
        var logged = false
        var cleanupError: String?
        await perform { client in
            if !direct {
                if description != timer.description || billable != timer.billable {
                    try await client.update(timer, description: description, billable: billable)
                }
                try await client.complete(timer.id)
                logged = true
            } else {
                guard let projectId = timer.projectId else { throw SignInError("This timer has no project to log against.") }
                try await client.logTime(projectId: projectId, taskId: timer.taskId, seconds: seconds,
                                         start: timer.startedAt ?? .now.addingTimeInterval(-seconds),
                                         description: description, billable: billable, markTaskComplete: markTaskComplete)
                // The entry exists now; never report failure past this point, or a retry would log it twice.
                logged = true
                do { try await client.delete(timer.id) } catch {
                    cleanupError = "Logged, but the timer couldn't be removed. Discard it manually. (\(error.localizedDescription))"
                }
            }
        }
        if logged { logRevision += 1 }
        await refresh()
        await refreshToday()
        if let cleanupError { errorMessage = cleanupError } // after refresh, which clears errors
        return logged
    }

    /// Logs several timers one after another; returns how many were logged.
    func logAll(_ drafts: [(timer: TWTimer, seconds: TimeInterval, durationEdited: Bool, billable: Bool)]) async -> Int {
        var logged = 0
        for draft in drafts where await log(draft.timer, seconds: draft.seconds, durationEdited: draft.durationEdited,
                                            description: draft.timer.description, billable: draft.billable,
                                            markTaskComplete: false) {
            logged += 1
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

    /// Moves a timer to another project/task and/or edits its notes; the tracked time stays.
    func edit(_ timer: TWTimer, target: WorkItem?, description: String, billable: Bool) async -> Bool {
        let ok = await perform { try await $0.update(timer, target: target, description: description, billable: billable) }
        if ok, let target { remember(target) }
        await refresh()
        return ok
    }

    func updateEntry(_ entry: TimeEntry, seconds: TimeInterval, start: Date, description: String, billable: Bool) async -> Bool {
        let ok = await perform { try await $0.updateEntry(entry.id, seconds: seconds, start: start, description: description, billable: billable) }
        if ok { logRevision += 1 }
        await refreshToday()
        return ok
    }

    func deleteEntry(_ entry: TimeEntry) async {
        if await perform({ try await $0.deleteEntry(entry.id) }) { logRevision += 1 }
        await refreshToday()
    }

    /// The task a pasted or dropped Teamwork link points to.
    func item(fromLink text: String) async -> WorkItem? {
        guard let id = taskID(fromLink: text) else { return nil }
        var item: WorkItem?
        await perform { item = try await $0.task(id) }
        return item
    }

    func refreshDueToday() async {
        if let tasks = await myTasks(.today) { dueToday = tasks }
    }

    func discard(_ timer: TWTimer) async {
        await perform { try await $0.delete(timer.id) }
        await refresh()
    }

    /// Idle prompt outcome: drop `seconds` from the timer, optionally pausing it.
    func removeIdle(_ seconds: TimeInterval, from timer: TWTimer, stop: Bool) async {
        adjustments[timer.id, default: 0] += seconds
        Self.save(adjustments, "adjustments")
        if stop && timer.running { await toggle(timer) }
    }

    // MARK: Projects, tasks, pins

    func search(_ query: String, in project: Project?) async -> [WorkItem] {
        guard let client else { return [] }
        let query = query.trimmingCharacters(in: .whitespaces)
        do {
            if let project {
                let tasks = try await client.tasks(matching: query, projectId: project.id, projectName: project.name)
                return query.isEmpty ? [WorkItem(project: project)] + tasks : tasks
            }
            guard !query.isEmpty else { return [] }
            async let projects = client.projects(matching: query)
            async let tasks = client.tasks(matching: query, projectId: nil, projectName: nil)
            return try await projects.map(WorkItem.init(project:)) + tasks
        } catch {
            if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
            return []
        }
    }

    func setStarred(_ project: Project, _ isStarred: Bool) async {
        await perform { try await $0.setStarred(project.id, isStarred) }
        await loadStarred()
    }

    func isPinned(_ item: WorkItem) -> Bool { pins.contains { $0.sameTarget(as: item) } }

    func togglePin(_ item: WorkItem) {
        if isPinned(item) { pins.removeAll { $0.sameTarget(as: item) } } else { pins.append(item) }
        Self.save(pins, "pins")
    }

    func movePins(from source: IndexSet, to destination: Int) {
        pins.move(fromOffsets: source, toOffset: destination)
        Self.save(pins, "pins")
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
        Self.save(recents, "recents")
    }

    private func merge(_ included: Included) {
        for project in included.projects.values { projectNames[project.id] = project.name }
        for task in included.tasks.values { taskNames[task.id] = task.name }
    }

    // MARK: Helpers

    /// Runs `work`, surfacing errors in `errorMessage`. Returns whether it succeeded.
    @discardableResult
    private func perform(_ work: (TeamworkClient) async throws -> Void) async -> Bool {
        guard let client else { return false }
        do {
            try await work(client)
            return true
        } catch {
            if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
            return false
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func save(_ value: some Encodable, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
