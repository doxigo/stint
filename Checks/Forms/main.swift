// Return submits what was typed. SwiftUI runs the default button's action from an earlier render (see Forms.swift),
// so "2h30m" + Return once left a running 1:00 timer at 1:00 and Log All logged the old times. Real forms in an
// offscreen window, typed into with key events, against the mock Teamwork (Checks/Store/Transport.swift).
// Synchronous top-level code: awaiting at the top level ends the process once AppKit's event loop is involved.
import AppKit
import SwiftUI

var failed = 0
@MainActor func check(_ ok: Bool, _ name: String) {
    if !ok { print("FAIL", name); failed += 1 }
}
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [MockProtocol.self]
TeamworkClient.session = URLSession(configuration: configuration)
let state = MockProtocol.state
let suite = "TeamworkTimerFormChecks.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = Store(defaults: defaults, logDirectory: URL.temporaryDirectory.appending(path: suite), polls: false)
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.finishLaunching()

/// Turns the run loop (key events, SwiftUI updates, the main actor's tasks).
@MainActor func settle(_ seconds: Double) {
    let end = Date.now + seconds
    while Date.now < end {
        if let event = NSApp.nextEvent(matching: .any, until: .now + 0.005, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
    }
}
final class Done { var done = false }
@MainActor func wait(_ work: @escaping @MainActor () async -> Void) {
    let box = Done()
    Task { await work(); box.done = true }
    while !box.done { settle(0.01) }
}
final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func submit(_ form: some View, typing text: String) {
    let window = KeyWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 500, height: 600), styleMask: .borderless,
                           backing: .buffered, defer: false)
    window.contentViewController = NSHostingController(rootView: form.environment(store))
    window.orderFrontRegardless()
    window.makeKey()
    settle(0.3)
    func field(in view: NSView) -> SelectAllField? { view as? SelectAllField ?? view.subviews.lazy.compactMap(field).first }
    window.makeFirstResponder(field(in: window.contentView!))
    let codes: [Character: UInt16] = ["0": 29, "2": 19, "3": 20, "h": 4, "m": 46, "\r": 36]
    for c in text + "\r" {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            NSApp.postEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: String(c),
                                             charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: codes[c]!)!, atStart: false)
        }
        settle(0.1) // a turn between keys, as when typing
    }
    settle(1)
    window.orderOut(nil)
}
let timer = { (id: Int) in store.timers.first { $0.id == id }! }
let postedMinutes = { state.lock.withLock { (state.body?["timelog"] as? [String: Any]).map { ($0["hours"] as! Int) * 60 + ($0["minutes"] as! Int) } } }
let reset = { state.lock.withLock { state.body = nil; state.posts = [:]; state.durations = [:]; state.running = [2: .now - 3600] } }

reset()
wait { try? await store.signIn(site: "forms.teamwork.com", token: "placeholder"); await store.refresh() }
submit(EditTimerView(timer: timer(2)) {}, typing: "2h30m")
check(timer(2).running && store.elapsed(timer(2)).hoursMinutes == "2:30", "Return in Edit Timer sets a running 1:00 timer to 2h30m")
let entry = try JSONDecoder().decode(TimeEntry.self, from: Data(#"{"id":5,"minutes":60,"projectId":101}"#.utf8))
submit(EditEntryView(entry: entry) {}, typing: "2h30m")
check(postedMinutes() == 150, "Return in Edit Entry saves 2h30m")
reset()
wait { await store.refresh() }
submit(LogAllView {}, typing: "2h30m") // into the first row: the running timer at 1:00
check(postedMinutes() == 150 && state.lock.withLock { state.posts[202] == 1 }, "Return in Log All logs the 2h30m typed")
print(failed == 0 ? "All form checks passed." : "\(failed) form check(s) failed.")
exit(failed == 0 ? 0 : 1)
