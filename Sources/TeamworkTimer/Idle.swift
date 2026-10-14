import AppKit
import CoreGraphics

/// Notices idle time (no input, or sleep) while a timer runs and asks what to do once you're back.
/// The old app paused silently and still counted the time before it noticed.
@MainActor
final class IdleMonitor {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "idleEnabled") as? Bool ?? true }
    static var threshold: TimeInterval { TimeInterval(UserDefaults.standard.object(forKey: "idleMinutes") as? Int ?? 10) * 60 }
    private static let anyInput = CGEventType(rawValue: ~0)!

    private weak var store: Store?
    private var idleSince: Date?
    private var idleTimerID: Int?
    private var idleSession: UUID?
    private var sleptAt: Date?
    private var sleptSession: UUID?
    private var prompting = false

    init(store: Store) {
        self.store = store
        Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
                self?.sleptAt = .now
                self?.sleptSession = self?.store?.sessionID
            }
        }
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                self?.woke()
            }
        }
    }

    func reset() {
        idleSince = nil
        idleTimerID = nil
        idleSession = nil
        sleptAt = nil
        sleptSession = nil
    }

    private func tick() {
        guard Self.enabled, let store else { reset(); return }
        guard !prompting else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        let lastInput = Date.now.addingTimeInterval(-idle)
        if let since = idleSince {
            // Any input after the idle period began means you're back, even if you're reading right now.
            if lastInput > since.addingTimeInterval(1) {
                idleSince = nil
                if idleSession == store.sessionID, let id = idleTimerID,
                   let timer = store.timers.first(where: { $0.id == id }) {
                    prompt(timer, from: since, to: lastInput, session: store.sessionID)
                }
            }
        } else if idle >= Self.threshold, let timer = store.runningTimer {
            idleSince = lastInput
            idleTimerID = timer.id
            idleSession = store.sessionID
        }
    }

    private func woke() {
        let slept = sleptAt
        let session = sleptSession
        sleptAt = nil
        sleptSession = nil
        guard Self.enabled, !prompting, let store, let slept, let session, session == store.sessionID,
              Date.now.timeIntervalSince(slept) >= Self.threshold else { return }
        let since = min(slept, idleSince ?? slept)
        idleSince = nil
        prompting = true
        // Timers may have changed elsewhere while asleep; ask about the current state.
        Task {
            defer { prompting = false; idleSince = nil }
            await store.refresh()
            guard store.sessionID == session else { return }
            let end = Date.now
            for timer in store.timers where timer.trackedTime(from: since, to: end) > 0 {
                prompt(timer, from: since, to: end, session: session)
            }
        }
    }

    private func prompt(_ timer: TWTimer, from since: Date, to end: Date, session: UUID) {
        guard let store, store.sessionID == session else { return }
        prompting = true
        defer { prompting = false }
        let seconds = timer.trackedTime(from: since, to: end)
        guard seconds > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "You were away for \(seconds.spoken)"
        alert.informativeText = "From \(since.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened)), while “\(store.title(of: timer))” was running."
        alert.addButton(withTitle: "Remove and Continue")
        alert.addButton(withTitle: "Remove and Stop")
        alert.addButton(withTitle: "Keep Time").keyEquivalent = "\u{1b}"
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await store.removeIdle(from: since, to: end, timer: timer, session: session, stop: false) }
        case .alertSecondButtonReturn: Task { await store.removeIdle(from: since, to: end, timer: timer, session: session, stop: true) }
        default: break
        }
    }
}
