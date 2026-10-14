import Foundation

/// A Teamwork v3 timer (`/projects/api/v3/me/timers`).
struct TWTimer: Decodable, Identifiable, Equatable, Sendable {
    /// One run of the timer; `to` is nil (or unreliable) for the run in progress.
    struct Interval: Decodable, Equatable, Sendable {
        let from: Date
        var to: Date?
    }

    let id: Int
    var description: String
    var running: Bool
    var billable: Bool
    /// Server-reported seconds; only used when `intervals` is empty.
    var duration: Int
    var lastStartedAt: Date?
    var intervals: [Interval]
    var projectId: Int?
    var taskId: Int?

    init(id: Int, description: String = "", running: Bool, billable: Bool = false, duration: Int,
         lastStartedAt: Date?, intervals: [Interval] = [], projectId: Int? = nil, taskId: Int? = nil) {
        self.id = id
        self.description = description
        self.running = running
        self.billable = billable
        self.duration = duration
        self.lastStartedAt = lastStartedAt
        self.intervals = intervals
        self.projectId = projectId
        self.taskId = taskId
    }

    private enum CodingKeys: String, CodingKey {
        case id, description, running, billable, duration, lastStartedAt, intervals, projectId, taskId, project, task
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        billable = try c.decodeIfPresent(Bool.self, forKey: .billable) ?? false
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        lastStartedAt = try c.decodeIfPresent(Date.self, forKey: .lastStartedAt)
        intervals = (try? c.decodeIfPresent([Interval].self, forKey: .intervals)) ?? []
        projectId = try c.decodeIfPresent(Int.self, forKey: .projectId) ?? c.decodeIfPresent(Ref.self, forKey: .project)?.id
        taskId = try c.decodeIfPresent(Int.self, forKey: .taskId) ?? c.decodeIfPresent(Ref.self, forKey: .task)?.id
    }

    /// Finished runs plus the current one. Built from `intervals` so it doesn't depend on what `duration` counts;
    /// the run in progress is always measured from `lastStartedAt`.
    func elapsed(at now: Date = .now) -> TimeInterval {
        let current = running ? lastStartedAt : nil
        guard !intervals.isEmpty else {
            return TimeInterval(duration) + (current.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }
        let finished = intervals.reduce(0.0) { sum, run in
            // The run in progress may carry a `to` and a `from` a few ms off `lastStartedAt`; skip it by time, not equality.
            guard let to = run.to, current.map({ run.from < $0.addingTimeInterval(-1) }) ?? true else { return sum }
            return sum + max(0, to.timeIntervalSince(run.from))
        }
        return finished + (current.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func trackedTime(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        let current = running ? lastStartedAt : nil
        let finished = intervals.reduce(0.0) { sum, run in
            guard let to = run.to, current.map({ run.from < $0.addingTimeInterval(-1) }) ?? true else { return sum }
            return sum + max(0, min(to, end).timeIntervalSince(max(run.from, start)))
        }
        let active = current.map { max(0, end.timeIntervalSince(max($0, start))) } ?? 0
        return min(elapsed(at: end), finished + active)
    }

    /// When the timer first started; this is the start time a time entry should carry.
    var startedAt: Date? { intervals.map(\.from).min() ?? lastStartedAt }

    /// Last time the timer ran, for "most recently used" ordering.
    var lastActive: Date {
        ([lastStartedAt].compactMap { $0 } + intervals.flatMap { [$0.from, $0.to].compactMap { $0 } }).max() ?? .distantPast
    }
}

/// v3 relationship stub, e.g. `{"id": 1, "type": "projects"}`.
private struct Ref: Decodable { let id: Int }

struct Project: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

/// A logged time entry (v3 `timelogs`).
struct TimeEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    var minutes: Int
    var description: String
    var timeLogged: Date?
    var billable: Bool
    var locked: Bool
    var projectId: Int?
    var taskId: Int?

    private enum CodingKeys: String, CodingKey {
        case id, minutes, description, timeLogged, isBillable, billable, isLocked, projectId, taskId, project, task
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        timeLogged = try? c.decodeIfPresent(Date.self, forKey: .timeLogged)
        billable = try c.decodeIfPresent(Bool.self, forKey: .isBillable) ?? c.decodeIfPresent(Bool.self, forKey: .billable) ?? false
        locked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        projectId = try c.decodeIfPresent(Int.self, forKey: .projectId) ?? c.decodeIfPresent(Ref.self, forKey: .project)?.id
        taskId = try c.decodeIfPresent(Int.self, forKey: .taskId) ?? c.decodeIfPresent(Ref.self, forKey: .task)?.id
    }
}

struct TWTask: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    var projectId: Int?
    var tasklistId: Int?

    private enum CodingKeys: String, CodingKey { case id, name, projectId, tasklistId, tasklist }

    /// Tasklist link; its `meta.projectId` names the project without a sideload.
    private struct ListRef: Decodable {
        struct Meta: Decodable { var projectId: Int? }
        let id: Int
        var meta: Meta?
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let list = try? c.decodeIfPresent(ListRef.self, forKey: .tasklist)
        projectId = try c.decodeIfPresent(Int.self, forKey: .projectId) ?? list?.meta?.projectId
        tasklistId = try c.decodeIfPresent(Int.self, forKey: .tasklistId) ?? list?.id
    }
}

struct Tasklist: Decodable, Identifiable, Sendable {
    let id: Int
    var projectId: Int?

    private enum CodingKeys: String, CodingKey { case id, projectId, project }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        projectId = try c.decodeIfPresent(Int.self, forKey: .projectId) ?? c.decodeIfPresent(Ref.self, forKey: .project)?.id
    }
}

/// Sideloaded records. v3 keys them by ID string; arrays are accepted too.
struct Included: Decodable, Sendable {
    var projects: [String: Project] = [:]
    var tasks: [String: TWTask] = [:]
    var tasklists: [String: Tasklist] = [:]

    init() {}

    mutating func merge(_ other: Included) {
        projects.merge(other.projects) { _, new in new }
        tasks.merge(other.tasks) { _, new in new }
        tasklists.merge(other.tasklists) { _, new in new }
    }

    private enum CodingKeys: String, CodingKey { case projects, tasks, tasklists }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = Self.records(c, .projects)
        tasks = Self.records(c, .tasks)
        tasklists = Self.records(c, .tasklists)
    }

    private static func records<T: Decodable & Identifiable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: T] where T.ID == Int {
        if let map = try? c.decodeIfPresent([String: T].self, forKey: key) { return map }
        let list = (try? c.decodeIfPresent([T].self, forKey: key)) ?? []
        return Dictionary(list.map { (String($0.id), $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Something a timer can run on: a project, optionally narrowed to a task. Pins and recents are these.
struct WorkItem: Codable, Hashable, Identifiable, Sendable {
    var projectId: Int
    var projectName: String
    var taskId: Int?
    var taskName: String?
    var description = ""
    var billable = false

    var id: String { "\(projectId)-\(taskId ?? 0)-\(description)" }
    var title: String { taskName ?? projectName }
    var subtitle: String? { taskName == nil ? nil : projectName }

    func sameTarget(as other: WorkItem) -> Bool { projectId == other.projectId && taskId == other.taskId }
}

extension WorkItem {
    init(project: Project) { self.init(projectId: project.id, projectName: project.name) }
}

struct Credentials: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case apiToken, oauth }
    var kind: Kind
    var site: URL
    var secret: String

    var authorization: String {
        switch kind {
        case .apiToken: "Basic " + Data("\(secret):x".utf8).base64EncodedString()
        case .oauth: "Bearer \(secret)"
        }
    }
}

/// "acme.teamwork.com" or a pasted page URL → `https://acme.teamwork.com/`.
func normalizedSite(_ input: String) -> URL? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://" + text }
    guard let host = URLComponents(string: text)?.host, host.contains(".") else { return nil }
    return URL(string: "https://\(host)/")
}

/// Task ID from a pasted or dropped Teamwork link: ".../app/tasks/123", "...#/tasks/123", "/tasks/123.json".
func taskID(fromLink text: String) -> Int? {
    guard let match = text.firstMatch(of: ##/(?:^|[/#])tasks/(\d+)(?:[/?#.]|$)/##) else { return nil }
    return Int(match.1)
}

/// Mondays to Fridays in an interval, for weekly targets.
func weekdays(in interval: DateInterval, calendar: Calendar = .current) -> Int {
    var count = 0
    var day = calendar.startOfDay(for: interval.start)
    while day < interval.end {
        if (2...6).contains(calendar.component(.weekday, from: day)) { count += 1 }
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return count
}

/// Query items of the browser's loopback request, e.g. "GET /?code=abc HTTP/1.1" → ["code": "abc"].
func oauthRedirect(_ input: String) -> URL? {
    guard let url = URL(string: input), url.scheme == "http",
          ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? ""),
          let port = url.port, (1...65535).contains(port),
          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
    return url
}

func callbackQuery(fromRequest request: String, redirect: URL, state: String) -> [String: String] {
    guard request.contains("\r\n\r\n") else { return [:] }
    let requestLine = request.components(separatedBy: "\r\n").first ?? ""
    let parts = requestLine.split(separator: " ")
    guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
          parts[1].hasPrefix("/"), !parts[1].hasPrefix("//"),
          let url = URLComponents(string: "http://localhost" + parts[1]),
          url.path == (redirect.path.isEmpty ? "/" : redirect.path) else { return [:] }
    let items = url.queryItems ?? []
    guard Set(items.map(\.name)).count == items.count else { return [:] }
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    guard query["state"] == state,
          (query["code"]?.isEmpty == false) != (query["error"]?.isEmpty == false) else { return [:] }
    return query
}

/// Automatic rounding of logged time (Settings › General › Time Logs).
enum Rounding: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case up = "Round up"
    case down = "Round down"
    case nearest = "Round to nearest"
    var id: Self { self }

    static let steps = [5, 6, 10, 15, 30, 60]

    /// Rounds the whole minutes in `seconds` to multiples of `step` minutes (Teamwork logs whole minutes,
    /// so 1:15:20 rounds up to 1:15, not 1:30). Never rounds to zero: the exact time is kept instead.
    func apply(_ seconds: TimeInterval, step: Int) -> TimeInterval {
        guard self != .off, step > 0 else { return seconds }
        let steps = Double(Int(seconds) / 60) / Double(step)
        let rounded = switch self {
        case .up: steps.rounded(.up)
        case .down: steps.rounded(.down)
        case .nearest, .off: steps.rounded(.toNearestOrAwayFromZero)
        }
        let minutes = Int(rounded) * step
        return minutes > 0 ? TimeInterval(minutes * 60) : seconds
    }
}

/// Typed durations: "1:30", ":45", "1.5", "1,5" (hours), "90m", "1h30", "1h 30m", "2h".
/// A bare number means hours, as in Harvest. Returns nil for empty, zero or over-24h input.
func parseDuration(_ input: String) -> TimeInterval? {
    let text = input.lowercased().replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
    // Digits, separators and unit letters only: rules out "-0:30", "1:-5", hex like "0x2", "1e3".
    guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || ".:hrsouminte".contains($0)) }) else { return nil }
    var hours = 0.0

    if text.contains(":") {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let m = Double(parts[1]), m < 60, parts[1].count == 2 || parts[1].count == 1 else { return nil }
        let h = parts[0].isEmpty ? 0 : Double(parts[0])
        guard let h else { return nil }
        hours = h + m / 60
    } else if text.wholeMatch(of: #/\d+(\.\d+)?|\.\d+/#) != nil, let plain = Double(text) {
        hours = plain
    } else {
        // "1.5h", "90m", "1h30", "1h30m"; minutes without a unit only after hours.
        let units = #/^(?:(\d+(?:\.\d+)?)(?:h|hr|hrs|hour|hours))?(?:(\d+(?:\.\d+)?)(?:m|min|mins|minute|minutes)?)?$/#
        guard let match = text.wholeMatch(of: units), match.1 != nil || match.2 != nil else { return nil }
        hours = (match.1.flatMap { Double($0) } ?? 0) + (match.2.flatMap { Double($0) } ?? 0) / 60
    }

    let seconds = (hours * 3600).rounded()
    return seconds > 0 && seconds <= 24 * 3600 ? seconds : nil
}

extension TimeInterval {
    /// "1:23" — truncated, never rounded up (the old app showed "0h 60m").
    var hoursMinutes: String {
        Duration.seconds(self).formatted(.time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .down)))
    }
    /// "1:23:04"
    var clock: String { Duration.seconds(self).formatted(.time(pattern: .hourMinuteSecond)) }
    /// "1h 23m" for spoken and log labels.
    var spoken: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .wide, zeroValueUnits: .hide,
                                                fractionalPart: .hide(rounded: .down)))
    }
}
