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
    private var sleptAt: Date?
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
            }
        }
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                self?.woke()
            }
        }
    }

    private func tick() {
        guard Self.enabled, store?.runningTimer != nil else { idleSince = nil; return }
        guard !prompting else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        let lastInput = Date.now.addingTimeInterval(-idle)
        if let since = idleSince {
            // Any input after the idle period began means you're back, even if you're reading right now.
            if lastInput > since.addingTimeInterval(1) {
                idleSince = nil
                prompt(from: since, to: lastInput)
            }
        } else if idle >= Self.threshold {
            idleSince = lastInput
        }
    }

    private func woke() {
        let slept = sleptAt
        sleptAt = nil
        guard Self.enabled, !prompting, let slept, Date.now.timeIntervalSince(slept) >= Self.threshold else { return }
        let since = min(slept, idleSince ?? slept)
        idleSince = nil
        // Timers may have changed elsewhere while asleep; ask about the current state.
        Task {
            await store?.refresh()
            prompt(from: since, to: .now)
        }
    }

    private func prompt(from since: Date, to end: Date) {
        guard let store, let timer = store.runningTimer else { return }
        prompting = true
        defer { prompting = false }
        let seconds = end.timeIntervalSince(since)

        let alert = NSAlert()
        alert.messageText = "You were away for \(seconds.spoken)"
        alert.informativeText = "From \(since.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened)), while “\(store.title(of: timer))” was running."
        alert.addButton(withTitle: "Remove and Continue")
        alert.addButton(withTitle: "Remove and Stop")
        alert.addButton(withTitle: "Keep Time").keyEquivalent = "\u{1b}"
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await store.removeIdle(seconds, from: timer, stop: false) }
        case .alertSecondButtonReturn: Task { await store.removeIdle(seconds, from: timer, stop: true) }
        default: break
        }
    }
}
