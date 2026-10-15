// Assert-based checks for the non-UI code. Run with ./check.sh (works without Xcode).
// Fixtures are real v3 responses (anonymized), fetched read-only.
import Foundation

var failed = 0
@MainActor func check(_ ok: Bool, _ name: String) {
    if !ok { print("FAIL", name); failed += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_000)
func iso(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

// Elapsed: finished runs from `intervals` + the current run from `lastStartedAt`; `duration` only as fallback.
let current = t0.addingTimeInterval(500)
let runs = [TWTimer.Interval(from: t0, to: t0.addingTimeInterval(60)),
            TWTimer.Interval(from: t0.addingTimeInterval(200), to: t0.addingTimeInterval(320)),
            TWTimer.Interval(from: current, to: nil)]
let running = TWTimer(id: 1, running: true, duration: 999, lastStartedAt: current, intervals: runs)
check(running.elapsed(at: t0.addingTimeInterval(530)) == 210, "running: finished runs + current run")
var openWithTo = runs
openWithTo[2].to = current.addingTimeInterval(5)
check(TWTimer(id: 1, running: true, duration: 0, lastStartedAt: current, intervals: openWithTo)
    .elapsed(at: t0.addingTimeInterval(530)) == 210, "running: open run's `to` is ignored")
check(TWTimer(id: 2, running: false, duration: 999, lastStartedAt: current, intervals: Array(runs.prefix(2)))
    .elapsed(at: .distantFuture) == 180, "paused: sum of runs")
check(TWTimer(id: 3, running: true, duration: 600, lastStartedAt: t0).elapsed(at: t0.addingTimeInterval(90)) == 690,
      "no intervals: duration fallback")
check(running.startedAt == t0, "startedAt is the first run")
// Server reports the open run a few ms off lastStartedAt *and* with a `to`: must not count it twice.
let skewed = [runs[0], runs[1], TWTimer.Interval(from: current.addingTimeInterval(0.25), to: current.addingTimeInterval(20))]
check(TWTimer(id: 4, running: true, duration: 0, lastStartedAt: current, intervals: skewed)
    .elapsed(at: t0.addingTimeInterval(530)) == 210, "running: skewed open run not double-counted")
// Most recently used first: B was created later, but A ran last.
let a = TWTimer(id: 1, running: false, duration: 0, lastStartedAt: t0.addingTimeInterval(300),
                intervals: [.init(from: t0.addingTimeInterval(300), to: t0.addingTimeInterval(400))])
let b = TWTimer(id: 2, running: false, duration: 0, lastStartedAt: t0.addingTimeInterval(100),
                intervals: [.init(from: t0.addingTimeInterval(100), to: t0.addingTimeInterval(200))])
check(a.lastActive > b.lastActive, "lastActive orders by last run, not id")

// Decoding: synthetic timer (no live timer was available) + real fixtures.
let decoder = TeamworkClient.makeDecoder()
let timerJSON = """
{"timers":[{"id":7,"running":true,"billable":true,"duration":120,"description":"standup",
  "lastStartedAt":"2026-10-14T09:00:00Z","project":{"id":5,"type":"projects"},"task":{"id":9,"type":"tasks"},
  "intervals":[{"id":1,"from":"2026-10-14T08:00:00Z","to":"2026-10-14T08:02:00Z","duration":120},
               {"id":2,"from":"2026-10-14T09:00:00.250Z","to":null,"duration":0}]}],
 "included":{"projects":{"5":{"id":5,"name":"Website"}},"tasks":[{"id":9,"name":"Fix nav"}]}}
"""
let page = try decoder.decode(TimersResponse.self, from: Data(timerJSON.utf8))
let timer = page.timers[0]
check(timer.projectId == 5 && timer.taskId == 9 && timer.running && timer.intervals.count == 2, "timer refs + intervals")
check(timer.elapsed(at: timer.lastStartedAt!.addingTimeInterval(60)) == 180, "decoded elapsed")
check(page.included.projects["5"]?.name == "Website" && page.included.tasks["9"]?.name == "Fix nav", "included as map and array")

let fixtures = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Checks/fixtures")
func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try decoder.decode(T.self, from: Data(contentsOf: fixtures.appending(path: name)))
}
let me = try fixture(MeResponse.self, "me.json").person
check(me.id == 1001 && me.firstName == "Ada" && me.lengthOfDay == 8, "real: v3 me (incl. 8 h working day)")
let logs = try fixture(TimeEntriesResponse.self, "timelogs.json").timelogs
check(logs.count == 3 && logs[1].minutes == 225 && logs[2].billable && !logs[1].billable, "real: timelogs")
check(logs.allSatisfy { $0.timeLogged != nil && $0.projectId != nil && $0.taskId != nil }, "real: timelog dates + refs")
check(try fixture(ProjectsResponse.self, "projects.json").projects.count == 3, "real: starred projects")
let tasks = try fixture(TasksResponse.self, "tasks.json").tasks
check(tasks.count == 2 && tasks.allSatisfy { $0.projectId == 411598 && $0.tasklistId == 1542561 },
      "real: task's project via tasklist meta")

// Typed durations.
for (input, seconds) in [("1:30", 5400.0), (":45", 2700), ("1.5", 5400), ("1,5", 5400), ("90m", 5400), ("1h30", 5400),
                         ("1h 30m", 5400), ("2h", 7200), ("1.5h", 5400), ("45 min", 2700), ("45 minutes", 2700),
                         ("1hours", 3600), (".5", 1800), ("530", 19800), ("1230", 45000), ("045", 2700),
                         ("0530", 19800), ("5", 18000), ("12", 43200)] {
    check(parseDuration(input) == seconds, "parse \(input)")
}
for bad in ["", "0", "abc", "1:75", "25h", "h", "m30", "1x", "-0:30", "1:-5", "-1", "0x2", "2e1", "1e3", "1.2.3",
            "575", "2530", "12345"] {
    check(parseDuration(bad) == nil, "reject '\(bad)'")
}
for (typed, shown) in [("5", "5"), ("53", "53"), ("530", "5:30"), ("5:301", "53:01"), ("1230", "12:30"), ("12:3", "1:23"),
                       (":45", ":45"), ("1.5h", "1.5h"), ("90m", "90m"), ("12:305", "12:30"), ("", "")] {
    check(durationWithColon(typed, previous: "12:30") == shown, "colon as you type: '\(typed)' → '\(shown)'")
}
check(parseDuration("0:00", allowZero: true) == 0 && parseDuration("0", allowZero: true) == 0
      && parseDuration("24:00", allowZero: true) == 86400 && parseDuration("24:01", allowZero: true) == nil, "a timer's time may be 0:00")

// Rounding: whole minutes to the step; never to zero.
let m = { (minutes: Double) in minutes * 60 }
check(Rounding.up.apply(m(73) + 40, step: 15) == m(75), "round up 1:13 → 1:15")
check(Rounding.down.apply(m(73) + 40, step: 15) == m(60), "round down 1:13 → 1:00")
check(Rounding.nearest.apply(m(67), step: 15) == m(60) && Rounding.nearest.apply(m(68), step: 15) == m(75), "nearest 1:07 / 1:08")
check(Rounding.up.apply(m(75) + 20, step: 15) == m(75), "up: seconds past a step don't add a step")
check(Rounding.down.apply(m(10), step: 15) == m(10), "down never rounds to zero")
check(Rounding.up.apply(m(1), step: 6) == m(6), "up with 6-minute step")
check(Rounding.off.apply(m(73) + 40, step: 15) == m(73) + 40, "off leaves time alone")

// Task links (pasted or dropped).
check(taskID(fromLink: "https://acme.teamwork.com/app/tasks/17505056") == 17505056, "link: app/tasks")
check(taskID(fromLink: "https://acme.teamwork.com/#/tasks/123?c=1") == 123, "link: legacy #/tasks")
check(taskID(fromLink: "https://acme.teamwork.com/tasks/42.json") == 42, "link: .json")
check(taskID(fromLink: "https://acme.teamwork.com/app/tasks/9/comments") == 9, "link: subpage")
check(taskID(fromLink: "https://acme.teamwork.com/app/tasklists/77") == nil, "link: tasklist is not a task")
check(taskID(fromLink: "subtasks/5") == nil && taskID(fromLink: "standup") == nil, "link: not a link")

// Targets: Teamwork's hours per weekday, else lengthOfDay Monday–Friday; a custom day replaces each working day.
var gregorian = Calendar(identifier: .gregorian)
gregorian.timeZone = TimeZone(identifier: "UTC")!
let week = DateInterval(start: iso("2026-10-12T00:00:00Z"), end: iso("2026-10-19T00:00:00Z")) // Mon..Sun
let friday = DateInterval(start: iso("2026-10-16T00:00:00Z"), duration: 86_400)
let saturday = DateInterval(start: iso("2026-10-17T00:00:00Z"), duration: 86_400)
let h = 3600.0
let weekdays = { (length: TimeInterval) in Dictionary(uniqueKeysWithValues: (2...6).map { ($0, length) }) }
let shortFriday = workingDays(teamwork: [2: 7.5 * h, 3: 7.5 * h, 4: 7.5 * h, 5: 7.5 * h, 6: 6 * h, 7: 0], lengthOfDay: 8 * h, custom: nil)
check(workTarget(in: week, days: shortFriday, calendar: gregorian) == 36 * h, "week target sums each weekday's hours")
check(workTarget(in: friday, days: shortFriday, calendar: gregorian) == 6 * h, "a shorter Friday")
check(workTarget(in: saturday, days: shortFriday, calendar: gregorian) == nil, "a 0-hour Saturday has no target")
check(workingDays(teamwork: nil, lengthOfDay: 8 * h, custom: nil) == weekdays(8 * h), "no working hours: lengthOfDay Monday–Friday")
check(workingDays(teamwork: [7: 0], lengthOfDay: 8 * h, custom: nil) == weekdays(8 * h), "all-zero working hours fall back too")
check(workingDays(teamwork: shortFriday, lengthOfDay: 8 * h, custom: 7.5 * h) == weekdays(7.5 * h), "custom day on Teamwork's working days")
check(workingDays(teamwork: [2: 4 * h, 4: 4 * h], lengthOfDay: 8 * h, custom: 7.5 * h) == [2: 7.5 * h, 4: 7.5 * h], "custom keeps days off")
check(workingDays(teamwork: nil, lengthOfDay: nil, custom: 7.5 * h) == weekdays(7.5 * h), "custom without anything from Teamwork")
check(workingDays(teamwork: nil, lengthOfDay: nil, custom: nil).isEmpty, "no target without a length")
check(try fixture(WorkloadResponse.self, "workload.json").hours == [2: 27_000, 3: 27_000, 4: 27_000, 5: 27_000, 6: 21_600],
      "real: working hours per weekday from the workload")

// Formats sent to and shown from Teamwork.
check((5025.0).hoursMinutes == "1:23" && (3599.0).hoursMinutes == "0:59", "h:mm truncates")
check((5025.0).clock == "1:23:45", "clock")
let nine = iso("2026-10-14T09:00:00Z")
check(nine.formatted(.iso8601.year().month().day()) == "2026-10-14", "timelog date")
check(nine.formatted(.iso8601.time(includingFractionalSeconds: false).timeSeparator(.colon)) == "09:00:00", "timelog time")

// Reminders: Monday–Friday, 9:00–17:00.
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
for (date, expected) in [("2026-10-14T09:00:00Z", true), ("2026-10-14T16:59:00Z", true), ("2026-10-14T17:00:00Z", false),
                         ("2026-10-14T08:59:00Z", false), ("2026-10-17T10:00:00Z", false), ("2026-10-18T10:00:00Z", false),
                         ("2026-10-12T10:00:00Z", true), ("2026-10-16T10:00:00Z", true)] {
    check(Reminders.isWorkingHours(iso(date), calendar: utc) == expected, "working hours \(date)")
}

// End-of-day nudge: weekdays from 17:00.
for (date, expected) in [("2026-10-14T17:00:00Z", true), ("2026-10-14T23:30:00Z", true), ("2026-10-14T16:59:00Z", false),
                         ("2026-10-17T18:00:00Z", false)] {
    check(Reminders.isAfterWork(iso(date), calendar: utc) == expected, "after work \(date)")
}

// Sign-in helpers.
check(normalizedSite("acme.teamwork.com") == URL(string: "https://acme.teamwork.com/"), "site: bare host")
check(normalizedSite(" https://acme.eu.teamwork.com/app/home ") == URL(string: "https://acme.eu.teamwork.com/"), "site: pasted URL")
check(normalizedSite("teamwork.example.com") == URL(string: "https://teamwork.example.com/"), "site: custom domain")
check(normalizedSite("acme") == nil, "site: rejects junk")
let redirect = URL(string: "http://localhost:8123/callback")!
func callback(_ target: String, method: String = "GET") -> [String: String] {
    callbackQuery(fromRequest: "\(method) \(target) HTTP/1.1\r\nHost: localhost:8123\r\n\r\n", redirect: redirect, state: "expected")
}
check(callback("/callback?code=abc123&state=expected")["code"] == "abc123", "oauth verified code")
check(callback("/callback?error=access_denied&state=expected")["error"] == "access_denied", "oauth verified error")
for bad in ["/callback?code=abc", "/callback?code=abc&state=wrong", "/wrong?code=abc&state=expected",
            "/callback?code=abc&state=expected&state=wrong", "/callback?code=abc&error=denied&state=expected",
            "/callback?code=&state=expected", "/favicon.ico"] {
    check(callback(bad).isEmpty, "reject oauth callback \(bad)")
}
check(callback("/callback?code=abc&state=expected", method: "POST").isEmpty, "oauth rejects wrong method")
check(callbackQuery(fromRequest: "GET /callback?code=abc&state=expected HTTP/1.1\r\n", redirect: redirect, state: "expected").isEmpty, "oauth waits for complete headers")
check(APIError(status: 403, detail: #"{"errors":[{"title":"Forbidden","detail":"A timer already exists for this task"}]}"#).errorDescription
      == "Teamwork denied access (403). A timer already exists for this task", "403 shows Teamwork's reason")
check(APIError(status: 403, detail: "<html>").errorDescription == "Teamwork denied access (403).", "403 without a reason")
check(callbackQuery(fromRequest: "GET /callback/?code=abc&state=s HTTP/1.1\r\n\r\n", redirect: URL(string: "http://localhost:8123/callback/")!, state: "s")["code"] == "abc",
      "oauth keeps a trailing slash in the redirect path")
check(callbackQuery(fromRequest: "GET /?code=abc&state=s HTTP/1.1\r\n\r\n", redirect: URL(string: "http://localhost:8123")!, state: "s")["code"] == "abc",
      "oauth root redirect")
for good in ["http://localhost:8123", "http://127.0.0.1:1/callback", "http://[::1]:65535/callback"] {
    check(oauthRedirect(good) != nil, "valid redirect \(good)")
}
for bad in ["http://localhost:0", "http://localhost:65536", "http://localhost", "https://localhost:8123",
            "http://evil.example:8123", "http://user@localhost:8123", "http://localhost:8123?x=1"] {
    check(oauthRedirect(bad) == nil, "invalid redirect \(bad)")
}
let stateOne = try Launchpad.makeState(), stateTwo = try Launchpad.makeState()
check(stateOne != stateTwo && Data(base64Encoded: stateOne)?.count == 32, "oauth uses random 256-bit state")
check(URLComponents(url: Launchpad.loginURL(clientID: "client", redirect: redirect, state: stateOne), resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "state", value: stateOne)) == true, "oauth sends state")
check(Launchpad.loginURL(clientID: "client", redirect: redirect, state: "a+b").absoluteString.contains("state=a%2Bb"), "oauth encodes plus in state")
// The app's own redirect (stint://oauth/callback), checked like the loopback one.
check(oauthRedirect("stint://oauth/callback") == appRedirect, "the app redirect is a valid redirect")
for bad in ["stint://oauth/other", "stint://evil/callback", "stint://oauth/callback?x=1", "other://oauth/callback"] {
    check(oauthRedirect(bad) == nil, "invalid redirect \(bad)")
}
func appCallback(_ text: String) -> [String: String] { callbackQuery(fromURL: URL(string: text)!, redirect: appRedirect, state: "expected") }
check(appCallback("stint://oauth/callback?code=abc123&state=expected")["code"] == "abc123", "app redirect verified code")
check(appCallback("STINT://oauth/callback?error=access_denied&state=expected")["error"] == "access_denied", "app redirect verified error")
for bad in ["stint://oauth/callback?code=abc", "stint://oauth/callback?code=abc&state=wrong", "stint://oauth/other?code=abc&state=expected",
            "stint://evil/callback?code=abc&state=expected", "stint://oauth/callback?code=abc&state=expected&state=wrong",
            "stint://oauth/callback?code=abc&error=denied&state=expected", "stint://user@oauth/callback?code=abc&state=expected",
            "other://oauth/callback?code=abc&state=expected"] {
    check(appCallback(bad).isEmpty, "reject app redirect \(bad)")
}
let waiting = Task { try await AppRedirect.waitForCode(state: "expected") }
await Task.yield()
AppRedirect.handle(URL(string: "stint://oauth/callback?code=forged&state=wrong")!)
AppRedirect.handle(URL(string: "stint://oauth/callback?code=abc123&state=expected")!)
check(try await waiting.value == "abc123", "the app redirect hands over the code for this sign-in only")
AppRedirect.handle(URL(string: "stint://oauth/callback?code=late&state=expected")!) // nothing pending: ignored
let denied = Task { try await AppRedirect.waitForCode(state: "expected") }
await Task.yield()
AppRedirect.handle(URL(string: "stint://oauth/callback?error=access_denied&state=expected")!)
do { _ = try await denied.value; check(false, "a refused sign-in fails") } catch { check("\(error.localizedDescription)".contains("access_denied"), "a refused sign-in says why") }
func tokenBody(secret: String?) throws -> [String: String]? {
    let request = try Launchpad.tokenRequest(code: "c", clientID: "id", clientSecret: secret, redirect: appRedirect)
    return try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
}
check(try tokenBody(secret: "s") == ["code": "c", "client_id": "id", "client_secret": "s", "redirect_uri": "stint://oauth/callback"],
      "the token exchange sends the secret when there is one")
check(try tokenBody(secret: nil)?["client_secret"] == nil, "a client without a secret leaves it out")
check(Launchpad.builtIn == nil, "no built-in app without build-time configuration")

// Rate limiting: Retry-After in seconds, capped at 5 minutes; otherwise Teamwork's 60 s.
for (header, delay) in [("120", 120.0), (" 0 ", 0), ("100000", 300), ("-5", 60), ("Wed, 21 Oct 2026 07:28:00 GMT", 60), ("nan", 60)] {
    check(TeamworkClient.retryDelay(header) == delay, "Retry-After \(header) waits \(delay) s")
}
check(TeamworkClient.retryDelay(nil) == 60, "no Retry-After waits 60 s")
check(APIError(status: 429, detail: "").errorDescription?.contains("rate-limiting") == true, "a lasting 429 says so")
do { try Keychain.check(-25308); check(false, "Keychain propagates errors") } catch {}
try Keychain.check(0)
let overlap = TWTimer(id: 8, running: true, duration: 0, lastStartedAt: current, intervals: runs)
check(overlap.trackedTime(from: t0.addingTimeInterval(30), to: t0.addingTimeInterval(530)) == 180, "idle overlaps finished and running intervals")
check(overlap.trackedTime(from: t0.addingTimeInterval(70), to: t0.addingTimeInterval(190)) == 0, "idle excludes paused time")
check(overlap.trackedTime(from: t0.addingTimeInterval(-1000), to: t0.addingTimeInterval(-1)) == 0, "idle excludes time before timer")
check(Credentials(kind: .apiToken, site: URL(string: "https://a.teamwork.com/")!, secret: "tok").authorization
      == "Basic " + Data("tok:x".utf8).base64EncodedString(), "basic auth header")

let badge = MenuBarBadge.image(.badge, running: true, highlight: false, text: "1:30")!
check(MenuBarBadge.image(.badge, running: true, highlight: false, text: "1:30") === badge, "menu badge reuses unchanged image")
check(MenuBarBadge.image(.badge, running: false, highlight: false, text: "1:30") !== badge, "menu badge redraws changed state")
check(badge.isTemplate && MenuBarBadge.image(.badge, running: false, highlight: true, text: "1:30")!.isTemplate
      && !MenuBarBadge.image(.badge, running: true, highlight: true, text: "1:30")!.isTemplate,
      "highlighted badge keeps its brand colour; plain badge follows the menu bar tint")
for (style, text) in [(MenuBarStyle.taskAndTime, "Fix login  1:30"), (.time, "1:30"), (.icon, "")] {
    let pill = MenuBarBadge.image(style, running: true, highlight: true, text: text)
    check(pill?.isTemplate == false, "\(style.rawValue) fills with the brand colour while running")
    check(MenuBarBadge.image(style, running: true, highlight: true, text: text) === pill, "\(style.rawValue) reuses unchanged image")
    check(MenuBarBadge.image(style, running: false, highlight: true, text: text) == nil
          && MenuBarBadge.image(style, running: true, highlight: false, text: text) == nil,
          "\(style.rawValue) keeps its tinted glyph while paused or unhighlighted")
}
check(MenuBarBadge.image(.icon, running: true, highlight: true, text: "")!.size == NSSize(width: 18, height: 18), "icon pill is a square")
check(MenuBarBadge.image(.taskAndTime, running: true, highlight: true, text: "Fix login  1:30")!.size.width
      > MenuBarBadge.image(.time, running: true, highlight: true, text: "1:30")!.size.width, "task pill fits the task")
print(failed == 0 ? "All checks passed." : "\(failed) check(s) failed.")
exit(failed == 0 ? 0 : 1)
