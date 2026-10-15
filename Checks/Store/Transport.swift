import Foundation

final class MockState: @unchecked Sendable {
    let lock = NSLock()
    var mode = "normal"
    var calls: [String] = []
    /// The last POSTed timelog body.
    var body: [String: Any]?
    var posts: [Int: Int] = [:]
    var removed: Set<Int> = []
    var failedSecond = false
    var deleteFails = false
    var delay = false
    var delayedStarted = false
    var user = 1
    /// Timer seconds set through `seconds` on PUT (paused timers, default 600), and running timers' start.
    var durations: [Int: Int] = [:]
    var running: [Int: Date] = [:]
    /// URLSession hands protocols the body as a stream.
    static func json(_ request: URLRequest) -> [String: Any]? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 { data.append(buffer, count: count) }
        stream.close()
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    func response(_ request: URLRequest) -> (Int, String, Double) {
        lock.withLock {
            let url = request.url!, path = url.path, verb = request.httpMethod ?? "GET"
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems?.first { $0.name == "page" }?.value ?? "1"
            calls.append("\(url.host!) \(verb) \(path)?page=\(page)")
            if path.hasSuffix("/me.json") { return (200, "{\"person\":{\"id\":\(user),\"firstName\":\"Test\",\"lastName\":\"User\"}}", 0) }
            if path.hasSuffix("/workload.json") {
                return (200, "{\"included\":{\"workingHourEntries\":{\"1\":{\"weekday\":\"thursday\",\"taskHours\":7.5},\"2\":{\"weekday\":\"friday\",\"taskHours\":6}}}}", 0)
            }
            if verb == "POST", path.hasSuffix("/timers.json") { return (403, "{}", 0) }
            if verb == "POST", path.hasSuffix("/time.json") {
                body = Self.json(request)
                let id = Int(path.split(separator: "/").dropLast().last!)!
                if mode == "partial", id == 202, !failedSecond { failedSecond = true; return (403, "{}", 0) }
                posts[id, default: 0] += 1
                if mode == "uncertain" { return (500, "{}", 0) }
                return (201, "{}", delay ? 0.15 : 0)
            }
            if verb == "PUT", path.hasSuffix("/complete.json") {
                removed.insert(Int(path.split(separator: "/").dropLast().last!)!)
                return (200, "{}", 0)
            }
            // Edit: `seconds` replaces the runs with one that long; "ignore-seconds" plays a server that drops it,
            // "put-fails" one that can't be reached.
            if verb == "PUT", path.contains("/timers/"), let id = Int(path.split(separator: "/").last!.dropLast(5)) {
                if mode == "put-fails" { return (503, "{}", 0) }
                if mode != "ignore-seconds", let seconds = (Self.json(request)?["timer"] as? [String: Any])?["seconds"] as? Int {
                    if running[id] != nil { running[id] = .now.addingTimeInterval(-Double(seconds)) } else { durations[id] = seconds }
                }
                return (200, "{}", 0)
            }
            if verb == "DELETE", path.contains("/timers/") {
                if deleteFails { return (500, "{}", 0) }
                removed.insert(Int(path.split(separator: "/").last!.split(separator: ".").first!)!)
                return (204, "", 0)
            }
            if path.hasSuffix("/timers.json"), mode == "offline-once" { mode = "normal"; return (503, "{}", 0) }
            if path.hasSuffix("/timers.json") {
                let ids = [1, 2].filter { !removed.contains($0) }
                let rows = ids.map { id in
                    let started = running[id].map { ",\"running\":true,\"lastStartedAt\":\"\($0.formatted(.iso8601))\"" } ?? ",\"running\":false"
                    return "{\"id\":\(id),\"duration\":\(running[id] == nil ? durations[id] ?? 600 : 0),\"projectId\":\(id == 1 ? 101 : 202)\(started)}"
                }.joined(separator: ",")
                if mode == "late", url.host == "a.teamwork.com", !delayedStarted {
                    delayedStarted = true
                    return (200, "{\"timers\":[{\"id\":999,\"description\":\"A private notes\",\"running\":false,\"duration\":60,\"projectId\":101}],\"included\":{}}", 0.3)
                }
                return (200, "{\"timers\":[\(rows)],\"included\":{}}", 0)
            }
            if mode == "pagination" || mode == "empty-page" {
                let number = Int(page)!, more = number == 1
                let meta = "\"meta\":{\"page\":{\"hasMore\":\(more)}}"
                if path.hasSuffix("/projects.json") { return (200, "{\(meta),\"projects\":[{\"id\":\(number),\"name\":\"P\(number)\"}]}", 0) }
                if path.hasSuffix("/tasks.json") { return (200, "{\(meta),\"tasks\":[{\"id\":\(number),\"name\":\"T\(number)\",\"projectId\":101}],\"included\":{}}", 0) }
                if path.hasSuffix("/time.json") {
                    let rows = mode == "empty-page" && !more ? "" : "{\"id\":\(number),\"minutes\":30,\"timeLogged\":\"2026-10-14T09:00:00Z\"}"
                    return (200, "{\(meta),\"timelogs\":[\(rows)],\"included\":{\"projects\":{\"\(number)\":{\"id\":\(number),\"name\":\"P\(number)\"}}}}", 0)
                }
            }
            if path.hasSuffix("/time.json") { return (200, "{\"timelogs\":[],\"included\":{}}", 0) }
            if path.hasSuffix("/projects.json") { return (200, "{\"projects\":[]}", 0) }
            return (200, "{}", 0)
        }
    }
}
final class MockProtocol: URLProtocol, @unchecked Sendable {
    static let state = MockState()
    private let stopped = NSLock()
    private var cancelled = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body, delay) = Self.state.response(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            guard !stopped.withLock({ cancelled }) else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopped.withLock { cancelled = true } }
}
