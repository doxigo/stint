import Foundation

var failed = 0
@MainActor func check(_ ok: Bool, _ name: String) {
    if !ok { print("FAIL", name); failed += 1 }
}
URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
URLProtocol.registerClass(MockProtocol.self)
let state = MockProtocol.state
let suite = "TeamworkTimerChecks.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
let directory = URL.temporaryDirectory.appending(path: suite)
defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
let store = Store(defaults: defaults, logDirectory: directory)
try await store.signIn(site: "a.teamwork.com", token: "placeholder")
await store.refresh()
let first = store.timers.first { $0.id == 1 }!
let second = store.timers.first { $0.id == 2 }!
let drafts = [(timer: first, seconds: 900.0, durationEdited: true, billable: false), (timer: second, seconds: 900.0, durationEdited: true, billable: false)]
state.lock.withLock { state.mode = "partial"; state.calls = [] }
check(await store.logAll(drafts) == [1], "partial batch reports successful IDs")
check(await store.logAll(drafts) == [1, 2], "partial batch retry completes safely")
check(state.lock.withLock { state.posts[101] == 1 && state.posts[202] == 1 }, "batch retry never reposts successful timer")
check(store.errorMessage != nil, "refresh preserves failed write error")
try store.signOut()

state.lock.withLock { state.mode = "normal"; state.removed = []; state.posts = [:]; state.calls = [] }
try await store.signIn(site: "b.teamwork.com", token: "placeholder")
await store.refresh()
while store.weeks.count < 2 { try await Task.sleep(for: .milliseconds(2)) }
state.lock.withLock { state.calls = [] }
check(await store.logAll(drafts) == [1, 2], "second account logs independently")
check(state.lock.withLock { state.calls.count == 6 }, "two direct logs use four writes and two shared reads")
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
await store.removeIdle(from: .distantPast, to: .now, timer: first, session: staleSession, stop: false)
check(store.adjustments == before, "stale idle prompt cannot alter new session")
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
await oldRefresh.value
check(store.timers.allSatisfy { $0.id != 999 }, "late old-account refresh cannot overwrite session")
await store.start(WorkItem(projectId: 101, projectName: "Denied"))
check(store.errorMessage?.contains("403") == true, "failed write remains visible after successful refresh")
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
try store.signOut()
Keychain.failure = SignInError("Denied Keychain save")
do { try await store.signIn(site: "denied.teamwork.com", token: "placeholder"); check(false, "sign-in reports Keychain save failure") } catch {}
check(!store.isSignedIn, "sign-in does not activate unsaved credentials")
Keychain.failure = nil
let blockedPath = directory.appending(path: "regular-file")
try Data().write(to: blockedPath)
let blockedStore = Store(defaults: defaults, logDirectory: blockedPath)
try await blockedStore.signIn(site: "disk.teamwork.com", token: "placeholder")
await blockedStore.refresh()
state.lock.withLock { state.posts = [:]; state.removed = [] }
await blockedStore.refresh()
check(await !blockedStore.log(first, seconds: 900, durationEdited: true, description: "", billable: false, markTaskComplete: false), "receipt write failure blocks logging")
check(state.lock.withLock { state.posts.isEmpty }, "no POST before durable attempt is written")
try blockedStore.signOut()

state.lock.withLock { state.mode = "pagination" }
let client = TeamworkClient(credentials: Credentials(kind: .apiToken, site: URL(string: "https://page.teamwork.com/")!, secret: "placeholder"))
let entries = try await client.timeEntries(userId: 1, from: .now, to: .now)
check(entries.timelogs.count == 2 && entries.included.projects.count == 2, "pagination merges rows and included records")
check(try await client.myTasks(userId: 1, filter: .today).count == 2, "task pagination")
check(try await client.starredProjects().count == 2, "starred project pagination")
state.lock.withLock { state.mode = "empty-page" }
do { _ = try await client.timeEntries(userId: 1, from: .now, to: .now); check(false, "pagination rejects unexpected empty page") } catch {}
print(failed == 0 ? "All store and transport checks passed." : "\(failed) store check(s) failed.")
exit(failed == 0 ? 0 : 1)
