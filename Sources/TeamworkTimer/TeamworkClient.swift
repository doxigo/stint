import Foundation

struct APIError: LocalizedError {
    let status: Int
    let detail: String

    var errorDescription: String? {
        switch status {
        case 401: "Teamwork rejected the sign-in (401). Sign in again in Settings."
        case 403: "Teamwork denied access (403)."
        default: "Teamwork returned \(status). \(detail)"
        }
    }
}

/// The only HTTP layer. v3 for timers, projects and tasks; v1 where v3 has no equivalent (me, star).
actor TeamworkClient {
    let credentials: Credentials
    private let decoder = TeamworkClient.makeDecoder()

    init(credentials: Credentials) { self.credentials = credentials }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(text)"))
        }
        return decoder
    }

    // MARK: Account

    /// The signed-in person; doubles as a credentials check. `dayLength` is their working day, in seconds.
    func me() async throws -> (id: Int, name: String, dayLength: TimeInterval?) {
        let me = try await get(MeResponse.self, "projects/api/v3/me.json").person
        return (me.id, "\(me.firstName) \(me.lastName)".trimmingCharacters(in: .whitespaces),
                me.lengthOfDay.flatMap { $0 > 0 ? $0 * 3600 : nil })
    }

    // MARK: Timers

    func timers() async throws -> TimersResponse {
        try await getPages(TimersResponse.self, "projects/api/v3/me/timers.json",
                      [.init(name: "include", value: "projects,tasks"), .init(name: "pageSize", value: "50")])
    }

    func startTimer(_ item: WorkItem) async throws {
        var timer: [String: Any] = [
            "projectId": item.projectId, "description": item.description, "isBillable": item.billable,
            "isRunning": true, "stopRunningTimers": true,
        ]
        if let taskId = item.taskId { timer["taskId"] = taskId }
        try await send("POST", "projects/api/v3/me/timers.json", body: ["timer": timer])
    }

    func pause(_ id: Int) async throws { try await send("PUT", "projects/api/v3/me/timers/\(id)/pause.json") }
    func resume(_ id: Int) async throws { try await send("PUT", "projects/api/v3/me/timers/\(id)/resume.json") }
    /// Turns the timer into a time entry and deletes it.
    func complete(_ id: Int) async throws { try await send("PUT", "projects/api/v3/me/timers/\(id)/complete.json") }
    func delete(_ id: Int) async throws {
        do { try await send("DELETE", "projects/api/v3/me/timers/\(id).json") }
        catch let error as APIError where error.status == 404 { return }
    }

    /// Sends the whole timer (not just the changed fields) in case the edit endpoint replaces rather than merges.
    /// `target` moves the timer to another project/task; its tracked time stays.
    func update(_ timer: TWTimer, target: WorkItem? = nil, description: String, billable: Bool) async throws {
        var body: [String: Any] = ["description": description, "isBillable": billable, "isRunning": timer.running]
        if let projectId = target?.projectId ?? timer.projectId { body["projectId"] = projectId }
        if let target {
            body["taskId"] = target.taskId.map { $0 as Any } ?? NSNull() // project-only clears the task
        } else if let taskId = timer.taskId {
            body["taskId"] = taskId
        }
        try await send("PUT", "projects/api/v3/me/timers/\(timer.id).json", body: ["timer": body])
    }

    // MARK: Time entries

    /// Logs time directly (used when the duration was edited or idle time removed). Minutes are truncated.
    func logTime(projectId: Int, taskId: Int?, seconds: TimeInterval, start: Date,
                 description: String, billable: Bool, markTaskComplete: Bool) async throws {
        let path = taskId.map { "projects/api/v3/tasks/\($0)/time.json" } ?? "projects/api/v3/projects/\(projectId)/time.json"
        try await send("POST", path, body: [
            "timelog": Self.timelog(seconds: seconds, start: start, description: description, billable: billable),
            "timelogOptions": ["markTaskComplete": markTaskComplete],
        ])
    }

    /// Edits a logged entry (PATCH merges the given fields).
    func updateEntry(_ id: Int, seconds: TimeInterval, start: Date, description: String, billable: Bool) async throws {
        try await send("PATCH", "projects/api/v3/time/\(id).json", body: [
            "timelog": Self.timelog(seconds: seconds, start: start, description: description, billable: billable),
        ])
    }

    func deleteEntry(_ id: Int) async throws { try await send("DELETE", "projects/api/v3/time/\(id).json") }

    /// Timelog body: start as UTC date + time with `isUtc`, duration as whole hours + minutes.
    private static func timelog(seconds: TimeInterval, start: Date, description: String, billable: Bool) -> [String: Any] {
        let minutes = Int(seconds) / 60
        return [
            "date": start.formatted(.iso8601.year().month().day()),
            "time": start.formatted(.iso8601.time(includingFractionalSeconds: false).timeSeparator(.colon)),
            "isUtc": true, "hasStartTime": true,
            "hours": minutes / 60, "minutes": minutes % 60,
            "description": description, "isBillable": billable,
        ]
    }

    /// A single task as a startable item (for pasted or dropped task links).
    func task(_ id: Int) async throws -> WorkItem? {
        let page = try await get(TaskResponse.self, "projects/api/v3/tasks/\(id).json",
                                 [.init(name: "include", value: "projects,tasklists")])
        let listProject = page.task.tasklistId.flatMap { page.included.tasklists[String($0)]?.projectId }
        guard let projectId = page.task.projectId ?? listProject else { return nil }
        return WorkItem(projectId: projectId, projectName: page.included.projects[String(projectId)]?.name ?? "Project \(projectId)",
                        taskId: page.task.id, taskName: page.task.name)
    }

    /// The user's entries between two local calendar days, inclusive.
    func timeEntries(userId: Int, from: Date, to: Date) async throws -> TimeEntriesResponse {
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        return try await getPages(TimeEntriesResponse.self, "projects/api/v3/time.json", [
            .init(name: "startDate", value: from.formatted(day)), .init(name: "endDate", value: to.formatted(day)),
            .init(name: "assignedToUserIds", value: String(userId)), .init(name: "include", value: "projects,tasks"),
            .init(name: "orderBy", value: "date"), .init(name: "orderMode", value: "desc"),
            .init(name: "pageSize", value: "250"),
        ])
    }

    enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
        case today, overdue, upcoming, anytime
        var id: Self { self }
    }

    func myTasks(userId: Int, filter: TaskFilter) async throws -> [WorkItem] {
        try await tasks([
            .init(name: "responsiblePartyIds", value: String(userId)), .init(name: "taskFilter", value: filter.rawValue),
            .init(name: "orderBy", value: "duedate"),
        ], projectId: nil, projectName: nil)
    }

    // MARK: Projects & tasks

    func starredProjects() async throws -> [Project] {
        try await getPages(ProjectsResponse.self, "projects/api/v3/projects.json", [
            .init(name: "onlyStarredProjects", value: "true"), .init(name: "orderBy", value: "name"),
            .init(name: "pageSize", value: "100"),
        ]).projects
    }

    func projects(matching query: String) async throws -> [Project] {
        try await get(ProjectsResponse.self, "projects/api/v3/projects.json", [
            .init(name: "searchTerm", value: query), .init(name: "orderBy", value: "name"),
            .init(name: "pageSize", value: "10"),
        ]).projects
    }

    /// Tasks as startable work items; `projectId` scopes the search to one project.
    func tasks(matching query: String, projectId: Int?, projectName: String?) async throws -> [WorkItem] {
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(.init(name: "searchTerm", value: query)) }
        if let projectId { items.append(.init(name: "projectIds", value: String(projectId))) }
        // Search-as-you-type across every project takes the first page only, like project search: walking all
        // pages could mean dozens of requests per pause in typing. A project's own list stays complete.
        return try await tasks(items, projectId: projectId, projectName: projectName, allPages: projectId != nil || query.isEmpty)
    }

    private func tasks(_ filters: [URLQueryItem], projectId: Int?, projectName: String?, allPages: Bool = true) async throws -> [WorkItem] {
        let items = filters + [.init(name: "include", value: "projects,tasklists"), .init(name: "pageSize", value: "50")]
        let page = allPages ? try await getPages(TasksResponse.self, "projects/api/v3/tasks.json", items)
                            : try await get(TasksResponse.self, "projects/api/v3/tasks.json", items)
        return page.tasks.compactMap { task in
            let listProject = task.tasklistId.flatMap { page.included.tasklists[String($0)]?.projectId }
            guard let pid = task.projectId ?? listProject ?? projectId else { return nil }
            let name = page.included.projects[String(pid)]?.name ?? projectName ?? "Project \(pid)"
            return WorkItem(projectId: pid, projectName: name, taskId: task.id, taskName: task.name)
        }
    }

    func setStarred(_ projectId: Int, _ starred: Bool) async throws {
        try await send("PUT", "projects/\(projectId)/\(starred ? "star" : "unstar").json")
    }

    // MARK: Transport

    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        try decoder.decode(T.self, from: try await send("GET", path, query: query))
    }

    private func getPages<T: PaginatedResponse>(_ type: T.Type, _ path: String, _ query: [URLQueryItem]) async throws -> T {
        var result = try await get(type, path, query + [.init(name: "page", value: "1")])
        var more = result.meta?.page.hasMore ?? false
        var page = 1
        while more {
            page += 1
            let next = try await get(type, path, query + [.init(name: "page", value: String(page))])
            guard next.itemCount > 0 else { break } // hasMore can be set when the previous page was exactly full
            let count = result.itemCount
            result.append(next)
            more = next.meta?.page.hasMore ?? false
            guard !more || result.itemCount > count else { throw SignInError("Teamwork repeated a page before the list was complete.") }
        }
        return result
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        try Task.checkCancellation()
        var components = URLComponents(url: credentials.site.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" alone, which servers read as a space ("C++" → "C  ").
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, detail: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }
}

// MARK: Responses

struct ResponseMeta: Decodable, Sendable {
    struct Page: Decodable, Sendable { let hasMore: Bool }
    let page: Page
}

private protocol PaginatedResponse: Decodable {
    var meta: ResponseMeta? { get }
    var itemCount: Int { get }
    mutating func append(_ page: Self)
}

private extension Array where Element: Identifiable {
    mutating func appendNew(_ items: [Element]) {
        var seen = Set(map(\.id))
        append(contentsOf: items.filter { seen.insert($0.id).inserted })
    }
}

struct TimersResponse: Decodable, Sendable, PaginatedResponse {
    var timers: [TWTimer]
    var included: Included
    var meta: ResponseMeta?
    var itemCount: Int { timers.count }
    mutating func append(_ page: Self) { timers.appendNew(page.timers); included.merge(page.included); meta = page.meta }

    private enum CodingKeys: String, CodingKey { case timers, included, meta }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timers = try c.decode([TWTimer].self, forKey: .timers)
        meta = try c.decodeIfPresent(ResponseMeta.self, forKey: .meta)
        included = (try? c.decode(Included.self, forKey: .included)) ?? Included()
    }
}

struct ProjectsResponse: Decodable, Sendable, PaginatedResponse {
    var projects: [Project]
    var meta: ResponseMeta?
    var itemCount: Int { projects.count }
    mutating func append(_ page: Self) { projects.appendNew(page.projects); meta = page.meta }
}

struct TasksResponse: Decodable, Sendable, PaginatedResponse {
    var tasks: [TWTask]
    var included: Included
    var meta: ResponseMeta?
    var itemCount: Int { tasks.count }
    mutating func append(_ page: Self) { tasks.appendNew(page.tasks); included.merge(page.included); meta = page.meta }

    private enum CodingKeys: String, CodingKey { case tasks, included, meta }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decode([TWTask].self, forKey: .tasks)
        meta = try c.decodeIfPresent(ResponseMeta.self, forKey: .meta)
        included = (try? c.decode(Included.self, forKey: .included)) ?? Included()
    }
}

struct TimeEntriesResponse: Decodable, Sendable, PaginatedResponse {
    var timelogs: [TimeEntry]
    var included: Included
    var meta: ResponseMeta?
    var itemCount: Int { timelogs.count }
    mutating func append(_ page: Self) { timelogs.appendNew(page.timelogs); included.merge(page.included); meta = page.meta }

    private enum CodingKeys: String, CodingKey { case timelogs, included, meta }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timelogs = try c.decode([TimeEntry].self, forKey: .timelogs)
        meta = try c.decodeIfPresent(ResponseMeta.self, forKey: .meta)
        included = (try? c.decode(Included.self, forKey: .included)) ?? Included()
    }
}

struct TaskResponse: Decodable, Sendable {
    let task: TWTask
    let included: Included

    private enum CodingKeys: String, CodingKey { case task, included }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        task = try c.decode(TWTask.self, forKey: .task)
        included = (try? c.decode(Included.self, forKey: .included)) ?? Included()
    }
}

struct MeResponse: Decodable, Sendable {
    struct Person: Decodable, Sendable {
        let id: Int
        let firstName: String
        let lastName: String
        /// Working day in hours (e.g. 8).
        var lengthOfDay: Double?
    }
    let person: Person
}
