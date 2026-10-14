import Foundation

final class MockState: @unchecked Sendable {
    let lock = NSLock()
    var mode = "normal"
    var calls: [String] = []
    var posts: [Int: Int] = [:]
    var removed: Set<Int> = []
    var failedSecond = false
    var deleteFails = false
    var delay = false
    var delayedStarted = false
    var user = 1
    func response(_ request: URLRequest) -> (Int, String, Double) {
        lock.withLock {
            let url = request.url!, path = url.path, verb = request.httpMethod ?? "GET"
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems?.first { $0.name == "page" }?.value ?? "1"
            calls.append("\(url.host!) \(verb) \(path)?page=\(page)")
            if path.hasSuffix("/me.json") { return (200, "{\"person\":{\"id\":\(user),\"firstName\":\"Test\",\"lastName\":\"User\"}}", 0) }
            if verb == "POST", path.hasSuffix("/timers.json") { return (403, "{}", 0) }
            if verb == "POST", path.hasSuffix("/time.json") {
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
            if verb == "DELETE", path.contains("/timers/") {
                if deleteFails { return (500, "{}", 0) }
                removed.insert(Int(path.split(separator: "/").last!.split(separator: ".").first!)!)
                return (204, "", 0)
            }
            if path.hasSuffix("/timers.json") {
                let ids = [1, 2].filter { !removed.contains($0) }
                let rows = ids.map { "{\"id\":\($0),\"running\":false,\"duration\":600,\"projectId\":\($0 == 1 ? 101 : 202)}" }.joined(separator: ",")
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
