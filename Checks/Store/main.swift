import Foundation

var failed = 0
@MainActor func check(_ ok: Bool, _ name: String) {
    if !ok { print("FAIL", name); failed += 1 }
}
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [MockProtocol.self]
TeamworkClient.session = URLSession(configuration: configuration)
let state = MockProtocol.state
let suite = "TeamworkTimerChecks.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
let directory = URL.temporaryDirectory.appending(path: suite)
defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
let store = Store(defaults: defaults, logDirectory: directory, polls: false)
try await store.signIn(site: "a.teamwork.com", token: "placeholder")
await store.refresh()
check(store.webURL(projectId: 1, taskId: 7)?.absoluteString == "https://tw.a.example/app/tasks/7", "links open on the account's own domain")
let first = store.timers.first { $0.id == 1 }!
let second = store.timers.first { $0.id == 2 }!
let drafts = [(timer: first, seconds: 900.0, durationEdited: true, billable: false), (timer: second, seconds: 900.0, durationEdited: true, billable: false)]
state.lock.withLock { state.mode = "partial"; state.calls = [] }
check(await store.logAll(drafts) == [1], "partial batch reports successful IDs")
check(store.toast == nil, "a partly failed batch shows no success toast")
check(await store.logAll(drafts) == [1, 2], "partial batch retry completes safely")
check(state.lock.withLock { state.posts[101] == 1 && state.posts[202] == 1 }, "batch retry never reposts successful timer")
check(store.errorMessage != nil, "refresh preserves failed write error")
try store.signOut()

state.lock.withLock { state.mode = "normal"; state.removed = []; state.posts = [:]; state.calls = [] }
try await store.signIn(site: "b.teamwork.com", token: "placeholder")
await store.refresh()
check(store.webURL(projectId: 1, taskId: 7)?.absoluteString == "https://b.teamwork.com/app/tasks/7", "without an account address, links open on the API site")
await store.loadWeek(containing: .now) // this week and last
state.lock.withLock { state.calls = [] }
check(await store.logAll(drafts) == [1, 2], "second account logs independently")
check(state.lock.withLock { state.calls.count == 5 }, "two direct logs use four writes and one shared read")
try store.signOut()

state.lock.withLock { state.removed = []; state.posts = [:]; state.delay = true }
try await store.signIn(site: "c.teamwork.com", token: "placeholder")
await store.refresh()
async let a = store.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
async let b = store.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
_ = await (a, b)
check(state.lock.withLock { state.posts[101] == 1 }, "concurrent logs only post once")
try store.signOut()

state.lock.withLock { state.removed = []; state.posts = [:]; state.delay = false; state.deleteFails = true }
try await store.signIn(site: "cleanup.teamwork.com", token: "placeholder")
await store.refresh()
check(await store.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false), "successful post survives cleanup failure")
try store.signOut()
state.lock.withLock { state.deleteFails = false }
try await store.signIn(site: "cleanup.teamwork.com", token: "placeholder")
await store.refresh()
await store.resolveLog(first, entryExists: false)
check(store.logAttempts[first.id] == .posted, "known success cannot be reset to allow another POST")
await store.resolveLog(first, entryExists: true)
check(!store.timers.contains(where: { $0.id == first.id }), "persisted receipt retries cleanup")
check(state.lock.withLock { state.posts[101] == 1 }, "cleanup after relaunch does not repost")
try store.signOut()

state.lock.withLock { state.removed = []; state.posts = [:]; state.mode = "uncertain" }
try await store.signIn(site: "uncertain.teamwork.com", token: "placeholder")
await store.refresh()
check(await !store.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false), "ambiguous failure does not claim success")
try store.signOut()
try await store.signIn(site: "uncertain.teamwork.com", token: "placeholder")
await store.refresh()
check(await !store.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false), "ambiguous post remains blocked after relaunch")
check(state.lock.withLock { state.posts[101] == 1 }, "ambiguous post is not repeated")
state.lock.withLock { state.mode = "normal" }
await store.resolveLog(first, entryExists: true)
check(state.lock.withLock { state.posts[101] == 1 && state.removed.contains(1) }, "confirmed entry only cleans up timer")
check(store.toast == nil, "removing a leftover timer is not reported as a new log")
try store.signOut()

state.lock.withLock { state.removed = []; state.posts = [:] }
try await store.signIn(site: "a.teamwork.com", token: "placeholder")
await store.refresh()
let pin = WorkItem(projectId: 101, projectName: "A private project", taskId: 5)
store.togglePin(pin)
let staleSession = store.sessionID
try store.signOut()
check(store.pins.isEmpty && store.recents.isEmpty && store.dueToday.isEmpty && store.adjustments.isEmpty, "logout clears account state")
try await store.signIn(site: "b.teamwork.com", token: "placeholder")
await store.refresh()
check(!store.pins.contains(pin), "pins are isolated by site")
let before = store.adjustments
state.lock.withLock { state.calls = [] }
await store.removeIdle(from: .distantPast, to: .now, timer: first, session: staleSession, stop: false)
check(store.adjustments == before && state.lock.withLock { !state.calls.contains { $0.contains("PUT") } },
      "stale idle prompt cannot alter new session")
try store.signOut()
try await store.signIn(site: "a.teamwork.com", token: "placeholder")
check(store.pins.contains(pin), "pins are restored for their own account")
state.lock.withLock { state.user = 2 }
try store.signOut()
try await store.signIn(site: "a.teamwork.com", token: "placeholder")
check(!store.pins.contains(pin), "pins are isolated by user on the same site")
state.lock.withLock { state.user = 1 }
try store.signOut()

try await store.signIn(site: "a.teamwork.com", token: "placeholder")
await store.refresh()
state.lock.withLock { state.mode = "late"; state.delayedStarted = false }
let oldRefresh = Task { await store.refresh() }
while !state.lock.withLock({ state.delayedStarted }) { try await Task.sleep(for: .milliseconds(5)) }
try store.signOut()
try await store.signIn(site: "new.teamwork.com", token: "placeholder")
_ = await oldRefresh.value
check(store.timers.allSatisfy { $0.id != 999 }, "late old-account refresh cannot overwrite session")
await store.start(WorkItem(projectId: 303, projectName: "Denied"))
check(store.errorMessage?.contains("403") == true, "failed write remains visible after successful refresh")
state.lock.withLock { state.calls = [] }
let fresh = WorkItem(projectId: 404, projectName: "New")
async let firstClick: Void = store.start(fresh)
async let secondClick: Void = store.start(fresh)
_ = await (firstClick, secondClick)
check(state.lock.withLock { state.calls.filter { $0.contains("POST") && $0.contains("/me/timers.json") }.count } == 1, "a double click creates one timer")
state.lock.withLock { state.removed = [] }
await store.refresh()
let paused = store.timers.first { !$0.running }!
state.lock.withLock { state.calls = [] }
await store.start(WorkItem(projectId: paused.projectId!, projectName: "Has a paused timer", taskId: paused.taskId))
check(state.lock.withLock { !state.calls.contains { $0.contains("POST") } && state.calls.contains { $0.contains("/resume.json") } },
      "starting work that already has a paused timer resumes it instead of creating another")
Keychain.failure = SignInError("Denied Keychain deletion")
do { try store.signOut(); check(false, "logout reports Keychain denial") } catch {}
check(store.isSignedIn, "failed credential deletion does not claim logout")
Keychain.failure = nil
try store.signOut()

state.lock.withLock { state.mode = "normal"; state.removed = []; state.posts = [:] }
try await store.signIn(site: "complete.teamwork.com", token: "placeholder")
await store.refresh()
check(await store.log(first, seconds: 600, durationEdited: false, description: "", billable: false, markTaskComplete: false), "unchanged timer uses native completion")
check(state.lock.withLock { state.posts.isEmpty && state.removed.contains(1) }, "native completion avoids direct timelog POST")
check(store.toast?.message.hasPrefix("Logged 0:10 to ") == true, "a successful log confirms with a toast")
try store.signOut()
Keychain.failure = SignInError("Denied Keychain save")
do { try await store.signIn(site: "denied.teamwork.com", token: "placeholder"); check(false, "sign-in reports Keychain save failure") } catch {}
check(!store.isSignedIn, "sign-in does not activate unsaved credentials")
Keychain.failure = nil
let blockedPath = directory.appending(path: "regular-file")
try Data().write(to: blockedPath)
let blockedStore = Store(defaults: defaults, logDirectory: blockedPath, polls: false)
try await blockedStore.signIn(site: "disk.teamwork.com", token: "placeholder")
await blockedStore.refresh()
state.lock.withLock { state.posts = [:]; state.removed = [] }
await blockedStore.refresh()
check(await !blockedStore.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false), "receipt write failure blocks logging")
check(state.lock.withLock { state.posts.isEmpty }, "no POST before durable attempt is written")
try blockedStore.signOut()

// A project no mock timer uses: remembering a running timer replaces a recent for the same project, which
// made this flaky when a background refresh remembered timer 1 (project 101) right after sign-in.
let legacyRecent = WorkItem(projectId: 909, projectName: "Legacy")
defaults.set(try JSONEncoder().encode([legacyRecent]), forKey: "recents")
state.lock.withLock { state.mode = "normal"; state.removed = []; state.posts = [:]; state.deleteFails = false }
try await store.signIn(site: "upgrade.teamwork.com", token: "placeholder")
check(store.recents.contains(legacyRecent) && defaults.data(forKey: "recents") == nil, "recents saved before per-account keys are adopted once")
state.lock.withLock { state.mode = "offline-once" }
await store.refresh()
check(store.errorMessage != nil, "a failed poll shows its error")
await store.refresh()
check(store.errorMessage == nil, "the next successful poll clears a poll error")
let long = store.timers.first { $0.id == 1 }!
check(await store.log(long, seconds: 90_000, durationEdited: false, description: "", billable: false, markTaskComplete: false),
      "an unedited timer over 24 hours logs through native completion")
try store.signOut()

state.lock.withLock { state.removed = []; state.posts = [:]; state.deleteFails = true }
try await store.signIn(site: "cleanup2.teamwork.com", token: "placeholder")
await store.refresh()
_ = await store.log(store.timers.first { $0.id == 1 }!, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
state.lock.withLock { state.deleteFails = false }
await store.refresh()
check(!store.timers.contains { $0.id == 1 } && state.lock.withLock { state.posts[101] == 1 },
      "a logged timer whose removal failed is removed by the next poll, without reposting")
try store.signOut()

// Logging work without a timer: one POST to the task, nothing sent to timers, even on a double click.
state.lock.withLock { state.removed = []; state.posts = [:]; state.deleteFails = false; state.delay = true; state.body = nil }
try await store.signIn(site: "direct.teamwork.com", token: "placeholder")
await store.refresh()
await store.loadWeek(containing: .now) // this week and last
state.lock.withLock { state.calls = [] }
let work = WorkItem(projectId: 101, projectName: "Website", taskId: 7, taskName: "Write the spec")
let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
let revision = store.logRevision
async let logClick = store.log(work, seconds: 4500, on: yesterday, description: "Notes", billable: true, markTaskComplete: true)
async let logAgain = store.log(work, seconds: 4500, on: yesterday, description: "Notes", billable: true, markTaskComplete: true)
let logged = await [logClick, logAgain]
let (calls, body) = state.lock.withLock { (state.calls, state.body) }
check(logged.filter { $0 }.count == 1 && calls.filter { $0.contains("POST") }.count == 1, "a double click on Log posts one entry")
check(calls.contains { $0.contains("POST /projects/api/v3/tasks/7/time.json") }, "a task's time posts to that task")
check(!calls.contains { $0.contains("/timers") }, "logging work without a timer makes no timer call")
let timelog = body?["timelog"] as? [String: Any]
let logStart = timelog.flatMap { ISO8601DateFormatter().date(from: "\($0["date"] ?? "")T\($0["time"] ?? "")Z") }
check(timelog?["hours"] as? Int == 1 && timelog?["minutes"] as? Int == 15 && timelog?["description"] as? String == "Notes"
      && timelog?["isBillable"] as? Bool == true && (body?["timelogOptions"] as? [String: Bool])?["markTaskComplete"] == true,
      "the entry carries duration, notes, billable and mark complete")
check(logStart.map { Calendar.current.isDate($0, inSameDayAs: yesterday) } == true, "the entry lands on the chosen day")
check(store.logRevision == revision + 1 && store.recents.first?.sameTarget(as: work) == true
      && store.toast?.message == "Logged 1:15 to Write the spec", "a direct log reloads lists, joins Recents and confirms")
check(await !store.log(work, seconds: 30, on: .now, description: "", billable: false, markTaskComplete: false)
      && state.lock.withLock { state.posts[7] == 1 }, "under a minute is refused before posting")
state.lock.withLock { state.delay = false }
try store.signOut()

// Editing a timer's time: Teamwork takes `seconds` and a running timer carries on from it; when a server ignores it,
// Stint keeps the difference. Either way the time shown and logged is the new one, and idle removal still applies.
let timer = { (id: Int) in store.timers.first { $0.id == id }! }
let near = { (a: TimeInterval, b: TimeInterval) in abs(a - b) < 2 }
let postedMinutes = { state.lock.withLock { (state.body?["timelog"] as? [String: Any]).map { ($0["hours"] as! Int) * 60 + ($0["minutes"] as! Int) } } }
for mode in ["normal", "ignore-seconds"] {
    state.lock.withLock { // timer 1 paused at 0:10, timer 2 running at 4:57
        state.mode = mode; state.removed = []; state.posts = [:]; state.body = nil
        state.durations = [:]; state.running = [2: .now.addingTimeInterval(-17_820)]
    }
    try await store.signIn(site: "\(mode).teamwork.com", token: "placeholder")
    await store.refresh()
    for seconds in [900.0, 300.0] { // later, then earlier
        check(await store.edit(timer(1), target: nil, description: "", billable: false, seconds: seconds)
              && store.elapsed(timer(1)) == seconds, "\(mode): a timer is set to exactly \(seconds.hoursMinutes)")
        await store.refresh()
        check(store.elapsed(timer(1)) == seconds, "\(mode): an edited time survives a refresh")
    }
    state.lock.withLock { state.calls = [] }
    check(await store.edit(timer(2), target: nil, description: "", billable: false, seconds: 18_900)
          && near(store.elapsed(timer(2)), 18_900) && near(store.elapsed(timer(2), at: .now + 60), 18_960),
          "\(mode): a running 4:57 set to 5:15 carries on from 5:15")
    check(state.lock.withLock { state.calls.filter { $0.contains(" PUT ") }.map { $0.split(separator: "/").last! } }
          == ["pause.json?page=1", "2.json?page=1", "resume.json?page=1"], "\(mode): a running timer is paused, set, then resumed")
    check((store.adjustments[2] == nil) == (mode == "normal"), "\(mode): Teamwork keeps the new time, else Stint does")
    await store.removeIdle(from: .now.addingTimeInterval(-120), to: .now, timer: timer(2), session: store.sessionID, stop: false)
    let shown = store.elapsed(timer(2))
    check(near(shown, 18_780), "\(mode): idle removal applies on top of an edited time")
    check((store.adjustments[2] == nil) == (mode == "normal"), "\(mode): Teamwork holds the time without the idle stretch, else Stint does")
    check(await store.log(timer(2), seconds: shown, durationEdited: false, description: "", billable: false, markTaskComplete: false)
          && (mode == "normal" ? postedMinutes() == nil && state.lock.withLock { state.removed.contains(2) } : postedMinutes() == Int(shown) / 60),
          "\(mode): the log posts the time shown (Teamwork completes its own timer when it holds the time)")
    state.lock.withLock { state.body = nil }
    _ = await store.log(timer(1), seconds: store.elapsed(timer(1)), durationEdited: false, description: "", billable: false, markTaskComplete: false)
    check(mode == "normal" ? postedMinutes() == nil && state.lock.withLock { state.removed.contains(1) } : postedMinutes() == 5,
          "\(mode): an edited paused timer logs 0:05 (Teamwork completes its own timer when it holds the time)")
    try store.signOut()
}
// Idle removal Teamwork can't take is kept locally, and "Remove and Stop" still pauses.
state.lock.withLock { state.mode = "put-fails"; state.removed = []; state.durations = [:]; state.running = [2: .now.addingTimeInterval(-3600)] }
try await store.signIn(site: "idle.teamwork.com", token: "placeholder")
await store.refresh()
state.lock.withLock { state.calls = [] }
await store.removeIdle(from: .now.addingTimeInterval(-600), to: .now, timer: timer(2), session: store.sessionID, stop: true)
check(near(store.adjustments[2]?.seconds ?? 0, 600) && near(store.elapsed(timer(2)), 3000), "a failed idle write keeps the removal locally")
check(state.lock.withLock { state.calls.filter { $0.contains(" PUT ") }.map { $0.split(separator: "/").last! } }
      == ["pause.json?page=1", "2.json?page=1", "resume.json?page=1", "pause.json?page=1"] && !timer(2).running,
      "a refused edit resumes the timer, and Remove and Stop pauses it")
try store.signOut()
state.lock.withLock { state.mode = "normal"; state.running = [:]; state.durations = [:] }

// Time changed in Teamwork's web app (which pauses a running timer, then sends `seconds`) shows at the next refresh
// (each poll, and when the popover opens), running or paused. An adjustment holds while Teamwork's time only runs on
// or pauses, and gives way once that time is changed elsewhere.
let teamwork = { (id: Int, seconds: Int, running: Bool) in
    state.lock.withLock {
        if running { state.running[id] = .now.addingTimeInterval(-Double(seconds)) } else { state.running[id] = nil; state.durations[id] = seconds }
    }
}
state.lock.withLock { state.removed = []; state.running = [2: .now.addingTimeInterval(-3600)] }
try await store.signIn(site: "web.teamwork.com", token: "placeholder")
await store.refresh()
teamwork(1, 1500, false)
await store.refresh()
check(store.elapsed(timer(1)) == 1500, "a paused timer's time changed on the web shows at the next refresh")
teamwork(2, 7200, true)
await store.refresh()
check(near(store.elapsed(timer(2)), 7200), "a running timer's time changed elsewhere shows at the next refresh")
teamwork(2, 2700, false)
await store.refresh()
check(!timer(2).running && store.elapsed(timer(2)) == 2700, "the web app's edit of a running timer (paused, then set) shows")
state.lock.withLock { state.mode = "ignore-seconds" }
check(await store.edit(timer(1), target: nil, description: "", billable: false, seconds: 900)
      && store.adjustments[1] != nil && store.elapsed(timer(1)) == 900, "an edit Teamwork ignores is kept as an adjustment")
teamwork(1, 2400, false)
await store.refresh()
check(store.adjustments[1] == nil && store.elapsed(timer(1)) == 2400, "a paused timer's web edit replaces its adjustment")
state.lock.withLock { state.mode = "put-fails" }
teamwork(2, 3600, true)
await store.refresh()
await store.removeIdle(from: .now.addingTimeInterval(-600), to: .now, timer: timer(2), session: store.sessionID, stop: false)
state.lock.withLock { state.mode = "normal" }
await store.refresh()
check(store.adjustments[2] != nil && near(store.elapsed(timer(2)), 3000), "an adjustment holds while Teamwork's time runs on")
teamwork(2, Int(timer(2).elapsed()), false)
await store.refresh()
check(store.adjustments[2] != nil && near(store.elapsed(timer(2)), 3000), "an adjustment holds when the timer is paused")
teamwork(2, 1200, false)
await store.refresh()
check(store.adjustments[2] == nil && store.elapsed(timer(2)) == 1200, "a running timer's web edit replaces its adjustment")
try store.signOut()
state.lock.withLock { state.mode = "normal"; state.running = [:]; state.durations = [:] }

// Pause shows at once, before Teamwork answers, and a refresh that read Teamwork before the pause doesn't undo it.
state.lock.withLock { state.mode = "slow"; state.removed = []; state.running = [2: .now.addingTimeInterval(-3600)] }
try await store.signIn(site: "toggle.teamwork.com", token: "placeholder")
await store.refresh()
let stale = Task { await store.refresh() } // reads timer 2 still running
try await Task.sleep(for: .milliseconds(50))
let pausing = Task { await store.toggle(timer(2)) }
try await Task.sleep(for: .milliseconds(50))
check(store.runningTimer == nil, "a pause shows before Teamwork answers")
_ = await stale.value
check(store.runningTimer == nil, "a refresh that read Teamwork before the pause doesn't undo it")
await pausing.value
check(store.runningTimer == nil && state.lock.withLock { state.running[2] == nil }, "the pause lands")
try store.signOut()
state.lock.withLock { state.mode = "normal"; state.running = [:]; state.durations = [:] }

// A start shows at once too, pausing the running timer, and a refresh that read Teamwork before it doesn't undo it.
state.lock.withLock { state.mode = "slow"; state.removed = []; state.running = [2: .now.addingTimeInterval(-3600)] }
try await store.signIn(site: "start.teamwork.com", token: "placeholder")
await store.refresh()
let staleList = Task { await store.refresh() } // reads timer 2 running, and no new timer
try await Task.sleep(for: .milliseconds(50))
let starting = Task { await store.start(WorkItem(projectId: 505, projectName: "New work")) }
try await Task.sleep(for: .milliseconds(50))
let startedAlone = { store.runningTimer.map { store.title(of: $0) } == "New work" && store.timers.filter(\.running).count == 1 }
check(startedAlone(), "a start shows before Teamwork answers, and the running timer pauses")
_ = await staleList.value
check(startedAlone(), "a refresh that read Teamwork before the start doesn't undo it")
await starting.value
check(startedAlone() && store.runningTimer?.id == 3 && state.lock.withLock { state.running.keys.sorted() == [3] }, "the start lands")
try store.signOut()
state.lock.withLock { state.mode = "normal"; state.running = [:]; state.durations = [:]; state.created = nil }

// Targets: Teamwork's working hours from sign-in; a custom day applies at once and is remembered.
let day = { (number: Int) in Calendar.current.dateInterval(of: .day, for: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: number))!)! }
try await store.signIn(site: "hours.teamwork.com", token: "placeholder")
check(store.target(in: day(15)) == 27_000 && store.target(in: day(16)) == 21_600 && store.target(in: day(14)) == nil,
      "Teamwork's working hours set each day's target")
store.customDayLength = 27_000
check(store.target(in: day(16)) == 27_000 && store.target(in: day(14)) == nil, "a custom day applies at once, on working days only")
try store.signOut()
check(store.target(in: day(16)) == 27_000 && store.target(in: day(17)) == nil, "the custom day outlives sign-out, Monday–Friday")
check(Store(defaults: defaults, logDirectory: directory, polls: false).customDayLength == 27_000, "the custom day is remembered")
store.customDayLength = nil
check(store.target(in: day(16)) == nil && defaults.object(forKey: "customDayLength") == nil, "no target signed out without a custom day")

// "No timer running" stays quiet once today's logged time (fetched, so the web's counts) plus the timers' meets
// the target; below it, or on a day without one, it reminds as before.
state.lock.withLock { state.removed = []; state.loggedMinutes = 430 }
try await store.signIn(site: "filled.teamwork.com", token: "placeholder")
await store.refresh() // two paused timers, 0:10 each
let tenAM = { (number: Int) in day(number).start.addingTimeInterval(10 * 3600) }
check(await store.filledToday(at: tenAM(15)), "7:10 logged and 0:20 on timers fill a 7:30 day: no reminder")
state.lock.withLock { state.loggedMinutes = 420 }
check(await !store.filledToday(at: tenAM(15)), "below the target: the reminder comes")
state.lock.withLock { state.loggedMinutes = 600 }
check(await !store.filledToday(at: tenAM(14)), "a day without a target: the reminder comes as before")
try store.signOut()
state.lock.withLock { state.loggedMinutes = 0 }

// Rate limiting (429): Teamwork refused the request unprocessed, so it's sent again after Retry-After (else 60 s),
// up to 3 times, with a calm status meanwhile. A log's receipt still guards against any other failure.
let sent = { (method: String) in state.lock.withLock { state.calls.filter { $0.contains("\(method) ") }.count } }
state.lock.withLock { state.mode = "normal"; state.removed = []; state.posts = [:]; state.durations = [:]; state.running = [:] }
try await store.signIn(site: "limited.teamwork.com", token: "placeholder")
await store.refresh()
await store.loadWeek(containing: .now) // this week and last, before the 429 is armed
state.lock.withLock { state.limited = 1; state.retryAfter = "0"; state.calls = [] }
check(await store.log(timer(1), seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
      && sent("POST") == 2 && state.lock.withLock { state.posts[101] == 1 } && store.errorMessage == nil,
      "a rate-limited time entry is sent again and logged once, with no error")
state.lock.withLock { state.limited = 4; state.calls = [] }
check(await !store.log(timer(2), seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
      && sent("POST") == 4 && store.errorMessage?.contains("429") == true, "a request still refused after 3 retries fails")
check(store.logAttempts[2] == nil && state.lock.withLock { state.posts[202] == nil }, "a refused log leaves no receipt, so it can be retried")
check(await store.log(timer(2), seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false)
      && state.lock.withLock { state.posts[202] == 1 }, "the retry logs once")
state.lock.withLock { state.limited = 1; state.retryAfter = "1"; state.calls = [] }
store.errorMessage = nil
let held = Task { await store.refresh() }
try await Task.sleep(for: .milliseconds(400))
check(store.rateLimited && store.errorMessage == nil && sent("GET") == 1, "Retry-After is honoured with a status, not an error")
check(await held.value && !store.rateLimited && store.errorMessage == nil, "the status clears once the request goes through")
state.lock.withLock { state.limited = 1; state.retryAfter = nil; state.calls = [] }
let stuck = Task { await store.refresh() }
try await Task.sleep(for: .milliseconds(500))
check(store.rateLimited && sent("GET") == 1, "without Retry-After the wait is longer (60 s)")
try store.signOut()
check(await !stuck.value && !store.rateLimited && store.errorMessage == nil, "sign-out ends the wait quietly")

state.lock.withLock { state.mode = "pagination" }
let client = TeamworkClient(credentials: Credentials(kind: .apiToken, site: URL(string: "https://page.teamwork.com/")!, secret: "placeholder"))
let entries = try await client.timeEntries(userId: 1, from: .now, to: .now)
check(entries.timelogs.count == 2 && entries.included.projects.count == 2, "pagination merges rows and included records")
check(try await client.myTasks(userId: 1, filter: .today).count == 2, "task pagination")
check(try await client.starredProjects().count == 2, "starred project pagination")
check(try await client.tasks(matching: "t", projectId: nil, projectName: nil).count == 1, "global task search reads one page")
check(try await client.tasks(matching: "", projectId: 101, projectName: "P").count == 2, "a project's task list reads every page")
state.lock.withLock { state.mode = "empty-page" }
check(try await client.timeEntries(userId: 1, from: .now, to: .now).timelogs.count == 1, "an empty page ends the list")
state.lock.withLock { state.mode = "pagination"; state.limited = 1; state.retryAfter = "0"; state.calls = [] }
check(try await client.timeEntries(userId: 1, from: .now, to: .now).timelogs.count == 2 && sent("GET") == 3,
      "a rate-limited page is fetched again and the list completes")
state.lock.withLock { state.mode = "normal"; state.limited = 1; state.retryAfter = "1" }
let begun = Date.now
async let refused = client.starredProjects()
try await Task.sleep(for: .milliseconds(200))
_ = try await client.projects(matching: "x")
check(Date.now.timeIntervalSince(begun) > 0.9, "after a 429 every request waits, not only the refused one")
_ = try await refused
try await client.updateEntry(5, seconds: 1800, start: .now, description: "", billable: false,
                             target: WorkItem(projectId: 202, projectName: "Other"))
let moved = state.lock.withLock { state.body?["timelog"] as? [String: Any] }
check(moved?["projectId"] as? Int == 202 && moved?["taskId"] is NSNull && moved?["minutes"] as? Int == 30,
      "moving an entry to a project sends the project and clears the task")
print(failed == 0 ? "All store and transport checks passed." : "\(failed) store check(s) failed.")
exit(failed == 0 ? 0 : 1)
